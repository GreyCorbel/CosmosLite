function Invoke-CosmosQuery
{
<#
.SYNOPSIS
    Queries collection for documents

.DESCRIPTION
    Queries the collection and returns documents that fulfill query conditions.
    Data returned may not be complete; in such case, returned object contains continuation token in 'Continuation' property. To receive more data, execute command again with parameter ContinuationToken set to value returned in Continuation field by previous command call.
    
.OUTPUTS
    Response describing result of operation

.EXAMPLE
    $query = "select * from c where c.itemType = @itemType"
    $queryParams = @{
        '@itemType' = 'person'
    }
    $totalRuConsumption = 0
    $data = @()
    do
    {
        $rsp = Invoke-CosmosQuery -Query $query -QueryParameters $queryParams -Collection 'docs' -ContinuationToken $rsp.Continuation
        if($rsp.IsSuccess)
        {
            $data += $rsp.data.Documents
        }
        $totalRuConsumption+=$rsp.Charge
    }while($null -ne $rsp.Continuation)
    "Total RU consumption: $totalRuConsumption"

    Description
    -----------
    This command performs cross partition parametrized query and iteratively fetches all matching documents. Command also measures total RU consumption of the query
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
            #Query string
        $Query,

        [Parameter()]
        [System.Collections.Hashtable]
            #Query parameters if the query string contains parameter placeholders
            #Parameter names must start with '@' char
        $QueryParameters,

        [Parameter()]
        [string[]]
            #Partition key for partition where query operates. If not specified, query queries all partitions - it's cross-partition query (expensive)
        $PartitionKey,

        [Parameter()]
        [string[]]
            #Partition key range id retrieved from Get-CosmosCollectionPartitionKeyRanges command
            #Helps execution cross-partition queries
        $PartitionKeyRangeId,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection
        $Collection,

        [Parameter()]
        [NUllable[UInt32]]
            #Maximum number of documents to be returned by query
            #When not specified, all matching documents are returned
        $MaxItems,

        [Parameter()]
        [string]
            #Continuation token. Used to ask for next page of results
        $ContinuationToken,

        [switch]
            #when response contains continuation token, returns the reesponse and automatically sends new request with continuation token
            #this simnlifies getting all data from query for large datasets
        $AutoContinue,

        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($context.Endpoint)/colls/$collection/docs"
    }

    process
    {
        do
        {
            $rq = Get-CosmosRequest `
                -PartitionKey $partitionKey `
                -PartitionKeyRangeId $PartitionKeyRangeId `
                -Type Query `
                -MaxItems $MaxItems `
                -Continuation $ContinuationToken `
                -Context $Context `
                -Collection $Collection

            $QueryDefinition = @{
                query = $Query
            }
            if($null -ne $QueryParameters)
            {
                $QueryDefinition['parameters']=@()
                foreach($key in $QueryParameters.Keys)
                {
                    $QueryDefinition['parameters']+=@{
                        name=$key
                        value=$QueryParameters[$key]
                    }
                }
            }
            $rq.Method = [System.Net.Http.HttpMethod]::Post
            $uri = "$url"
            $rq.Uri = New-Object System.Uri($uri)
            $rq.Payload = ($QueryDefinition | ConvertTo-Json -Depth 99 -Compress)
            $rq.ContentType = 'application/query+json'

            $response = ProcessRequestBatchInternal -Batch (SendRequestInternal -rq $rq -Context $Context) -Context $Context
            $response
            #auto-continue if requested
            if(-not $AutoContinue) {break;}
            if([string]::IsNullOrEmpty($response.Continuation)) {break;}
            $ContinuationToken = $response.Continuation
        }while($true)
    }
}