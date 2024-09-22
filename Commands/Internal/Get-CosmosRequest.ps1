function Get-CosmosRequest
{
    param(
        [Switch]$Upsert,
        [Parameter()]
        [NUllable[UInt32]]$MaxItems,
        [Parameter()]
        [Type]$TargetType,
        [Parameter()]
        [string]$Continuation,
        [Parameter()]
        [int]$MaxContinuationTokenSizeInKb = 6,
        [Parameter()]
        [string[]]$PartitionKey,
        [Parameter()]
        [string[]]$PartitionKeyRangeId,
        [Parameter(Mandatory)]
        [string]$Collection,
        [Parameter()]
        [ValidateSet('Query','SpCall','Document','Other')]
        [string]$Type = 'Other',
        [switch]$PopulateMetrics,
        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]$Context = $script:Configuration
    )

    process
    {
        $token = Get-CosmosAccessToken -Context $context
 
        [PSCustomObject]@{
            AccessToken = $token.AccessToken
            Type = $Type
            TargetType = $TargetType
            MaxItems = $MaxItems
            Continuation = $Continuation
            MaxContinuationTokenSizeInKb = $Context.MaxContinuationTokenSizeInKb
            Session = $Context.Session[$Collection]
            Upsert = $Upsert
            PartitionKey = $PartitionKey
            PartitionKeyRangeId = $PartitionKeyRangeId
            Method = $null
            Uri = $null
            Payload = $null
            ContentType = $null
            MaxRetries = $Context.RetryCount
            Collection=$Collection
            ETag = $null
            PriorityLevel = $null
            PopulateMetrics = $PopulateMetrics
            NoContentOnResponse = $false
            Version = $Context.ApiVersion
        }
    }
}