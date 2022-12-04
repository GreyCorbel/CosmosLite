function Set-CosmosDocument
{
<#
.SYNOPSIS
    Replaces document with new document

.DESCRIPTION
    replaces document data completely with new data. Document must exist for oepration to succeed.
    
.OUTPUTS
    Response describing result of operation

.EXAMPLE
    $doc = [Ordered]@{
        id = '123'
        pk = 'test-docs'
        content = 'this is content data'
    }
    Set-CosmosDocument -Id '123' Document ($doc | ConvertTo-Json) -PartitionKey 'test-docs' -Collection 'docs'

Description
-----------
This command replaces entire document with ID '123' and partition key 'test-docs' in collection 'docs' with new content
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
        [string]
            #Partition key of document to be replaced
        $PartitionKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #Object representing document to create
            #Command performs JSON serialization via ConvertTo-Json -Depth 99
        $DocumentObject,

        [Parameter(Mandatory, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #attribute of DocumentObject used as partition key
        $PartitionKeyAttribute,
        
        [Parameter(Mandatory)]
        [string]
            #Name of collection containing the document
        $Collection,

        [Parameter()]
        [PSCustomObject]
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
            $PartitionKey = $DocumentObject."$PartitionKeyAttribute"
            $Document = $DocumentObject | ConvertTo-Json -Depth 99 -Compress
        }

        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Type Document -Context $Context -Collection $Collection
        $rq.Method = [System.Net.Http.HttpMethod]::Put
        $rq.Uri = new-object System.Uri("$url/$id")
        $rq.Payload = $Document
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