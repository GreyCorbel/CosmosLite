function SendRequestInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$rq,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context
    )

    process
    {
        $httpRequest = GetCosmosRequestInternal -rq $rq
        #pair our request to task for possible retry and batch executing tasks
        [PSCustomObject]@{
            CosmosLiteRequest = $rq
            HttpRequest = $httpRequest
            HttpTask = $Context.HttpClient.SendAsync($httpRequest)
        }
    }
}