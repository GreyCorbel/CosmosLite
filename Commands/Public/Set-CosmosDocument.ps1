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
        [Parameter(Mandatory)]
        [string]
            #Id of the document to be replaced
        $Id,

        [Parameter(Mandatory)]
        [string]
            #new document data
        $Document,

        [Parameter(Mandatory)]
        [string]
            #Partition key of document to be replaced
        $PartitionKey,

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
    }

    process
    {
        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Type Document -Context $Context -Collection $Collection
        $rq.Method = [System.Net.Http.HttpMethod]::Put
        $uri = "$url/$id"
        $rq.Uri = new-object System.Uri($uri)
        $rq.Payload = $Document
        $rq.ContentType = 'application/json'
        ProcessRequestWithRetryInternal -rq $rq -Context $Context
    }
}