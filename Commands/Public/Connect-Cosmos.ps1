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
    Connection configuration object.

.NOTES
    Most recently created configuration object is also cached inside the module and is automatically used when not provided to other commands

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myCosmosDb -TenantId mydomain.com -AuthMode Interactive

    Description
    -----------
    This command returns configuration object for working with CosmosDB account myCosmosDbAccount and database myCosmosDb in tenant mydomain.com, with Delegated auth flow

.EXAMPLE
    $thumbprint = 'e827f78a7acf532eb539479d6afe9c7f703173d5'
    $appId = '1b69b00f-08fc-4798-9976-af325f7f7526'
    $cert = dir Cert:\CurrentUser\My\ | where-object{$_.Thumbprint -eq $thumbprint}
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -TenantId mycompany.com -ClientId $appId -X509Certificate $cert

    Description
    -----------
    This command returns configuration object for working with CosmosDB account myCosmosDbAccount and database myCosmosDb in tenant mycompany.com, with Application auth flow

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myCosmosDb -UseManagedIdentity

    Description
    -----------
    This command returns configuration object for working with CosmosDB account myCosmosDbAccount and database myCosmosDb, with authentication by System-assigned Managed Identity

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myCosmosDb -ClientId '3a174b1e-7b2a-4f21-a326-90365ff741cf' -UseManagedIdentity

    Description
    -----------
    This command returns configuration object for working with CosmosDB account myCosmosDbAccount and database myCosmosDb, with authentication by User-assigned Managed Identity
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

        [Parameter(ParameterSetName = 'ExistingFactory')]
        [object]
            #Existing factory to use rather than create a new one
        $Factory,

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
        $ClientId = (Get-AadDefaultClientId),

        [Parameter()]
        [Uri]
            #RedirectUri for the client
            #Default: default MSAL redirect Uri
        $RedirectUri,

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
            #Note: Does not work for federated authentication - see https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth-ropc
        $ResourceOwnerCredential,

        [Parameter()]
        [string]
            #AAD auth endpoint
            #Default: endpoint for public cloud
        $LoginApi = 'https://login.microsoftonline.com',
        
        [Parameter(Mandatory, ParameterSetName = 'PublicClient')]
        [ValidateSet('Interactive', 'DeviceCode', 'WIA', 'WAM')]
        [string]
            #How to authenticate client - via web view or via device code flow
        $AuthMode,
        
        [Parameter(ParameterSetName = 'PublicClient')]
        [string]
            #Username hint for interactive authentication flows
        $UserNameHint,

        [Parameter(ParameterSetName = 'MSI')]
        [Switch]
            #tries to get parameters from environment and token from internal endpoint provided by Azure MSI support
        $UseManagedIdentity,

        [Switch]
            #Whether to collect all response headers
        $CollectResponseHeaders,
        [switch]
            #Whether to use preview API version
        $Preview,

        [Parameter(ParameterSetName = 'PublicClient')]
        [Parameter(ParameterSetName = 'ConfidentialClientWithSecret')]
        [Parameter(ParameterSetName = 'ConfidentialClientWithCertificate')]
        [Parameter(ParameterSetName = 'ResourceOwnerPasssword')]
        [System.Net.WebProxy]
            #WebProxy object if connection to Azure has to go via proxy server
        $Proxy = $null,
        [Parameter()]
        [int]
            #Max number of retries when server returns http error 429 (TooManyRequests) before returning this error to caller
        $RetryCount = 10
    )

    process
    {
        if($null -ne $proxy)
        {
            [system.net.webrequest]::defaultwebproxy = $Proxy
        }

        $script:httpClient = new-object System.Net.Http.HttpClient
        $script:Configuration = [PSCustomObject]@{
            PSTypeName = "CosmosLite.Connection"
            AccountName = $AccountName
            Endpoint = "https://$accountName`.documents.azure.com/dbs/$Database"
            RetryCount = $RetryCount
            Session = @{}
            CollectResponseHeaders = $CollectResponseHeaders
            RequiredScopes = @("https://$accountName`.documents.azure.com/.default")    #we keep scopes separately to override any default scopes set on existing factory passed 
            AuthFactory = $null
            ApiVersion = $(if($Preview) {'2020-07-15'} else {'2018-12-31'})  #we don't use PS7 ternary operator to be compatible wirh PS5
        }

        try {
                switch($PSCmdlet.ParameterSetName)
                {
                    'ExistingFactory' {
                        #nothing specific here
                        break;
                    }
                    'PublicClient' {
                        $Factory = New-AadAuthenticationFactory -TenantId $TenantId -ClientId $ClientId -RedirectUri $RedirectUri -LoginApi $LoginApi -AuthMode $AuthMode -DefaultUsername $UserNameHint -Proxy $proxy
                        break;
                    }
                    'ConfidentialClientWithSecret' {
                        $Factory = New-AadAuthenticationFactory -TenantId $TenantId -ClientId $ClientId -RedirectUri $RedirectUri -ClientSecret $clientSecret -LoginApi $LoginApi  -Proxy $proxy
                        break;
                    }
                    'ConfidentialClientWithCertificate' {
                        $Factory = New-AadAuthenticationFactory -TenantId $TenantId -ClientId $ClientId -X509Certificate $X509Certificate -LoginApi $LoginApi -Proxy $proxy
                        break;
                    }
                    'MSI' {
                        $Factory = New-AadAuthenticationFactory -ClientId $clientId -UseManagedIdentity -Proxy $proxy
                        break;
                    }
                    'ResourceOwnerPasssword' {
                        $Factory = New-AadAuthenticationFactory -TenantId $TenantId -ClientId $ClientId -LoginApi $LoginApi -ResourceOwnerCredential $ResourceOwnerCredential -Proxy $proxy
                        break;
                    }
                }
                $script:Configuration.AuthFactory = $Factory
                $script:Configuration
        }
        catch {
            throw
        }
    }
}