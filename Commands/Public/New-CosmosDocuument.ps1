function New-CosmosDocument
{
<#
.SYNOPSIS
    Inserts new document into collection

.DESCRIPTION
    Inserts new document into collection, or replaces existing when asked to perform upsert.
    Command supports parallel processing.

.OUTPUTS
    Response describing result of operation

.EXAMPLE
    $doc = [Ordered]@{
        id = '123'
        pk = 'test-docs'
        content = 'this is content data'
    }
    New-CosmosDocument -Document ($doc | ConvertTo-Json) -PartitionKey 'test-docs' -Collection 'docs' -IsUpsert

    Description
    -----------
    This command creates new document with id = '123' and partition key 'test-docs' collection 'docs', replacing potentially existing document with same id and partition key
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'RawPayload')]
        [string]
            #JSON string representing the document data
        $Document,

        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string[]]
            #Partition key of new document
        $PartitionKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #Object representing document to create
            #Command performs JSON serialization via ConvertTo-Json -Depth 99
        $DocumentObject,

        [Parameter(Mandatory, ParameterSetName = 'DocumentObject')]
        [string[]]
            #attribute of DocumentObject used as partition key
        $PartitionKeyAttribute,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection where to store document in
        $Collection,

        [Parameter()]
        [string]
            #ETag to check. Document is upserted only if server version of document has the same Etag
        $Etag,

        [Parameter()]
        [ValidateSet('High','Low')]
        [string]
            #Priority assigned to request
            #High priority requests have less chance to get throttled than Low priority requests when throttlig occurs
        $Priority,

        [switch]
            #Whether to replace existing document with same Id and Partition key
        $IsUpsert,

        [switch]
            #asks server not to include created document in response data
        $NoContentOnResponse,

        [Parameter()]
        [int]
            #Degree of paralelism
        $BatchSize = 1,

        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($context.Endpoint)/colls/$collection/docs"
        $outstandingRequests=@()
    }

    process
    {
        if($PSCmdlet.ParameterSetName -eq 'DocumentObject')
        {
            $Document = $DocumentObject | ConvertTo-Json -Depth 99 -Compress
            #when in pipeline in PS5.1, parameter retains value across invocations
            $PartitionKey = @()
            foreach($attribute in $PartitionKeyAttribute)
            {
                $PartitionKey+=$DocumentObject."$attribute"
            }
        }

        $rq = Get-CosmosRequest `
            -PartitionKey $partitionKey `
            -Type Document `
            -Context $Context `
            -Collection $Collection `
            -Upsert:$IsUpsert
        
        $rq.Method = [System.Net.Http.HttpMethod]::Post
        $rq.Uri = new-object System.Uri($url)
        $rq.Payload = $Document
        $rq.ETag = $ETag
        $rq.PriorityLevel = $Priority
        $rq.NoContentOnResponse = $NoContentOnResponse.IsPresent
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
