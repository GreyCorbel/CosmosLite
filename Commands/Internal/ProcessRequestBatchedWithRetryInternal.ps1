function ProcessRequestBatchedWithRetryInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,ValueFromPipeline)]
        [PSCustomObject]$rq,
        [Parameter(Mandatory)]
        $Context,
        [Parameter()]
        [int]$BatchSize=1
    )

    begin
    {
        $outstandingRequests=@()
    }
    process
    {
        $httpRequest = GetCosmosRequestInternal -rq $rq
        #pair our request to task for possible retry and batch executing tasks
        $outstandingRequests+=[PSCustomObject]@{
            CosmosLiteRequest = $rq
            HttpRequest = $httpRequest
            HttpTask = $script:httpClient.SendAsync($httpRequest)
        }

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