function ProcessRequestBatchedWithRetryInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,ValueFromPipeline)]
        [PSCustomObject]$rq,
        [Parameter(Mandatory)]
        $Context,
        [Parameter()]
        [int]$BatchSize=5
    )

    begin
    {
        $outstandingRequests=@()
        $maxRetries = $Context.RetryCount
    }
    process
    {
        $httpRequest = GetCosmosRequestInternal -rq $rq
        #pair our request to task for possible retry and batch executing tasks
        $outstandingRequests+=@{
            CosmosLiteRequest = $rq
            HttpRequest = $httpRequest
            HttpTask = $script:httpClient.SendAsync($httpRequest)
        }

        if($outstandingRequests.Count -ge $batchSize)
        {
            do
            {
                #we have enough HttpRequests sent - wait for completion
                [System.Threading.Tasks.Task]::WaitAll($outstandingRequests.HttpTask)
                
                #dispose request messages first and create empty for possible retries
                $outstandingRequests.HttpRequest.foreach($_.Dispose())
                #process reponses
                $results = @()
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
                        $results+= ProcessCosmosResponseInternal -rsp $httpResponse -Context $Context -Collection $cosmosRequest.Collection
                    }
                    if($httpResponse.StatusCode -eq 429 -and $maxRetries -gt 0)
                    {
                        #get waitTime
                        $val = $null
                        if($httpResponse.Headers.TryGetValues('x-ms-retry-after-ms', [ref]$val)) {$wait = [long]$val[0]} else {$wait=1000}
                        #we wait for total time returned by all 429 responses
                        $waitTime+= $wait
                        $requestsToRetry+=$cosmosRequest
                    }
                    else {
                        #failed or maxRetries exhausted
                        $results+= ProcessCosmosResponseInternal -rsp $httpResponse -Context $Context -Collection $cosmosRequest.Collection
                    }
                    #dispose httpResponseMessage
                    $httpResponse.Dispose()
                }
                #return complete results
                foreach($result in $results) {$result}

                #retry throttled requests
                if($requestsToRetry.Count -gt 0)
                {
                    $outstandingRequests=@()
                    $maxRetries--
                    Start-Sleep -Milliseconds $waitTime
                    foreach($cosmosRequest in $requestsToRetry)
                    {
                        $outstandingRequests+=@{
                            CosmosLiteRequest = $rq
                            HttpRequest = $httpRequest
                            HttpTask = $script:httpClient.SendAsync($httpRequest)
                        }
                    }
                }
                else {
                    #no requests to retry
                    break
                }
            }while($true)
            #reset rety counter
            $maxRetries=$context.RetryCount
        }
    }
}