function Update-CosmosDocument
{
<#
.SYNOPSIS
    Updates content of the document

.DESCRIPTION
    Updates document data according to update operations provided.
    This command uses Cosmos DB Partial document update API to perform changes on server side without the need to download the document to client, modify it on client and upload back to server

.OUTPUTS
    Response describing result of operation

.EXAMPLE
    $DocUpdate = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'test-docs'
    $DocUpdate.Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -value 'This is new data for propery content'
    Update-CosmosDocument -UpdateObject $DocUpdate -Collection 'docs'

Description
-----------
This command replaces field 'content' in root of the document with ID '123' and partition key 'test-docs' in collection 'docs' with new value
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]
            #Object representing document update specification produced by New-CosmosDocumentUpdate
            #and containing collection od up to 10 updates produced by New-CosmosUpdateOperation
        $UpdateObject,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection containing updated document
        $Collection,
        
        [Parameter()]
        [PSCustomObject]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration,

        [Parameter()]
        [int]
            #Degree of paralelism
        $BatchSize = 1
    )

    begin
    {
        $url = "$($Context.Endpoint)/colls/$collection/docs"
    }

    process
    {
        $rq = Get-CosmosRequest -PartitionKey $UpdateObject.PartitionKey -Type Document -Context $Context -Collection $Collection
        $rq.Method = [System.Net.Http.HttpMethod]::Patch
        $rq.Uri = new-object System.Uri("$url/$($UpdateObject.Id)")
        $patches = @{
            operations = $UpdateObject.Updates
        }
        if(-not [string]::IsNullOrWhiteSpace($UpdateObject.Condition))
        {
            $patches['condition'] = $UpdateObject.Condition
        }
        $rq.Payload =  $patches | ConvertTo-Json -Depth 99
        $rq.ContentType = 'application/json_patch+json'
        ProcessRequestBatchedWithRetryInternal -rq $rq -Context $Context -BatchSize $BatchSize
    }
}