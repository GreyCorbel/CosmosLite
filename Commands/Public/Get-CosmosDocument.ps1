function Get-CosmosDocument
{
<#
.SYNOPSIS
    Retrieves document from the collection

.DESCRIPTION
    Retrieves document from the collection by id and partition key

.OUTPUTS
    Response containing retrieved document parsed from JSON format.

.EXAMPLE
$rsp = Get-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs'
$rsp.data

Description
-----------
This command retrieves document with id = '123' and partition key 'test-docs' from collection 'docs'
#>
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
            #Id of the document
        $Id,

        [Parameter(Mandatory)]
        [string]
            #value of partition key for the document
        $PartitionKey,

        [Parameter(Mandatory)]
        [string]
            #Name of collection conaining the document
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
        $rq.Method = [System.Net.Http.HttpMethod]::Get
        $rq.Uri = new-object System.Uri("$url/$id")
        ProcessRequestBatchInternal -Batch (SendRequestInternal -rq $rq -Context $Context) -Context $Context
    }
}