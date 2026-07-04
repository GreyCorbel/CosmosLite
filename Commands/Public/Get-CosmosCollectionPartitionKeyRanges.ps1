function Get-CosmosCollectionPartitionKeyRanges
{
<#
.SYNOPSIS
    Returns partition key ranges for a collection.

.DESCRIPTION
    Retrieves partition key range metadata for the specified collection.
    This is useful for advanced query scenarios, such as manual fan-out across ranges.

.OUTPUTS
    CosmosLite response object containing partition key range metadata.

.EXAMPLE
    $rsp = Get-CosmosCollectionPartitionKeyRanges -Collection veryLargeCollection
    foreach($id in $rsp.data.PartitionKeyRanges.Id) {
        Invoke-CosmosQuery -Query 'select * from c' -collection veryLargeCollection -PartitionKeyRangeId $id -AutoContinue
    }

    Description
    -----------
    Demonstrates using explicit partition key ranges for large cross-partition query workloads.
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
