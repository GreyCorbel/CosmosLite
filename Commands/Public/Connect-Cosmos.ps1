function Connect-Cosmos
{
    <#
.SYNOPSIS
    Creates a CosmosLite connection context.

.DESCRIPTION
    Builds and stores a CosmosLite connection configuration used by all public commands.
    The command does not send a network request by itself; authentication and connection happen on the first data operation.
    Supports interactive public client auth, confidential client auth, resource owner password flow, managed identity, or a prebuilt authentication factory.

.PARAMETER AccountName
    The name of the Azure Cosmos DB account to connect to.

.PARAMETER Database
    The name of the database within the Cosmos DB account.

.PARAMETER Factory
    An existing authentication factory object to use instead of creating a new one. Used with the ExistingFactory parameter set.

.PARAMETER TenantId
    The ID of the Azure Active Directory tenant where the user will be authenticated. Can be a tenant ID (GUID) or a registered DNS domain.
    Not required when using managed identity, but mandatory for public client, confidential client, and resource owner password flows.

.PARAMETER ClientId
    The client ID (application ID) of the Azure AD application used to obtain tokens for Cosmos DB.
    Default: The well-known client ID for Azure PowerShell, which has pre-configured delegated permissions to access Cosmos DB resources.

.PARAMETER RedirectUri
    The redirect URI for the client application, used in interactive authentication flows.
    Default: The default MSAL (Microsoft Authentication Library) redirect URI.

.PARAMETER Scope
    A custom scope to request tokens for instead of the default scope derived from the account name.
    Example: https://cosmos.azure.com/.default

.PARAMETER ClientSecret
    The client secret for the application ID. Used for confidential client authentication to obtain tokens as an application rather than as a user.

.PARAMETER X509Certificate
    An X.509 certificate for the application ID. Used for certificate-based confidential client authentication.

.PARAMETER ResourceOwnerCredential
    A PSCredential object containing the resource owner's username and password.
    Used for resource owner password flow (ROPC) authentication.
    Note: Does not work with federated authentication. See https://learn.microsoft.com/azure/active-directory/develop/v2-oauth-ropc

.PARAMETER Environment
    The Azure cloud environment to connect to. Valid values: PublicCloud, USGovernment, China.
    Default: PublicCloud
    Determines the appropriate REST API endpoints and login endpoints for the specified cloud.

.PARAMETER LoginApi
    The Azure Active Directory authentication endpoint URL.
    Default: Automatically determined based on the selected Environment.

.PARAMETER AuthMode
    The authentication mode for public client flows. Valid values: Interactive, DeviceCode, WIA (Windows Integrated Authentication), WAM (Web Account Manager).
    Required when using the PublicClient parameter set.

.PARAMETER UserNameHint
    A username hint to pre-populate in interactive authentication flows.

.PARAMETER UseManagedIdentity
    When specified, attempts to obtain authentication parameters from the environment and retrieves tokens from the Azure managed identity endpoint.
    Used for authentication in Azure-hosted environments with managed identities enabled.

.PARAMETER CollectResponseHeaders
    When specified, collects all response headers from Cosmos DB API responses.

.PARAMETER Preview
    When specified, uses the preview Cosmos DB API version (2020-07-15) instead of the stable version (2018-12-31).

.PARAMETER Proxy
    A System.Net.WebProxy object if the connection to Azure must route through a proxy server.

.PARAMETER RetryCount
    The maximum number of automatic retries when the server returns HTTP 429 (Too Many Requests).
    Default: 10

.PARAMETER MaxContinuationTokenSizeInKb
    The maximum size of continuation tokens in kilobytes.
    Default: 4 KB
    Decrease this value if experiencing 'Request too large' errors.

.OUTPUTS
    CosmosLite.Connection object with the following properties:
    - PSTypeName: CosmosLite.Connection
    - AccountName: The Cosmos DB account name
    - Endpoint: The full endpoint URI for the database
    - RetryCount: Configured retry count
    - Session: Cached session data
    - CollectResponseHeaders: Whether response headers are collected
    - RequiredScopes: OAuth scopes for authentication
    - AuthFactory: The authentication factory object
    - ApiVersion: The API version being used
    - HttpClient: The HTTP client for requests
    - MaxContinuationTokenSizeInKb: Maximum continuation token size

.NOTES
    The most recently created connection is cached in module scope and used automatically by other commands when the -Context parameter is omitted.

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myCosmosDb -TenantId mydomain.com -AuthMode Interactive

    Description
    -----------
    Creates a connection context using delegated interactive authentication with the specified tenant and interactive authentication mode.

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myCosmosDb -UseManagedIdentity

    Description
    -----------
    Creates a connection context using the local managed identity endpoint. Useful when running in Azure-hosted environments like Azure Functions or App Service.

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myCosmosDb -TenantId mydomain.com -ClientId 'app-id' -ClientSecret 'secret'

    Description
    -----------
    Creates a connection context using confidential client authentication with a client secret (application credentials).

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myCosmosDb -TenantId mydomain.com -AuthMode DeviceCode

    Description
    -----------
    Creates a connection context using device code flow, useful for scenarios where an interactive browser is not available.
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
        [Parameter(ParameterSetName = 'ResourceOwnerPassword')]
        [string]
            #Id of tenant where to authenticate the user. Can be tenant id, or any registered DNS domain
            #Not necessary when connecting with Managed Identity, otherwise necessary
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

        [Parameter()]
        [string]
            #Custom scope to request token for instead of default one constructed from AccountName
            #Typical generic scope: https://cosmos.azure.com/.default
        $Scope,

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

        [Parameter(ParameterSetName = 'ResourceOwnerPassword')]
        [pscredential]
            #Resource Owner username and password
            #Used to get access as user
            #Note: Does not work for federated authentication - see https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth-ropc
        $ResourceOwnerCredential,

        [Parameter()]
        [ValidateSet('PublicCloud', 'USGovernment', 'China')]
        [string]
            #cloud environment to connect to. Used to determine the correct REST API endpoint and login endpoint for the cloud. Default is PublicCloud.
            $Environment = 'PublicCloud',
        [Parameter()]
        [string]
            #AAD auth endpoint
            #Default: endpoint for public cloud
        $LoginApi,
        
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
        [Parameter(ParameterSetName = 'ResourceOwnerPassword')]
        [System.Net.WebProxy]
            #WebProxy object if connection to Azure has to go via proxy server
        $Proxy = $null,
        [Parameter()]
        [int]
            #Max number of retries when server returns http error 429 (TooManyRequests) before returning this error to caller
        $RetryCount = 10,
        [Parameter()]
        [int]
            #Maximum continuation token size in KB
            #Default: 4KB
            #Decrease when experiencing error 'Request too large'
        $MaxContinuationTokenSizeInKb = 4
    )

    process
    {
        if($null -ne $proxy)
        {
            [system.net.webrequest]::defaultwebproxy = $Proxy
        }
        switch($Environment)
        {
            'PublicCloud' {
                $LoginApi = 'https://login.microsoftonline.com'
                $accountEndpoint = "https://$accountName.documents.azure.com"
                break;
            }
            'USGovernment' {
                $LoginApi = 'https://login.microsoftonline.us'
                $accountEndpoint = "https://$accountName.documents.azure.us"
                break;
            }
            'China' {
                $LoginApi = 'https://login.chinacloudapi.cn'
                $accountEndpoint = "https://$accountName.documents.azure.cn"
                break;
            }
        }
        $script:Configuration = [PSCustomObject]@{
            PSTypeName = "CosmosLite.Connection"
            AccountName = $AccountName
            Endpoint = "$accountEndpoint/dbs/$Database"
            RetryCount = $RetryCount
            Session = @{}
            CollectResponseHeaders = $CollectResponseHeaders
            RequiredScopes = @("$accountEndpoint/.default")    #we keep scopes separately to override any default scopes set on existing factory passed 
            AuthFactory = $null
            ApiVersion = $(if($Preview) {'2020-07-15'} else {'2018-12-31'})  #we don't use PS7 ternary operator to be compatible wirh PS5
            HttpClient = new-object System.Net.Http.HttpClient
            MaxContinuationTokenSizeInKb = $MaxContinuationTokenSizeInKb
        }

        try {
            if(-not [string]::IsNullOrEmpty($Scope))
            {
                $script:Configuration.RequiredScopes = @($Scope)
            }
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
                'ResourceOwnerPassword' {
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