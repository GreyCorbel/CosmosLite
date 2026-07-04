function Set-CosmosRetryCount
{
<#
.SYNOPSIS
    Sets the retry count for throttled requests.

.DESCRIPTION
    Updates the maximum retry attempts used when Cosmos DB responds with HTTP 429 (Too Many Requests).
    Retry delay is taken from server-provided headers.
    
.OUTPUTS
    None.

.EXAMPLE
    Set-CosmosRetryCount -RetryCount 20

    Description
    -----------
    Sets the throttling retry limit to 20 for the active context.
#>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [int]
            #Number of retries
        $RetryCount,
        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    process
    {
        $Context.RetryCount = $RetryCount
    }
}