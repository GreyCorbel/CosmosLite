function Connect-Cosmos
{
    <#
.SYNOPSIS
    Creates a CosmosLite connection context.

.DESCRIPTION
    Builds and stores a CosmosLite connection configuration used by all public commands.
    The command does not send a network request by itself; authentication and connection happen on the first data operation.
    Supports interactive public client auth, confidential client auth, resource owner password flow, managed identity, or a prebuilt authentication factory.

.OUTPUTS
    CosmosLite.Connection object.

.NOTES
    The most recently created connection is cached in module scope and used automatically by other commands when -Context is omitted.

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myCosmosDb -TenantId mydomain.com -AuthMode Interactive

    Description
    -----------
    Creates a connection context using delegated interactive authentication.

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myCosmosDb -UseManagedIdentity

    Description
    -----------
    Creates a connection context using the local managed identity endpoint.
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