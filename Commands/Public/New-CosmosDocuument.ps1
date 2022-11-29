function New-CosmosDocument
{
<#
.SYNOPSIS
    Inserts new document into collection

.DESCRIPTION
    Inserts new document into collection, or replaces existing when asked to perform upsert.

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
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
            #JSON string representing the document data
        $Document,

        [Parameter(Mandatory)]
        [string]
            #Partition key of new document
        $PartitionKey,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection where to store document in
        $Collection,

        [switch]
            #Whether to replace existing document with same Id and Partition key
        $IsUpsert,
        [Parameter()]
        [PSCustomObject]
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
        $rq = Get-CosmosRequest `
            -PartitionKey $partitionKey `
            -Type Document `
            -Context $Context `
            -Collection $Collection `
            -Upsert:$IsUpsert
        
        $rq.Method = [System.Net.Http.HttpMethod]::Post
        $uri = "$url"
        $rq.Uri = new-object System.Uri($uri)
        $rq.Payload = $Document
        $rq.ContentType = 'application/json'
        ProcessRequestWithRetryInternal -rq $rq -Context $Context
    }
}
