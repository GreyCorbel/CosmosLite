# Maintains a sliding concurrency window for in-flight Cosmos DB HTTP requests.
#
# Submit mode  ($rq provided): starts one HTTP request and blocks until a slot is free
#   (Count < BatchSize), then returns so the caller can process the next pipeline item.
#   Used in process blocks.
#
# Drain mode ($rq omitted): flushes all remaining in-flight requests to completion.
#   Used in end blocks.
function InvokeCosmosWindowInternal
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [PSCustomObject]
            #CosmosLiteRequest to start. Omit (or pass $null) to switch to drain mode.
        $rq = $null,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$InFlight,
        [Parameter()]
        [int]
            #Maximum number of concurrent requests. Only used in submit mode.
        $BatchSize = 1,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context
    )

    process
    {
        $limit = 1
        if ($null -ne $rq)
        {
            [void]$InFlight.Add((SendRequestInternal -rq $rq -Context $Context))
            $limit = $BatchSize
        }
        # Submit mode: loop while window is at capacity  (Count >= BatchSize)
        # Drain  mode: loop while anything remains       (limit = 1  →  Count >= 1)
        while ($InFlight.Count -ge $limit)
        {
            WaitAndProcessOneInternal -InFlight $InFlight -Context $Context
        }
    }
}
