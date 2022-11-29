function Connect-Cosmos
{
    <#
.SYNOPSIS
    Sets up connection parameters to Cosmos DB.
    Does not actually perform the connection - connection is established with first request, including authentication

.DESCRIPTION
    Sets up connection parameters to Cosmos DB.
    Does not actually perform the connection - connection is established with first request, including authentication.
    Authentication uses by default well-know clientId of Azure Powershell, but can accept clientId of app registered in your own tenant. In this case, application shall have configured API permission to allow delegated access to CosmosDB resource (https://cosmos.azure.com/user_impersonation), or - for Confidential client - RBAC role on CosmosDB account

.OUTPUTS
    Connection configuration object

.EXAMPLE
Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -TenantId mydomain.com -AuthMode Interactive

Description
-----------
This command returns configuration object for working with CosmosDB account myCosmosDbAccount and database myDbInCosmosAccount in tenant mydomain.com, with Delegated auth flow

.EXAMPLE
$thumbprint = 'e827f78a7acf532eb539479d6afe9c7f703173d5'
$appId = '1b69b00f-08fc-4798-9976-af325f7f7526'
$cert = dir Cert:\CurrentUser\My\ | where-object{$_.Thumbprint -eq $thumbprint}
Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -TenantId mycompany.com -ClientId $appId -X509Certificate $cert

Description
-----------
This command returns configuration object for working with CosmosDB account myCosmosDbAccount and database myDbInCosmosAccount in tenant mycompany.com, with Application auth flow

.EXAMPLE

Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -UseManagedIdentity

Description
-----------
This command returns configuration object for working with CosmosDB account myCosmosDbAccount and database myDbInCosmosAccount, with authentication by System-assigned Managed Identity

.EXAMPLE

Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -ClientId '3a174b1e-7b2a-4f21-a326-90365ff741cf' -UseManagedIdentity

Description
-----------
This command returns configuration object for working with CosmosDB account myCosmosDbAccount and database myDbInCosmosAccount, with authentication by User-assigned Managed Identity
#>

    param
    (
        [Parameter(Mandatory)]
        [string]
            #Name of CosmosDB account.
        $AccountName,

        [Parameter(Mandatory)]
        [string]
            #Name of database in CosmosDB account
        $Database,

        [Parameter(ParameterSetName = 'PublicClient')]
        [Parameter(ParameterSetName = 'ConfidentialClientWithSecret')]
        [Parameter(ParameterSetName = 'ConfidentialClientWithCertificate')]
        [Parameter(ParameterSetName = 'ResourceOwnerPasssword')]
        [string]
            #Id of tenant where to autenticate the user. Can be tenant id, or any registerd DNS domain
            #Not necessary when connecting with Managed Identity, otherwise ncesessary
        $TenantId,

        [Parameter()]
        [string]
            #ClientId of application that gets token to CosmosDB.
            #Default: well-known clientId for Azure PowerShell - it already has pre-configured Delegated permission to access CosmosDB resource
        $ClientId = '1950a258-227b-4e31-a9cf-717495945fc2',

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

        [Parameter(ParameterSetName = 'ResourceOwnerPasssword')]
        [pscredential]
            #Resource Owner username and password
            #Used to get access as user
            #Note: Does not work for federated authentication
        $ResourceOwnerCredential,

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
            #How to authenticate user - via web view or via device code flow
        $UserNameHint,

        [Parameter(ParameterSetName = 'MSI')]
        [Switch]
            #tries to get parameters from environment and token from internal endpoint provided by Azure MSI support
        $UseManagedIdentity,

        [Switch]
            #Whether to collect all response headers
        $CollectResponseHeaders,

        [Parameter()]
        [string]
            #Name of the proxy if connection to Azure has to go via proxy server
        $Proxy
    )

    process
    {
        if(-not [string]::IsNullOrWhitespace($proxy))
        {
            [system.net.webrequest]::defaultwebproxy = new-object system.net.webproxy($Proxy)
            [system.net.webrequest]::defaultwebproxy.credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
            [system.net.webrequest]::defaultwebproxy.BypassProxyOnLocal = $true
        }

        $script:httpClient = new-object System.Net.Http.HttpClient
        $script:Configuration = [PSCustomObject]@{
            AccountName = $AccountName
            Endpoint = "https://$accountName`.documents.azure.com/dbs/$Database"
            RetryCount = 10
            Session = @{}
            CollectResponseHeaders = $CollectResponseHeaders
        }

        $RequiredScopes = @("https://$accountName`.documents.azure.com/.default")

        if($null -eq $script:AuthFactories) {$script:AuthFactories = @{}}
        try {
                switch($PSCmdlet.ParameterSetName)
                {
                    'PublicClient' {
                        $script:AuthFactories[$AccountName] = New-AadAuthenticationFactory -TenantId $TenantId -ClientId $ClientId -RequiredScopes $RequiredScopes -LoginApi $LoginApi -AuthMode $AuthMode -UserNameHint $UserNameHint
                        break;
                    }
                    'ConfidentialClientWithSecret' {
                        $script:AuthFactories[$AccountName] = New-AadAuthenticationFactory -TenantId $TenantId -ClientId $ClientId -ClientSecret $clientSecret -RequiredScopes $RequiredScopes -LoginApi $LoginApi
                        break;
                    }
                    'ConfidentialClientWithCertificate' {
                        $script:AuthFactories[$AccountName] = New-AadAuthenticationFactory -TenantId $TenantId -ClientId $ClientId -X509Certificate $X509Certificate -RequiredScopes $RequiredScopes -LoginApi $LoginApi
                        break;
                    }
                    'MSI' {
                        $script:AuthFactories[$AccountName] = New-AadAuthenticationFactory -ClientId $clientId -RequiredScopes $RequiredScopes
                        break;
                    }
                    'ResourceOwnerPasssword' {
                        $script:AuthFactories[$AccountName] = New-AadAuthenticationFactory -TenantId $TenantId -ClientId $ClientId -ClientSecret $clientSecret -RequiredScopes $RequiredScopes -LoginApi $LoginApi -ResourceOwnerCredential $ResourceOwnerCredential
                        break;
                    }
                }
                $script:Configuration | Select-Object Endpoint, RetryCount
        }
        catch {
            throw $_.Exception
        }
    }
}