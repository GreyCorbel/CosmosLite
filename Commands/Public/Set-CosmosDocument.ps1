function Set-CosmosDocument
{
<#
.SYNOPSIS
    Replaces an existing document.

.DESCRIPTION
    Replaces document content with the supplied payload.
    The document must exist.
    When -Etag is supplied, replacement is conditional on the current server ETag.
    Supports pipeline input and batched parallel request processing.
    
.OUTPUTS
    CosmosLite response object.

.EXAMPLE
    $doc = [Ordered]@{
        id = '123'
        pk = 'test-docs'
        content = 'this is content data'
    }
    Set-CosmosDocument -Id '123' Document ($doc | ConvertTo-Json) -PartitionKey 'test-docs' -Collection 'docs'

    Description
    -----------
    Replaces the full document body for document 123 in collection docs.
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string]
            #Id of the document to be replaced
        $Id,

        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string]
            #new document data
        $Document,

        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string[]]
            #Partition key of document to be replaced
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
            #Name of collection containing the document
        $Collection,

        [switch]
            #asks server not to include replaced document in response data
        $NoContentOnResponse,
        
        [Parameter()]
        [string]
            #ETag to check. Document is updated only if server version of document has the same Etag
        $Etag,

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
        $url = "$($Context.Endpoint)/colls/$collection/docs"
        $outstandingRequests=@()
    }

    process
    {
        if($PSCmdlet.ParameterSetName -eq 'DocumentObject')
        {
            #to change document Id, you cannot use DocumentObject parameter set
            $Id = $DocumentObject.id
            #when in pipeline in PS5.1, parameter retains value across invocations
            $PartitionKey = @()

            foreach($attribute in $PartitionKeyAttribute)
            {
                $PartitionKey+=$DocumentObject."$attribute"
            }
            $Document = $DocumentObject | ConvertTo-Json -Depth 99 -Compress
        }

        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Type Document -Context $Context -Collection $Collection
        $rq.Method = [System.Net.Http.HttpMethod]::Put
        $rq.Uri = new-object System.Uri("$url/$id")
        $rq.Payload = $Document
        $rq.ETag = $ETag
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