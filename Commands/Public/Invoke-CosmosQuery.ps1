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

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myCosmosDb -UseManagedIdentity -CollectResponseHeaders
    $query = "select * from c where c.itemType = @itemType"
    $queryParams = @{
        '@itemType' = 'person'
    }
    $rsp = Invoke-CosmosQuery -Query $query -QueryParameters $queryParams -Collection 'docs' -MaxItems 10 -AutoContinue -PopulateMetrics
    if($rsp.IsSuccess)
    {
        $rsp.data.Documents
        "Total RU consumption: $($rsp | Measure-Object -Property Charge -Sum | select -ExpandProperty Sum)"
    }

    Description
    -----------
    This command performs cross partition parametrized query, potentially iterating over all partition key ranges, and fetches all matching documents, automatically paginating over all pages.  
    Command also measures total RU consumption and populates 'x-ms-documentdb-query-metrics' header in the response across all subqueries
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
            #Custom type to serialize documents returned by query to
            #When specified, custom serializer is used and returns objects of specified type
            #When not specified, ConvertFrom-Json command is used that returns documents as PSCustomObject
        [Type]$TargetType,

        [Parameter()]
        [string]
            #Continuation token. Used to ask for next page of results
        $ContinuationToken,

        [switch]
            #Populates query metrics in response object
        $PopulateMetrics,

        [switch]
            #when response contains continuation token, returns the response and automatically sends new request with continuation token
            #on large collection with multiple partitions, it also iterates over all partition key ranges and queries them one by one
            #this simplifies getting all data from query for large datasets
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
        if($null -ne $TargetType)
        {
            #create custom type for response
            $expression = "class QueryResponse {
                [string]`$_rid
                [int]`$_count
                [System.Collections.Generic.List[$($targetType.Name)]]`$Documents
                }"
            Invoke-Expression $expression
            $Type = [QueryResponse]
        }
        else {$Type=$null}
        if($AutoContinue -and $null -eq $PartitionKeyRangeId)
        {
            Write-Verbose "AutoContinue specified but PartitionKeyRangeId not specified. Retrieving all partition key ranges for collection $Collection"
            #get all partition key ranges for the collection
            $rsp = Get-CosmosCollectionPartitionKeyRanges -Collection $Collection -Context $Context
            if(-not $rsp.IsSuccess)
            {
                Write-Warning "Failed to retrieve partition key ranges for collection $Collection. Error: $($rsp.Data)"
                return
            }
            $partitionKeyRangeIds = $rsp.data.PartitionKeyRanges.Id
        }
        else {
            $partitionKeyRangeIds = @($PartitionKeyRangeId)
        }
        foreach($id in $partitionKeyRangeIds)
        {
            if($null -ne $id) { Write-Verbose "Querying PartitionKeyRangeId $id" }
            do
            {
                $rq = Get-CosmosRequest `
                    -PartitionKey $partitionKey `
                    -PartitionKeyRangeId $id `
                    -Type Query `
                    -MaxItems $MaxItems `
                    -Continuation $ContinuationToken `
                    -PopulateMetrics:$PopulateMetrics `
                    -Context $Context `
                    -Collection $Collection `
                    -TargetType $Type

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
}