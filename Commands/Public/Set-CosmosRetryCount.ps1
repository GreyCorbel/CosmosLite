function Set-CosmosRetryCount
{
<#
.SYNOPSIS
    Sets up maximum number of retries when requests are throttled

.DESCRIPTION
    When requests are throttled (server return http 429 code), ruuntime retries the operation for # of times specified here. Default number of retries is 10.
    Waiting time between operations is specified by server together with http 429 response
    
.OUTPUTS
    No output

.EXAMPLE
    Set-CosmosRetryCount -RetryCount 20

    Description
    -----------
    This command sets maximus retries for throttled requests to 20
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