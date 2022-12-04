function SendRequestInternal
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
        $httpRequest = GetCosmosRequestInternal -rq $rq
        #pair our request to task for possible retry and batch executing tasks
        [PSCustomObject]@{
            CosmosLiteRequest = $rq
            HttpRequest = $httpRequest
            HttpTask = $script:httpClient.SendAsync($httpRequest)
        }
    }
}