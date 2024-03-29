function Invoke-CosmosStoredProcedure
{
<#
.SYNOPSIS
    Call stored procedure

.DESCRIPTION
    Calls stored procedure.
    Command supports parallel processing.
    Note: Stored procedures that return large dataset also support continuation token, however, continuation token must be passed as parameter, corretly passed to query inside store procedure logivc, and returned as part of stored procedure response.
      This means that stored procedure logic is fully responsible for handling paging via continuation tokens. 
      For details, see Cosmos DB server side programming reference
    
.OUTPUTS
    Response describing result of operation

.EXAMPLE
    $params = @('123', 'test')
    $rsp = Invoke-CosmosStoredProcedure -Name testSP -Parameters ($params | ConvertTo-Json) -Collection 'docs' -PartitionKey 'test-docs'
    $rsp

    Description
    -----------
    This command calls stored procedure and shows result.
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
            #Name of stored procedure to call
        $Name,

        [Parameter(ValueFromPipeline)]
        [string]
            #Array of parameters to pass to stored procedure, serialized to JSON string
            #When passing array of objects as single parameter, be sure that array is properly formatted so as it is a single parameter object rather than array of parameters
        $Parameters,

        [Parameter()]
        [string[]]
            #Partition key identifying partition to operate upon.
            #Stored procedures are currently required to operate upon single partition only
        $PartitionKey,

        [Parameter(Mandatory)]
        [string]
            #Name of collection containing the stored procedure to call
        $Collection,

        [Parameter()]
        [int]
            #Degree of paralelism for pipelinr processing
        $BatchSize = 1,

        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($Context.Endpoint)/colls/$collection/sprocs"
        $outstandingRequests=@()
    }

    process
    {
        $rq = Get-CosmosRequest `
            -PartitionKey $partitionKey `
            -Type SpCall `
            -MaxItems $MaxItems `
            -Context $Context `
            -Collection $Collection
        
        $rq.Method = [System.Net.Http.HttpMethod]::Post
        $rq.Uri = new-object System.Uri("$url/$Name")
        $rq.Payload = $Parameters
        $rq.ContentType = 'application/json'

        $outstandingRequests+=SendRequestInternal -rq $rq -Context $Context
        if($outstandingRequests.Count -ge $batchSize)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
            $outstandingRequests=@()
        }
    }
    end
    {
        if($outstandingRequests.Count -gt 0)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
        }
    }
}