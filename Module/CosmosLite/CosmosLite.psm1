function Connect-Cosmos
{
    param
    (
        [Parameter(Mandatory)]
        [string]$AccountName,
        [Parameter(Mandatory)]
        [string]$Database,
        [Parameter(Mandatory)]
        [string]$TenantId,
        [Parameter()]
        #well-know clientId for Azure PowerShell
        [string]$ClientId = '1950a258-227b-4e31-a9cf-717495945fc2',
        [Parameter()]
        [string]$LoginApi = 'https://login.microsoftonline.com',
        [Parameter()]
        [ValidateSet('Interactive', 'DeviceCode')]
        [string]$AuthMode = 'Interactive',
        [Parameter()]
        [string]$Proxy
    )

    process
    {
        $script:AuthMode = $AuthMode
        $script:AuthFactories = @{}

        switch($PSEdition)
        {
            'Core'
            {
                Add-type -Path "$PSScriptRoot\Shared\netcoreapp2.1\Microsoft.Identity.Client.dll"
                break;
            }
            'Desktop'
            {
                Add-Type -Path "$PSScriptRoot\Shared\net461\Microsoft.Identity.Client.dll"
                break;
            }
        }
        Add-Type -Path "$PSScriptRoot\Shared\netstandard2.1\GreyCorbel.PublicClient.Authentication.dll"

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        if(-not [string]::IsNullOrWhitespace($proxy))
        {
            [system.net.webrequest]::defaultwebproxy = new-object system.net.webproxy($Proxy)
            [system.net.webrequest]::defaultwebproxy.credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
            [system.net.webrequest]::defaultwebproxy.BypassProxyOnLocal = $true
        }

        $script:httpClient = new-object System.Net.Http.HttpClient
        $script:Configuration = [PSCustomObject]@{
            Account = $AccountName
            Database = $Database
            Endpoint = "https://$accountName`.documents.azure.com/dbs/$Database"
            RequiredScopes = @("https://$accountName`.documents.azure.com/.default")
            LoginApi = $LoginApi
            TenantId = $tenantId
            ClientId = $ClientId
            AuthMode = $AuthMode
        }
        $script:Configuration
    }
}

#region Authentication

function Get-Token
{
    param
    (
        [Parameter()]
        [PSCustomObject]$context = $script:Configuration,
        [Parameter()]
        [string]$userName = $null
    )

    process
    {
        if([string]::IsNullOrEmpty($context))
        {
            throw "Call Connect-Cosmos first"
        }

        if($null -eq $script:AuthFactories[$context.tenantId])
        {
            $script:AuthFactories[$context.tenantId] = new-object GreyCorbel.PublicClient.Authentication.AuthenticationFactory($context.tenantId, $context.ClientId, $context.RequiredScopes, $context.LoginApi)
        }

        $script:AuthFactories[$context.tenantId].AuthenticateAsync($userName, $context.AuthMode).GetAwaiter().GetResult()
    }
}

#region CosmosLiteInternals
function FormatCosmosResponseInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Net.Http.HttpResponseMessage]
        $rsp
    )

    begin
    {
        $retVal = [PSCustomObject]@{
            IsSuccess = $false
            HttpCode = 0
            Charge = -1
            Data = $null
            Continuation = $null
        }
        $provider =  [System.Globalization.CultureInfo]::CreateSpecificCulture("en-US")
    }
    process
    {
        $retVal.IsSuccess = $rsp.IsSuccessStatusCode
        $retVal.HttpCode = $rsp.StatusCode
        $val = $null
        if($rsp.Headers.TryGetValues('x-ms-request-charge', [ref]$val)) {
            $retVal.Charge = [double]::Parse($val[0],$provider)
        }
        if($rsp.Headers.TryGetValues('x-ms-continuation', [ref]$val)) {
            $retVal.Continuation = $val[0]
        }
        if($null -ne $rsp.Content)
        {
            $s = $rsp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $retVal.Data = ($s | ConvertFrom-Json)
        }
        $rsp.Dispose()
        return $retVal
    }
}
function ProcessRequestWithRetryInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$rq,
        [int]$maxRetries = 10
    )

    process
    {
        do {
            $request = GetCosmosRequestInternal -rq $rq
            $rsp = $script:httpClient.SendAsync($request).GetAwaiter().GetResult()
            $request.Dispose()
            if($rsp.IsSuccessStatusCode) {return (FormatCosmosResponseInternal -rsp $rsp)}
            if($rsp.StatusCode -eq 429 -and $maxRetries -gt 0)
            {
                $val = $null
                if($rsp.Headers.TryGetValues('x-ms-retry-after-ms', [ref]$val)) {$wait = [long]$val[0]} else {$wait=1000}
                Start-Sleep -Milliseconds $wait
                $maxRetries--
                $rsp.Dispose()
            }
            else {return (FormatCosmosResponseInternal -rsp $rsp)}
        } until ($false)
    }
}
function GetCosmosRequestInternal {
    param (
        [Parameter(Mandatory)]
        $rq
    )
    
    process
    {
        $retVal = New-Object System.Net.Http.HttpRequestMessage
        $retVal.Headers.TryAddWithoutValidation('Authorization', [System.Web.HttpUtility]::UrlEncode("type=aad`&ver=1.0`&sig=$($rq.AccessToken)")) | out-null
        $retVal.Headers.Add('x-ms-date', [DateTime]::UtcNow.ToString('r',[System.Globalization.CultureInfo]::GetCultureInfo('en-US')))
        $retVal.Headers.Add('x-ms-version', '2018-12-31')
        $retVal.RequestUri = $rq.Uri
        $retVal.Method = $rq.Method

        switch($rq.Type)
        {
            'Query' {
                $retVal.Content = new-object System.Net.Http.StringContent($rq.payload,$null ,$rq.ContentType)
                $retVal.Content.Headers.ContentType.CharSet=[string]::Empty
                $retVal.Headers.Add('x-ms-documentdb-isquery', 'True')

                if($rq.MaxItems.HasValue)
                {
                    $retVal.Headers.Add('x-ms-max-item-count', $rq.MaxItems.Value)
                }
                if($rq.CrossPartition)
                {
                    $retVal.Headers.Add('x-ms-documentdb-query-enablecrosspartition', 'True')
                }
                if(-not [string]::IsNullOrEmpty($rq.Continuation))
                {
                    $retVal.Headers.Add('x-ms-continuation', $rq.Continuation)
                }
                break;
            }
            {$_ -in 'SpCall','Document'} {
                $retVal.Content = new-object System.Net.Http.StringContent($rq.payload,$null ,$rq.ContentType)
                $retVal.Content.Headers.ContentType.CharSet=[string]::Empty
                break
            }
            default {}
        }
        if($rq.Upsert)
        {
            $retVal.Headers.Add('x-ms-documentdb-is-upsert', 'True');
        }
        if(-not [string]::IsNullOrEmpty($rq.PartitionKey))
        {
            $retVal.Headers.Add('x-ms-documentdb-partitionkey', "[`"$($rq.PartitionKey)`"]")
        }

        $retVal
    }
}

function Get-CosmosRequest
{
    param(
        [Switch]$Upsert,
        [Switch]$CrossPartition,
        [NUllable[UInt32]]$MaxItems,
        [string]$Continuation,
        [string]$PartitionKey,
        [Parameter()]
        [ValidateSet('Query','SpCall','Document','Other')]
        [string]$Type = 'Other',
        [switch]$Patch,
        [PSCustomObject]$Context = $script:Configuration
    )

    process
    {

        $token = Get-Token -Context $context
        
        [PSCustomObject]@{
            AccessToken = $token.AccessToken
            Type = $Type
            MaxItems = $MaxItems
            CrossPartition = $CrossPartition
            Continuation = $Continuation
            Upsert = $Upsert
            PartitionKey = $PartitionKey
            Method = $null
            Uri = $null
            Payload = $null
            ContentType = $null
        }
    }
}

#endregion


#region CosmosLiteDocs
function Get-CosmosDocument
{
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Id,
        [Parameter(Mandatory)]
        [string]$partitionKey,
        [Parameter(Mandatory)]
        [string]$collection,
        [Parameter()]
        [PSCustomObject]$Context = $script:Configuration
    )

    begin
    {
        $url = "$($context.Endpoint)/colls/$collection/docs"
    }

    process
    {
        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Context $Context
        $rq.Method = [System.Net.Http.HttpMethod]::Get
        $uri = "$url/$id"
        $rq.Uri = new-object System.Uri($uri)
        ProcessRequestWithRetryInternal -rq $rq
    }
}

function New-CosmosDocument
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
        $Document,
        [Parameter()]
        [string]$partitionKey,
        [Parameter(Mandatory)]
        [string]$collection,
        [switch]$IsUpsert,
        [Parameter()]
        [PSCustomObject]$Context = $script:Configuration
    )

    begin
    {
        $url = "$($context.Endpoint)/colls/$collection/docs"
    }

    process
    {
        $rq = Get-CosmosRequest -PartitionKey $partitionKey  -Type Document -Upsert:$IsUpsert
        $rq.Method = [System.Net.Http.HttpMethod]::Post
        $uri = "$url"
        $rq.Uri = new-object System.Uri($uri)
        $rq.Payload = $Document
        $rq.ContentType = 'application/json'
        ProcessRequestWithRetryInternal -rq $rq
    }
}

function Remove-CosmosDocument
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
        $Id,
        [Parameter(Mandatory)]
        [string]$partitionKey,
        [Parameter(Mandatory)]
        [string]$collection,
        [Parameter()]
        [PSCustomObject]$Context = $script:Configuration
    )

    begin
    {
        $url = "$($context.Endpoint)/colls/$collection/docs"
    }

    process
    {
        $rq = Get-CosmosRequest -PartitionKey $partitionKey
        $rq.Method = [System.Net.Http.HttpMethod]::Delete
        $uri = "$url/$id"
        $rq.Uri = new-object System.Uri($uri)
        ProcessRequestWithRetryInternal -rq $rq
    }
}

function Update-CosmosDocument
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $id,
        [Parameter(Mandatory)]
        [string]
        $Document,
        [Parameter(Mandatory)]
        [string]$partitionKey,
        [Parameter(Mandatory)]
        [string]$collection,
        [Parameter()]
        [PSCustomObject]$Context = $script:Configuration
    )

    begin
    {
        $url = "$($Context.Endpoint)/colls/$collection/docs"
    }

    process
    {
        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Type Document
        $rq.Method = [System.Net.Http.HttpMethod]::Put
        $uri = "$url/$id"
        $rq.Uri = new-object System.Uri($uri)
        $rq.Payload = $Document
        $rq.ContentType = 'application/json'
        ProcessRequestWithRetryInternal -rq $rq
    }
}
#endregion

#region CosmosLiteQuery
function Invoke-CosmosQuery
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Query,
        [Parameter(Mandatory)]
        [string]$collection,
        [Parameter()]
        [string]$partitionKey,
        [Parameter()]
        [NUllable[UInt32]]$MaxItems,
        [Parameter()]
        [string]$ContinuationToken,
        [switch]$CrossPartition,
        [Parameter()]
        [PSCustomObject]$Context = $script:Configuration
    )

    begin
    {
        $url = "$($context.Endpoint)/colls/$collection/docs"
    }

    process
    {

        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Type Query -CrossPartition:$CrossPartition -MaxItems $MaxItems
        $data = @{
            query = $Query
        }
        $rq.Method = [System.Net.Http.HttpMethod]::Post
        $uri = "$url"
        $rq.Uri = new-object System.Uri($uri)
        $rq.Payload = ($data | Convertto-json)
        $rq.ContentType = 'application/query+json'
        $rq.Continuation = $ContinuationToken
        ProcessRequestWithRetryInternal -rq $rq

    }
}

#endregion

#region CosmosLiteStoredProcedure
function Invoke-CosmosStoredProcedure
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Name,
        [Parameter()]
        [string]$Parameters,
        [Parameter(Mandatory)]
        [string]$collection,
        [Parameter()]
        [string]$partitionKey,
        [Parameter()]
        [NUllable[UInt32]]$MaxItems,
        [Parameter()]
        [string]$ContinuationToken,
        [Parameter()]
        [PSCustomObject]$Context = $script:Configuration
    )

    begin
    {
        $url = "$($Context.Endpoint)/colls/$collection/sprocs"
    }

    process
    {

        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Type SpCall -MaxItems $MaxItems
        $rq.Method = [System.Net.Http.HttpMethod]::Post
        $uri = "$url/$Name"
        $rq.Uri = new-object System.Uri($uri)
        $rq.Payload = $Parameters
        $rq.ContentType = 'application/json'
        $rq.Continuation = $ContinuationToken
        ProcessRequestWithRetryInternal -rq $rq
    }
}
#endregion
