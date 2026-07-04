# Atomic unit: wait for exactly ONE in-flight HTTP task to complete and handle its result.
# Called by InvokeCosmosWindowInternal in both submit and drain modes.
function WaitAndProcessOneInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$InFlight,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context
    )

    process
    {
        $tasks = [System.Threading.Tasks.Task[]]($InFlight | ForEach-Object { $_.HttpTask })
        $idx   = [System.Threading.Tasks.Task]::WaitAny($tasks)
        $completed = $InFlight[$idx]
        [void]$InFlight.RemoveAt($idx)

        $completed.HttpRequest.Dispose()
        $httpResponse = $completed.HttpTask.Result
        try
        {
            if ($httpResponse.IsSuccessStatusCode)
            {
                ProcessCosmosResponseInternal -ResponseContext $completed -Context $Context
            }
            elseif ($httpResponse.StatusCode -eq 429 -and $completed.RetriesRemaining -gt 0)
            {
                $val = $null
                if ($httpResponse.Headers.TryGetValues('x-ms-retry-after-ms', [ref]$val)) { $wait = [long]$val[0] } else { $wait = 1000 }
                $remaining = $completed.RetriesRemaining - 1
                Write-Verbose "Throttled`tWaitTime`t$wait`tRetriesRemaining`t$remaining"
                Start-Sleep -Milliseconds $wait
                [void]$InFlight.Add((SendRequestInternal -rq $completed.CosmosLiteRequest -Context $Context -RetriesRemaining $remaining))
            }
            else
            {
                # Failed response or retries exhausted — surface as error via ProcessCosmosResponseInternal
                ProcessCosmosResponseInternal -ResponseContext $completed -Context $Context
            }
        }
        finally
        {
            $httpResponse.Dispose()
        }
    }
}


