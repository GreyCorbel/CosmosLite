function Update-CosmosDocument
{
<#
.SYNOPSIS
    Applies partial updates to a document.

.DESCRIPTION
    Applies patch operations to documents by using the Cosmos DB partial document update API.
    This avoids downloading the full document, editing client-side, and replacing the complete payload.
    Supports pipeline input, batched parallel processing, and ShouldProcess (-WhatIf and -Confirm).

.OUTPUTS
    CosmosLite response object.

.EXAMPLE
    $DocUpdate = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'test-docs'
    $DocUpdate.Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -value 'This is new data for property content'
    Update-CosmosDocument -UpdateObject $DocUpdate -Collection 'docs'

    Description
    -----------
    Applies a single patch operation to update the content property of a document.
#>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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

        [switch]
            #asks server not to include updated document in response data
        $NoContentOnResponse,

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
        if($PSCmdlet.ShouldProcess("$Collection/$($UpdateObject.Id)", 'Update Cosmos document'))
        {
            $rq = Get-CosmosRequest -PartitionKey $UpdateObject.PartitionKey -Type Document -Context $Context -Collection $Collection
            #PS5.1 does not suppoort Patch method
            $rq.Method = [System.Net.Http.HttpMethod]::new('PATCH')
            $rq.Uri = new-object System.Uri("$url/$($UpdateObject.Id)")
            $rq.NoContentOnResponse = $NoContentOnResponse.IsPresent
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
    }
    end
    {
        if($outstandingRequests.Count -gt 0)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
        }
    }
}