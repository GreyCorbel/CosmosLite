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

.EXAMPLE
$proxy=new-object System.Net.WebProxy('http://myproxy.mycompany.com:8080')
$proxy.BypassProxyOnLocal=$true
$factory = New-AadAuthenticationFactory -TenantId mydomain.com  -RequiredScopes @('https://eventgrid.azure.net/.default') -AuthMode deviceCode -Proxy $proxy
$token = $factory | Get-AadToken

Description
-----------
Command works in on prem environment where access to internet is available via proxy. Command authenticates user with device code flow.

#>

    param
    (
        [Parameter(Mandatory)]
        [string[]]
            #Scopes to ask token for
        $RequiredScopes,

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

        [Parameter(ParameterSetName = 'MSI')]
        [Switch]
            #tries to get parameters from environment and token from internal endpoint provided by Azure MSI support
        $UseManagedIdentity,

        [Parameter()]
        [System.Net.WebProxy]
            #Web proxy configuration
            #Optional
        $proxy = $null

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
$token = $factory | Get-AadToken

Description
-----------
Command creates authentication factory and retrieves AAD token from it, authenticating user via web view or browser

.EXAMPLE
$cosmosDbAccountName = 'myCosmosDBAcct
$factory = New-AadAuthenticationFactory -RequiredScopes @("https://$cosmosDbAccountName`.documents.azure.com/.default") -UseManagedIdentity
$token = $factory | Get-AadToken

Description
-----------
Command creates authentication factory and retrieves AAD token for access data plane of cosmos DB aaccount.
For deatils on CosmosDB RBAC access, see https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-setup-rbac

.EXAMPLE
$factory = New-AadAuthenticationFactory -TenantId mydomain.com  -RequiredScopes @('https://eventgrid.azure.net/.default') -AuthMode WIA
$token = $factory | Get-AadToken

Description
-----------
Command works in Federated environment with ADFS. Command authenticates user silently with current credentials against ADFS and uses ADFS token to retrieve token from AAD

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
# SIG # Begin signature block
# MIIQvQYJKoZIhvcNAQcCoIIQrjCCEKoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUgksPl1SjGN0Q4wVka6Hr4ecY
# x1yggg2JMIIGsDCCBJigAwIBAgIQCK1AsmDSnEyfXs2pvZOu2TANBgkqhkiG9w0B
# AQwFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVk
# IFJvb3QgRzQwHhcNMjEwNDI5MDAwMDAwWhcNMzYwNDI4MjM1OTU5WjBpMQswCQYD
# VQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lD
# ZXJ0IFRydXN0ZWQgRzQgQ29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIwMjEg
# Q0ExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA1bQvQtAorXi3XdU5
# WRuxiEL1M4zrPYGXcMW7xIUmMJ+kjmjYXPXrNCQH4UtP03hD9BfXHtr50tVnGlJP
# DqFX/IiZwZHMgQM+TXAkZLON4gh9NH1MgFcSa0OamfLFOx/y78tHWhOmTLMBICXz
# ENOLsvsI8IrgnQnAZaf6mIBJNYc9URnokCF4RS6hnyzhGMIazMXuk0lwQjKP+8bq
# HPNlaJGiTUyCEUhSaN4QvRRXXegYE2XFf7JPhSxIpFaENdb5LpyqABXRN/4aBpTC
# fMjqGzLmysL0p6MDDnSlrzm2q2AS4+jWufcx4dyt5Big2MEjR0ezoQ9uo6ttmAaD
# G7dqZy3SvUQakhCBj7A7CdfHmzJawv9qYFSLScGT7eG0XOBv6yb5jNWy+TgQ5urO
# kfW+0/tvk2E0XLyTRSiDNipmKF+wc86LJiUGsoPUXPYVGUztYuBeM/Lo6OwKp7AD
# K5GyNnm+960IHnWmZcy740hQ83eRGv7bUKJGyGFYmPV8AhY8gyitOYbs1LcNU9D4
# R+Z1MI3sMJN2FKZbS110YU0/EpF23r9Yy3IQKUHw1cVtJnZoEUETWJrcJisB9IlN
# Wdt4z4FKPkBHX8mBUHOFECMhWWCKZFTBzCEa6DgZfGYczXg4RTCZT/9jT0y7qg0I
# U0F8WD1Hs/q27IwyCQLMbDwMVhECAwEAAaOCAVkwggFVMBIGA1UdEwEB/wQIMAYB
# Af8CAQAwHQYDVR0OBBYEFGg34Ou2O/hfEYb7/mF7CIhl9E5CMB8GA1UdIwQYMBaA
# FOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAK
# BggrBgEFBQcDAzB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGGGGh0dHA6Ly9v
# Y3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2NhY2VydHMuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcnQwQwYDVR0fBDwwOjA4
# oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJv
# b3RHNC5jcmwwHAYDVR0gBBUwEzAHBgVngQwBAzAIBgZngQwBBAEwDQYJKoZIhvcN
# AQEMBQADggIBADojRD2NCHbuj7w6mdNW4AIapfhINPMstuZ0ZveUcrEAyq9sMCcT
# Ep6QRJ9L/Z6jfCbVN7w6XUhtldU/SfQnuxaBRVD9nL22heB2fjdxyyL3WqqQz/WT
# auPrINHVUHmImoqKwba9oUgYftzYgBoRGRjNYZmBVvbJ43bnxOQbX0P4PpT/djk9
# ntSZz0rdKOtfJqGVWEjVGv7XJz/9kNF2ht0csGBc8w2o7uCJob054ThO2m67Np37
# 5SFTWsPK6Wrxoj7bQ7gzyE84FJKZ9d3OVG3ZXQIUH0AzfAPilbLCIXVzUstG2MQ0
# HKKlS43Nb3Y3LIU/Gs4m6Ri+kAewQ3+ViCCCcPDMyu/9KTVcH4k4Vfc3iosJocsL
# 6TEa/y4ZXDlx4b6cpwoG1iZnt5LmTl/eeqxJzy6kdJKt2zyknIYf48FWGysj/4+1
# 6oh7cGvmoLr9Oj9FpsToFpFSi0HASIRLlk2rREDjjfAVKM7t8RhWByovEMQMCGQ8
# M4+uKIw8y4+ICw2/O/TOHnuO77Xry7fwdxPm5yg/rBKupS8ibEH5glwVZsxsDsrF
# hsP2JjMMB0ug0wcCampAMEhLNKhRILutG4UI4lkNbcoFUCvqShyepf2gpx8GdOfy
# 1lKQ/a+FSCH5Vzu0nAPthkX0tGFuv2jiJmCG6sivqf6UHedjGzqGVnhOMIIG0TCC
# BLmgAwIBAgIQAsnIm0KCskhyoko4ccQk0jANBgkqhkiG9w0BAQsFADBpMQswCQYD
# VQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lD
# ZXJ0IFRydXN0ZWQgRzQgQ29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIwMjEg
# Q0ExMB4XDTIyMDMyNTAwMDAwMFoXDTIzMDkwNTIzNTk1OVowVjELMAkGA1UEBhMC
# Q1oxDzANBgNVBAcTBlByYWd1ZTEaMBgGA1UEChMRR3JleUNvcmJlbCBzLnIuby4x
# GjAYBgNVBAMTEUdyZXlDb3JiZWwgcy5yLm8uMIIBojANBgkqhkiG9w0BAQEFAAOC
# AY8AMIIBigKCAYEAxOrdrFNq/ewx1indXOIRmzzVG0YYk5lxs9xHX6KSrXrmtpr3
# G/5lADaadZrlaL3NU4A/KLVpLVGBZspp0cGAspwbmdJUQAI5ywrdC5BvffgyxWou
# gx5vN3JA7KrJUelw5+/GQd+CArfUD7Lhyx10DGXfAUEOd9cxfcHRMeUHXHQdoVCb
# Hfd7BlOY1rZmhVCi7FOhfFcc4dXiWcWjc1NahopJ+rS4yA1MZxR9MORrTLWO7NZ4
# ktjMSHPJhM6XJGFFxW6rpWkAUWjZ85Fpu0ZCm/rkxsiOinLveRw7oUPAKeHkzdMl
# Kc9RSRf/SJY2mMmrPWTJQiyGF1rpPs1SXJ/OYPjv6b2KVYzf4D7vN+Lah2W2gpJB
# XDw+tyycJzgC4be0QhirHd+KDlej+gUR2mWy1NTTmth1yKIGtSrMtRypaJDlG1jl
# MSRB8zBjczjoCUdIW25nBvC+30qOxuumTKeoRsrEnh6S6/pE+3nPmsiA3l56UsSd
# I4du1Mgdip0d9cQxAgMBAAGjggIGMIICAjAfBgNVHSMEGDAWgBRoN+Drtjv4XxGG
# +/5hewiIZfROQjAdBgNVHQ4EFgQUTNBN7Cb/iOQ8SoCjYH7PKUjFTK8wDgYDVR0P
# AQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMIG1BgNVHR8Ega0wgaowU6BR
# oE+GTWh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNENv
# ZGVTaWduaW5nUlNBNDA5NlNIQTM4NDIwMjFDQTEuY3JsMFOgUaBPhk1odHRwOi8v
# Y3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRDb2RlU2lnbmluZ1JT
# QTQwOTZTSEEzODQyMDIxQ0ExLmNybDA+BgNVHSAENzA1MDMGBmeBDAEEATApMCcG
# CCsGAQUFBwIBFhtodHRwOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwgZQGCCsGAQUF
# BwEBBIGHMIGEMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20w
# XAYIKwYBBQUHMAKGUGh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dFRydXN0ZWRHNENvZGVTaWduaW5nUlNBNDA5NlNIQTM4NDIwMjFDQTEuY3J0MAwG
# A1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAKKWCA4wPrm6gGTRVIejICtU
# A8gHfzagsJqCKfhhguL4Ng0fR2++UiWkixR58TtPjeBUrZORK6cZ+QQUtY/wgN9i
# nYPmIPzFl+XkAg4DEATGxVc1bxcIS1Qh+jeK2fRfG2WUPHOeO0yDJegj5KtAxH4w
# XHR7kie/6/fXKqRqwKvKd8E0z0bw4BiTRc4qAGAj2aGpnUU6XzYpSzGQaY5b0PYX
# Z6bnCmIKj5QOdQCsjH9i6KGRxW9S8xgmplEqQwV0PvmCmY/1bvYl/eNYx0txXkBb
# oNfdQY+N6fVIfka4UA8I4MAwC20lcrtM4icBsr1Zjq6JUjsFn4xoT6XdxfR9JJAr
# mzGgNQzMWgJdery6oFG/jiblVt0TWHO31/3rPFtSeW4SQ6MnyNVznG/zIKDEOI5H
# njPvpWAetuElVySS6c0p2VHq6kyjptPmX+owNBY88gALq1+sHxH6DjXtdyRJ2aEq
# EyuSJPOEW9RsVtoP+Mf7fF6fRmGk3riYi/kLuYiPXtdJlcjiR+9phwILvaDai7rw
# /A7lkduWIjvmlsGdxyTf8U0ekvCOkKJ0RP2lZKb5j8bSPCDTrwQs3hbS1uimUObU
# b3gAInMyvitMLts4lehQcqCIdCXjjvxLJowBp4lt8Id91NXyVS2Gka5s+7ZSbGJV
# cjQCg4YGXX/WUAk6u5KcMYICnjCCApoCAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUG
# A1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQg
# RzQgQ29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIwMjEgQ0ExAhACycibQoKy
# SHKiSjhxxCTSMAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAA
# MBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgor
# BgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQpgLCYdTNvlxOtdl2BMDEhc3qFkjAN
# BgkqhkiG9w0BAQEFAASCAYAc32Trco8OgiPNLSS62sR4Y1+5N8bIETvHwpODMzH2
# MN8ZOZpnGy7hPRib7PVJK8jNSR8OCOoaS8/IFDGWsXIe4t59MXw6602rXimLPZpj
# nQfX78Jj/ylHKaSS/VLafQ5w2IFBZJQ1g9HkZmuK0zBhecaxMUqDXWG79Ne0yAyE
# sy6TbIqdy7JkumohAJXQ5+Nf8PmU/wQJ65UexZ8In1emVJrH3oelGPWr689KinZk
# dcm742uXgQbyU6F/iHaj5ir9CM2+9xaZ0b6XNS8cPxSjMkhsEd56I61RsW4wF3np
# GH0NkG3iu4wxQOC5e16J+f7M1HBW7R19XyMEP6DdmTmODhj2iGdZn7uE5VO0nrx4
# RthAKP6ytPvDu3uwzE4UeMuW76encirXgkOcsir9S3nn1TaJfOp+SofZPGWp/XAt
# zx5TumCHp57hzhWHk3jW1/EYcKoen/7DHviTZVkXGm/gbk9A5ux8kVS+wArKGkRx
# +pGoAJu/k0W6PxarzvjJNdo=
# SIG # End signature block
