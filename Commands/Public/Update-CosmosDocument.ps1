function Update-CosmosDocument
{
<#
.SYNOPSIS
    Updates content of the document

.DESCRIPTION
    Updates document data according to update operations provided.
    This command uses Cosmos DB Partial document update API to perform changes on server side without the need to download the document to client, modify it on client side and upload back to server
    Command supports parallel processing.

.OUTPUTS
    Response describing result of operation

.EXAMPLE
    $DocUpdate = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'test-docs'
    $DocUpdate.Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -value 'This is new data for property content'
    Update-CosmosDocument -UpdateObject $DocUpdate -Collection 'docs'

    Description
    -----------
    This command replaces field 'content' in root of the document with ID '123' and partition key 'test-docs' in collection 'docs' with new value
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('CosmosLite.Update')]
            #Object representing document update specification produced by New-CosmosDocumentUpdate
            #and containing collection od up to 10 updates produced by New-CosmosUpdateOperation
        $UpdateObject,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection containing updated document
        $Collection,

        [Parameter()]
        [int]
            #Degree of paralelism for pipeline processing
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
        $rq.Payload =  $patches | ConvertTo-Json -Depth 99 -Compress
        $rq.ContentType = 'application/json_patch+json'

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