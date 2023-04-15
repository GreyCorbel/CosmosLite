function ProcessRequestBatchInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Batch,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context
    )

    begin
    {
        $outstandingRequests=@()
        $batch | ForEach-Object{$outstandingRequests+=$_}
        $maxRetries = $Context.RetryCount
    }
    process
    {
        do
        {
            #we have enough HttpRequests sent - wait for completion
            [System.Threading.Tasks.Task]::WaitAll($outstandingRequests.HttpTask)
            
            #process reponses
            #bag for requests to retry
            $requestsToRetry=@()
            #total time to wait in case of throttled
            $waitTime=0
            foreach($request in $outstandingRequests)
            {
                #dispose related httpRequestMessage
                $request.HttpRequest.Dispose()

                #get httpResponseMessage
                $httpResponse = $request.HttpTask.Result
                #and associated CosmosLiteRequest
                $cosmosRequest = $request.CosmosLiteRequest
                if($httpResponse.IsSuccessStatusCode) {
                    #successful - process response
                    ProcessCosmosResponseInternal -rsp $httpResponse -Context $Context -Collection $cosmosRequest.Collection
                }
                else
                {
                    if($httpResponse.StatusCode -eq 429 -and $maxRetries -gt 0)
                    {
                        #get waitTime
                        $val = $null
                        if($httpResponse.Headers.TryGetValues('x-ms-retry-after-ms', [ref]$val)) {$wait = [long]$val[0]} else {$wait=1000}
                        #we wait for longest time returned by all 429 responses
                        if($waitTime -lt $wait) {$waitTime = $wait}
                        $requestsToRetry+=$cosmosRequest
                    }
                    else {
                        #failed or maxRetries exhausted
                        ProcessCosmosResponseInternal -rsp $httpResponse -Context $Context -Collection $cosmosRequest.Collection
                    }
                }
                #dispose httpResponseMessage
                $httpResponse.Dispose()
            }

            #retry throttled requests
            if($requestsToRetry.Count -gt 0)
            {
                $outstandingRequests=@()
                $maxRetries--
                Write-Verbose "Throttled`tRequestsToRetry`t$($requestsToRetry.Count)`tWaitTime`t$waitTime`tRetriesRemaining`t$maxRetries"
                Start-Sleep -Milliseconds $waitTime
                foreach($cosmosRequest in $requestsToRetry)
                {
                    $outstandingRequests+=SendRequestInternal -rq $cosmosRequest -Context $Context
                }
            }
            else {
                #no requests to retry
                break
            }
        }while($true)
    }
}