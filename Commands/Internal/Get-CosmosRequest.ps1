function Get-CosmosRequest
{
    param(
        [Switch]$Upsert,
        [NUllable[UInt32]]$MaxItems,
        [string]$Continuation,
        [string]$PartitionKey,
        [string]$Collection,
        [Parameter()]
        [ValidateSet('Query','SpCall','Document','Other')]
        [string]$Type = 'Other',
        [PSCustomObject]$Context = $script:Configuration
    )

    process
    {
        $token = Get-CosmosAccessToken -Context $context
        
        [PSCustomObject]@{
            AccessToken = $token.AccessToken
            Type = $Type
            MaxItems = $MaxItems
            Continuation = $Continuation
            Session = $Context.Session[$Collection]
            Upsert = $Upsert
            PartitionKey = $PartitionKey
            Method = $null
            Uri = $null
            Payload = $null
            ContentType = $null
            MaxRetries = $Context.RetryCount
            Collection=$Collection
        }
    }
}