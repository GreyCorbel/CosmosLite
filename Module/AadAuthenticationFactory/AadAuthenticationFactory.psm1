function New-AadAuthenticationFactory
{
    <#
.SYNOPSIS
    Creates authentication factory with provided parameters for Public or Confidential client flows

.DESCRIPTION
    Creates authentication factory with provided parameters for Public or Confidential client flows
    Authentication uses by default well-know clientId of Azure Powershell, but can accept clientId of app registered in your own tenant.

.OUTPUTS
    AadAuthenticationFactory object

.EXAMPLE
New-AadAuthenticationFactory -TenantId mydomain.com -RequiredScopes @('https://my-db.documents.azure.com/.default') -AuthMode Interactive

Description
-----------
This command returns AAD authentication factory for Public client auth flow with well-known clientId for Azure PowerShell and interactive authentication for getting tokens for CosmosDB account

#>

    param
    (
        [Parameter(Mandatory,ParameterSetName = 'ConfidentialClientWithSecret')]
        [Parameter(Mandatory,ParameterSetName = 'ConfidentialClientWithCertificate')]
        [Parameter(Mandatory,ParameterSetName = 'PublicClient')]
        [Parameter(Mandatory,ParameterSetName = 'ResourceOwnerPasssword')]
        [string]
            #Id of tenant where to autenticate the user. Can be tenant id, or any registerd DNS domain
        $TenantId,

        [Parameter()]
        [string]
            #ClientId of application that gets token
            #Default: well-known clientId for Azure PowerShell
        $ClientId,

        [Parameter(Mandatory)]
        [string[]]
            #Scopes to ask token for
        $RequiredScopes,

        [Parameter(ParameterSetName = 'ConfidentialClientWithSecret')]
        [string]
            #Client secret for ClientID
            #Used to get access as application rather than as calling user
        $ClientSecret,

        [Parameter(ParameterSetName = 'ResourceOwnerPasssword')]
        [pscredential]
            #Resource Owner username and password
            #Used to get access as user
            #Note: Does not work for federated authentication
        $ResourceOwnerCredential,

        [Parameter(ParameterSetName = 'ConfidentialClientWithCertificate')]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
            #Authentication certificate for ClientID
            #Used to get access as application rather than as calling user
        $X509Certificate,

        [Parameter(ParameterSetName = 'ConfidentialClientWithSecret')]
        [Parameter(ParameterSetName = 'ConfidentialClientWithCertificate')]
        [Parameter(ParameterSetName = 'PublicClient')]
        [Parameter(ParameterSetName = 'ResourceOwnerPasssword')]
        [string]
            #AAD auth endpoint
            #Default: endpoint for public cloud
        $LoginApi = 'https://login.microsoftonline.com',
        
        [Parameter(Mandatory, ParameterSetName = 'PublicClient')]
        [ValidateSet('Interactive', 'DeviceCode', 'WIA')]
        [string]
            #How to authenticate client - via web view, via device code flow, or via Windows Integrated Auth
            #Used in public client flows
        $AuthMode,
        
        [Parameter(ParameterSetName = 'PublicClient')]
        [string]
            #Username hint for authentication UI
            #Optional
        $UserNameHint,

        [Parameter(ParameterSetName = 'ConfidentialClientWithSecret')]
        [Parameter(ParameterSetName = 'ConfidentialClientWithCertificate')]
        [Parameter(ParameterSetName = 'PublicClient')]
        [Parameter(ParameterSetName = 'ResourceOwnerPasssword')]
        [System.Net.WebProxy]
            #Web proxy configuration
            #Optional
        $proxy = $null,

        [Parameter(ParameterSetName = 'MSI')]
        [Switch]
            #tries to get parameters from environment and token from internal endpoint provided by Azure MSI support
        $UseManagedIdentity
    )

    process
    {
        switch($PSCmdlet.ParameterSetName)
        {
            'ConfidentialClientWithSecret' {
                $script:AadLastCreatedFactory = new-object GreyCorbel.Identity.Authentication.AadAuthenticationFactory($tenantId, $ClientId, $clientSecret, $RequiredScopes, $LoginApi,$proxy)
                break;
            }
            'ConfidentialClientWithCertificate' {
                $script:AadLastCreatedFactory = new-object GreyCorbel.Identity.Authentication.AadAuthenticationFactory($tenantId, $ClientId, $X509Certificate, $RequiredScopes, $LoginApi,$proxy)
                break;
            }
            'PublicClient' {
                $script:AadLastCreatedFactory = new-object GreyCorbel.Identity.Authentication.AadAuthenticationFactory($tenantId, $ClientId, $RequiredScopes, $LoginApi, $AuthMode, $UserNameHint,$proxy)
                break;
            }
            'MSI' {
                $script:AadLastCreatedFactory = new-object GreyCorbel.Identity.Authentication.AadAuthenticationFactory($ClientId, $RequiredScopes,$proxy)
                break;
            }
            'ResourceOwnerPasssword' {
                $script:AadLastCreatedFactory = new-object GreyCorbel.Identity.Authentication.AadAuthenticationFactory($tenantId, $ClientId, $RequiredScopes, $ResourceOwnerCredential.UserName, $ResourceOwnerCredential.Password, $LoginApi,$proxy)
                break;
            }
        }
        $script:AadLastCreatedFactory
    }
}

function Get-AadToken
{
    <#
.SYNOPSIS
    Retrieves AAD token according to configuration of authentication factory

.DESCRIPTION
    Retrieves AAD token according to configuration of authentication factory

.OUTPUTS
    Authentication result from AAD with tokens and other information

.EXAMPLE
$factory = New-AadAuthenticationFactory -TenantId mydomain.com  -RequiredScopes @('https://eventgrid.azure.net/.default') -AuthMode Interactive
$factory | Get-AadToken

Description
-----------
Command creates authentication factory and retrieves AAD token from it

#>

    param
    (
        [Parameter(ValueFromPipeline)]
        [GreyCorbel.Identity.Authentication.AadAuthenticationFactory]
            #AAD authentication factory created via New-AadAuthenticationFactory
        $Factory = $script:AadLastCreatedFactory,
        [Parameter()]
            #Scopes to be returned in the token.
            #If not specified, returns scopes provided when creating the factory
        [string[]]$Scopes = $null
    )

    process
    {
        try {
            #I don't know how to support Ctrl+Break
            $task = $factory.AuthenticateAsync($scopes)
            $task.GetAwaiter().GetResult()
        }
        catch [System.OperationCanceledException] {
            Write-Verbose "Authentication process has been cancelled"
        }
    }
}
function Test-AadToken
{
    <#
.SYNOPSIS
    Parses and validates AAD issues token

.DESCRIPTION
    Parses provided IdToken or AccessToken and checks for its validity.
    Note that some tokens may not be properly validated - this is in case then 'nonce' field present and set in the haeder. AAD issues such tokens for Graph API and nonce is taken into consideration when validating the token.
    See discussing at https://github.com/AzureAD/azure-activedirectory-identitymodel-extensions-for-dotnet/issues/609 for more details.

.OUTPUTS
    Parsed token and information about its validity

.EXAMPLE
$factory = New-AadAuthenticationFactory -TenantId mydomain.com  -RequiredScopes @('https://eventgrid.azure.net/.default') -AuthMode Interactive
$token = $factory | Get-AadToken
$token.idToken | Test-AadToken | fl

Description
-----------
Command creates authentication factory, asks it to issue token for EventGrid and parses IdToken and validates it

#>
[CmdletBinding()]
    param (
        [Parameter(Mandatory,ValueFromPipeline)]
        [string]
        #IdToken or AccessToken field from token returned by Get-AadToken
        $Token
    )

    process
    {
        $parts = $token.split('.')
        if($parts.Length -ne 3)
        {
            throw 'Invalid format of provided token'
        }
        
        $result = [PSCustomObject]@{
            Header = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((Base64UrlDecode -Data $parts[0]))) | ConvertFrom-Json
            Payload = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((Base64UrlDecode -Data $parts[1]))) | ConvertFrom-Json
            IsValid = $false
        }

        #validate the result using published keys
        $endpoint = $result.Payload.iss.Replace('/v2.0','/')

        $signingKeys = Invoke-RestMethod -Method Get -Uri "$($endpoint)discovery/keys"

        $key = $signingKeys.keys | Where-object{$_.kid -eq $result.Header.kid}
        if($null -eq $key)
        {
            throw "Could not find signing key with id = $($result.Header.kid)"
        }
        $cert = new-object System.Security.Cryptography.X509Certificates.X509Certificate2(,[Convert]::FromBase64String($key.x5c[0]))
        $rsa = $cert.PublicKey.Key

        $payload = "$($parts[0]).$($parts[1])"
        $dataToVerify = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $sig = Base64UrlDecode -Data $parts[2]
        $signature = [Convert]::FromBase64String($sig)

        switch($result.Header.alg)
        {
            'RS384' {
                $hash = [System.Security.Cryptography.HashAlgorithmName]::SHA384
                break;
            }
            'RS512' {
                $hash = [System.Security.Cryptography.HashAlgorithmName]::SHA512
                break;
            }
            default {
                $hash = [System.Security.Cryptography.HashAlgorithmName]::SHA256
                break;
            }
        }
        $padding = [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        $result.IsValid = $rsa.VerifyData($dataToVerify,$signature,$hash,$Padding)
        $cert.Dispose()
        if($null -ne $result.Header.nonce)
        {
            Write-Verbose "Header contains nonce, so token may not be properly validated. See https://github.com/AzureAD/azure-activedirectory-identitymodel-extensions-for-dotnet/issues/609"
        }
        $result.psobject.typenames.Insert(0,'GreyCorbel.Identity.Authentication.TokenValidationResult')
        $result
    }
}

#region Internals
function Base64UrlDecode
{
    param
    (
        [Parameter(Mandatory,ValueFromPipeline)]
        [string]$Data
    )

    process
    {
        $result = $Data
        $result = $result.Replace('-','+').Replace('_','/')

        switch($result.Length % 4)
        {
            0 {break;}
            2 {$result = "$result=="; break}
            3 {$result = "$result="; break;}
            default {throw "Invalid data format"}
        }

        $result
    }
}
function Init
{
    param()

    process
    {
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
                Add-Type -Assembly System.Net.Http
                break;
            }
        }
        Add-Type -Path "$PSScriptRoot\Shared\netstandard2.0\GreyCorbel.Identity.Authentication.dll"

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
}
#endregion

Init