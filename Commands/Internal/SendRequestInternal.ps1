function SendRequestInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$rq,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context,
        [Parameter()]
        [int]
            #Remaining retry attempts for this request. Defaults to Context.RetryCount on first send.
        $RetriesRemaining = -1
    )

    process
    {
        $httpRequest = GetCosmosRequestInternal -rq $rq
        [PSCustomObject]@{
            CosmosLiteRequest  = $rq
            HttpRequest        = $httpRequest
            HttpTask           = $Context.HttpClient.SendAsync($httpRequest)
            RetriesRemaining   = if ($RetriesRemaining -lt 0) { $Context.RetryCount } else { $RetriesRemaining }
        }
    }
}