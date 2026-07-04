function ProcessRequestBatchInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]
            #Mutable list of in-flight request contexts. Completed entries are removed in-place;
            #retried entries are re-added. The caller sees the updated list after each call.
        $InFlight,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context,
        [switch]
            #When set, wait for exactly ONE request to complete and return.
            #Intended for use in process blocks to maintain a sliding concurrency window.
            #When not set (default), drain all remaining requests (for end blocks).
        $DrainOne
    )

    process
    {
        if ($InFlight.Count -eq 0) { return }

        do
        {
            # Build Task[] from current in-flight list and wait for the first to complete.
            # Task.WaitAny returns the index of the completed task in the supplied array,
            # which corresponds directly to the same index in $InFlight.
            $tasks = [System.Threading.Tasks.Task[]]($InFlight | ForEach-Object { $_.HttpTask })
            $idx   = [System.Threading.Tasks.Task]::WaitAny($tasks)

            $completed = $InFlight[$idx]
            [void]$InFlight.RemoveAt($idx)

            $completed.HttpRequest.Dispose()
            $httpResponse = $completed.HttpTask.Result

            if ($httpResponse.IsSuccessStatusCode)
            {
                ProcessCosmosResponseInternal -ResponseContext $completed -Context $Context
                $httpResponse.Dispose()
            }
            elseif ($httpResponse.StatusCode -eq 429 -and $completed.RetriesRemaining -gt 0)
            {
                $val = $null
                if ($httpResponse.Headers.TryGetValues('x-ms-retry-after-ms', [ref]$val)) { $wait = [long]$val[0] } else { $wait = 1000 }
                $httpResponse.Dispose()
                $remaining = $completed.RetriesRemaining - 1
                Write-Verbose "Throttled`tWaitTime`t$wait`tRetriesRemaining`t$remaining"
                Start-Sleep -Milliseconds $wait
                [void]$InFlight.Add((SendRequestInternal -rq $completed.CosmosLiteRequest -Context $Context -RetriesRemaining $remaining))
            }
            else
            {
                # Failed response or retries exhausted — surface as error via ProcessCosmosResponseInternal
                ProcessCosmosResponseInternal -ResponseContext $completed -Context $Context
                $httpResponse.Dispose()
            }
        } while (-not $DrainOne -and $InFlight.Count -gt 0)
    }
}