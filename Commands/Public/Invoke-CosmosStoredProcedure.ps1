function Invoke-CosmosStoredProcedure
{
<#
.SYNOPSIS
    Executes a stored procedure.

.DESCRIPTION
    Calls a stored procedure in the specified collection and partition.
    Supports pipeline input and batched parallel request processing.
    Paging behavior for stored procedures is implemented by the stored procedure itself. If paging is needed,
    the procedure must accept, propagate, and return continuation state explicitly.
    
.OUTPUTS
    CosmosLite response object containing stored procedure output.

.EXAMPLE
    $params = @('123', 'test')
    $rsp = Invoke-CosmosStoredProcedure -Name testSP -Parameters ($params | ConvertTo-Json) -Collection 'docs' -PartitionKey 'test-docs'
    $rsp

    Description
    -----------
    Executes a stored procedure with two input parameters and returns its response.
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
        $outstandingRequests = [System.Collections.Generic.List[object]]::new()
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

        InvokeCosmosWindowInternal -rq $rq -InFlight $outstandingRequests -BatchSize $batchSize -Context $Context
    }
    end
    {
        InvokeCosmosWindowInternal -InFlight $outstandingRequests -Context $Context
    }
}