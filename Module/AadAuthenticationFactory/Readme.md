# AadAuthenticationFactory
This module provides unified experience for getting and using tokens from Azure AD authentication platform. Experience covers this authentication scenarios:
  - Interactive authentication with Public client flow and Delegated permissions. Uses standard MSAL implementation of Public flow with Browser based interactive authentication, or Device code authentication
  - Non-interactive authentication with Confidential client flow and Application permissions. Uses standard MSAL implementation of Confidential client with authentication via Client Secret of via X.509 certificate
  - Non-Interactive authentication via Azure Managed Identity, usable on Azure VMs, Azure App Services, Azure Functions or other platforms that support Azure Managed identity. Supports both System Managed Identity or User Managed Identity.

Module comes with commands:

|Command|Usage|
|:------|:----|
|New-AadAuthenticationFactory | Creates factory responsible for issuing of AAD tokens for given resource, using given authentication flow|
|Get-AAdToken|Tells the factory to create a token. Factory returns cached token, if available, and takes care of token renewals silently whenever possible, after tokens expire|
|Test-AadToken|Parses Access token or Id token and validates it against published keys. Provides PowerShell way of showing token content as available in http://jwt.ms|

Module is meant to provide instant authentication services to other modules relying on AAD authentication  just make dependency on AadAuthenticationFactory module inother module and use it to get tokens for resources as you need. This is demonstrated by CosmosLite module in this repo.

# Examples

## Simple usage with single factory and default Public client
Module caches most-recently created factory. Factory uses Client Id of Azure Powershell app provided by MS. Sample uses browser based authentication and gives Delegated permissions configured for Azure Powershell for Graph API to calling user.
```powershell
#create authnetication factory and cache it inside module
New-AadAuthenticationFactory -TenantId mytenant.com -RequiredScopes 'https://graph.microsoft.com/.default' -AuthMode Interactive | Out-Null

#ask for token
$Token = Get-AadToken

#examine access token data
$Token.AccessToken | Test-AadToken | Select -Expand Payload
#examine ID token data
$Token.IdToken | Test-AadToken | Select -Expand Payload
```

## Custom app and certificate auth with Confidential client
This sample creates multiple authentication factories for getting tokens for different resources for application that uses X.509 certificate for authentication.

```powershell
#load certificate for auth
$thumbprint = 'e827f78a78cf532eb539479d6afe9c7f703173d5'
$appId = '1b69b00f-08f0-4798-9976-af325f7f7526'
$cert = dir Cert:\CurrentUser\My\ | where-object{$_.Thumbprint -eq $thumbprint}

#create factory for issuing of tokens for Graph Api
$graphFactory = New-AadAuthenticationfactory -tenantId mydomain.com -ClientId $appId --X509Certificate $cert -RequiredScopes 'https://graph.microsoft.com/.default'
#create factory for issuing of tokens for Azure KeyVault
$vaultFactory = New-AadAuthenticationfactory -tenantId mydomain.com -ClientId $appId --X509Certificate $cert -RequiredScopes 'https://vault.azure.net/.default'

#get tokens
$graphToken = Get-AadToken -Factory $graphFactory
$vaultToken = $vaultFactory | Get-AadToken

#examine tokens
Test-AadToken -Token $graphToken.AccessToken
Test-AadToken -Token $vaultToken.AccessToken
```

## System assigned Managed identity
This sample assumes that code runs in environment supporting Azure Managed identity and uses it to get tokens.
```powershell
$azConfigFactory = New-AadAuthenticationfactory -RequiredScopes 'https://azconfig.io/.default' -UseManagedIdentity
#create factory for issuing of tokens for Azure KeyVault
$vaultFactory = New-AadAuthenticationfactory -UseManagedIdentity -RequiredScopes 'https://vault.azure.net/.default'

#get tokens
$graphToken = Get-AadToken -Factory $graphFactory
$vaultToken = $vaultFactory | Get-AadToken
```
## User assigned Managed identity
This sample assumes that code runs in environment supporting Azure Managed identity and uses it to get tokens.
```powershell
$azConfigFactory = New-AadAuthenticationfactory -RequiredScopes 'https://azconfig.io/.default' -UseManagedIdentity -ClientId '3a174b1e-7b2a-4f21-a326-90365ff741cf'
Get-AadToken | Select-object -expandProperty AccessToken | Test-AadToken | select-object -expandProperty payload
```
