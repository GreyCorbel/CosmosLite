function ProcessRequestWithRetryInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$rq,
        [Parameter(Mandatory)]
        $Context
    )

    
    process
    {
        do {

            try {
                $request = GetCosmosRequestInternal -rq $rq
                $rsp = $script:httpClient.SendAsync($request).GetAwaiter().GetResult()
                $request.Dispose()
                if($rsp.IsSuccessStatusCode) {
                    return (ProcessCosmosResponseInternal -rsp $rsp -Context $Context -Collection $rq.Collection)
                }
                if($rsp.StatusCode -eq 429 -and $rq.maxRetries -gt 0)
                {
                    $val = $null
                    if($rsp.Headers.TryGetValues('x-ms-retry-after-ms', [ref]$val)) {$wait = [long]$val[0]} else {$wait=1000}
                    Start-Sleep -Milliseconds $wait
                    $rq.maxRetries--
                }
                else {return (ProcessCosmosResponseInternal -rsp $rsp -Context $Context -Collection $rq.Collection)}
    
            }
            catch {
                throw $_.Exception
            }
            finally {
                if($null -ne $rsp) {$rsp.Dispose()}
            }
        } until ($false)
    }
}