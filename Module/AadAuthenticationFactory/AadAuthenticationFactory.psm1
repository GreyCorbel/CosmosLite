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
        [Parameter(Mandatory)]
        [string]
            #Id of tenant where to autenticate the user. Can be tenant id, or any registerd DNS domain
        $TenantId,

        [Parameter()]
        [string]
            #ClientId of application that gets token to CosmosDB.
            #Default: well-known clientId for Azure PowerShell - it already has pre-configured Delegated permission to access CosmosDB resource
        $ClientId = '1950a258-227b-4e31-a9cf-717495945fc2',

        [Parameter(Mandatory)]
        [string[]]
            #Scopes to ask token for
        $RequiredScopes,
        [Parameter(ParameterSetName = 'ConfidentialClientWithSecret')]
        [string]
            #Client secret for ClientID
            #Used to get access as application rather than as calling user
        $ClientSecret,

        [Parameter(ParameterSetName = 'ConfidentialClientWithCertificate')]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
            #Authentication certificate for ClientID
            #Used to get access as application rather than as calling user
        $X509Certificate,

        [Parameter()]
        [string]
            #AAD auth endpoint
            #Default: endpoint for public cloud
        $LoginApi = 'https://login.microsoftonline.com',
        
        [Parameter(Mandatory, ParameterSetName = 'PublicClient')]
        [ValidateSet('Interactive', 'DeviceCode')]
        [string]
            #How to authenticate client - via web view or via device code flow
        $AuthMode,
        
        [Parameter(ParameterSetName = 'PublicClient')]
        [string]
            #Username hint for authentication UI
        $UserNameHint
    )

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

        switch($PSCmdlet.ParameterSetName)
        {
            'PublicClient' {
                new-object GreyCorbel.Identity.Authentication.AadAuthenticationFactory($tenantId, $ClientId, $RequiredScopes, $LoginApi, $AuthMode, $UserNameHint)
                break;
            }
            'ConfidentialClientWithSecret' {
                new-object GreyCorbel.Identity.Authentication.AadAuthenticationFactory($tenantId, $ClientId, $clientSecret, $RequiredScopes, $LoginApi)
                break;
            }
            'ConfidentialClientWithCertificate' {
                new-object GreyCorbel.Identity.Authentication.AadAuthenticationFactory($tenantId, $ClientId, $X509Certificate, $RequiredScopes, $LoginApi)
                break;
            }
        }
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
$factory = New-AadAuthenticationFactory -TenantId mydomain.com  -RequiredScopes @('https://documents.azure.com/.default') -AuthMode Interactive
$factory | Get-AadToken

Description
-----------
Command creates authentication factory and retrieves AAD token from it

#>

    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        [GreyCorbel.Identity.Authentication.AadAuthenticationFactory]
            #AAD authentication factory created via New-AadAuthenticationFactory
        $Factory
    )

    process
    {
        $factory.AuthenticateAsync().GetAwaiter().GetResult()
    }
}
