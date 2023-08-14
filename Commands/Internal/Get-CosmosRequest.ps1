function Get-CosmosRequest
{
    param(
        [Switch]$Upsert,
        [Parameter()]
        [NUllable[UInt32]]$MaxItems,
        [Parameter()]
        [string]$Continuation,
        [Parameter()]
        [string[]]$PartitionKey,
        [Parameter(Mandatory)]
        [string]$Collection,
        [Parameter()]
        [ValidateSet('Query','SpCall','Document','Other')]
        [string]$Type = 'Other',
        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]$Context = $script:Configuration
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
            ETag = $null
            PriorityLevel = $null
            NoContentOfResponse = $false
        }
    }
}