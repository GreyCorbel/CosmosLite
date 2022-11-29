function Remove-CosmosDocument
{
<#
.SYNOPSIS
    Removes document from collection

.DESCRIPTION
    Removes document from collection

.OUTPUTS
    Response describing result of operation

.EXAMPLE
    Remove-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs' -IsUpsert

Description
-----------
This command creates new document with id = '123' and partition key 'test-docs' collection 'docs', replacing potentially existing document with same id and partition key
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
            #Id of the document
        $Id,

        [Parameter(Mandatory)]
        [string]
            #Partition key value of the document
        $PartitionKey,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection that contains the document to be removed
        $Collection,

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
        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Context $Context -Collection $Collection
        $rq.Method = [System.Net.Http.HttpMethod]::Delete
        $uri = "$url/$id"
        $rq.Uri = new-object System.Uri($uri)
        ProcessRequestWithRetryInternal -rq $rq -Context $Context
    }
}