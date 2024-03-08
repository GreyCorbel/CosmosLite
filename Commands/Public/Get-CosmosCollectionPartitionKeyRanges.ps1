function Get-CosmosCollectionPartitionKeyRanges
{
<#
.SYNOPSIS
    Retrieves partition key ranges for the collection

.DESCRIPTION
    Retrieves partition key ranges for the collection  
    This helps with execution of cross partition queries

.OUTPUTS
    Response containing partition key ranges for collection.

.EXAMPLE
    $rsp = Get-CosmosCollectioPartitionKeyRanges -Collection 'docs'
    $rsp.data

    Description
    -----------
    This command retrieves partition key ranges for collection 'docs'
#>
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
            #Name of collection conaining the document
        $Collection,

        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($context.Endpoint)/colls/$collection/pkranges"
        $outstandingRequests=@()
    }

    process
    {
        $rq = Get-CosmosRequest -Context $Context -Collection $Collection
        $rq.Uri = new-object System.Uri("$url")

        $rq.Method = [System.Net.Http.HttpMethod]::Get

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