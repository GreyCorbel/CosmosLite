# Atomic unit: wait for exactly ONE in-flight HTTP task to complete and handle its result.
# Shared by SubmitCosmosRequestInternal (process blocks) and DrainCosmosRequestsInternal (end blocks).
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
    }
}

# Start one HTTP request and maintain a sliding concurrency window of at most BatchSize requests.
# Blocks until a slot is available, then returns so the caller can send the next pipeline item.
# Used in process blocks.
function SubmitCosmosRequestInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$rq,
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$InFlight,
        [Parameter(Mandatory)]
        [int]$BatchSize,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context
    )

    process
    {
        [void]$InFlight.Add((SendRequestInternal -rq $rq -Context $Context))
        while ($InFlight.Count -ge $BatchSize)
        {
            WaitAndProcessOneInternal -InFlight $InFlight -Context $Context
        }
    }
}

# Flush all remaining in-flight requests to completion.
# Used in end blocks.
function DrainCosmosRequestsInternal
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
        while ($InFlight.Count -gt 0)
        {
            WaitAndProcessOneInternal -InFlight $InFlight -Context $Context
        }
    }
}
