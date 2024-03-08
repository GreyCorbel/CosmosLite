
#region Initialization
if($PSEdition -eq 'Desktop')
{
    add-type -AssemblyName system.web
}
#endregion Initialization

#region Definitions
class CosmosLiteException : Exception {
    [string] $Code
    [PSCustomObject] $Request

    CosmosLiteException($Code, $Message) : base($Message) {
        $this.Code = $code
        $this.Request = $null
    }
    CosmosLiteException($Code, $Message, $request) : base($Message) {
        $this.Code = $code
        $this.Request = $request
    }

    [string] ToString() {
        return "$($this.Code): $($this.Message)"
     }
}
#endregion Definitions

#region Public
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
function Get-CosmosAccessToken
{
    <#
.SYNOPSIS
    Retrieves AAD token for authentication with selected CosmosDB

.DESCRIPTION
    Retrieves AAD token for authentication with selected CosmosDB.
    Can be used for debug purposes; module itself gets token as needed, including refreshing the tokens when they expire

.OUTPUTS
    AuthenticationResult returned by AAD that contains access token and other information about logged-in identity.

.NOTES
    See https://learn.microsoft.com/en-us/dotnet/api/microsoft.identity.client.authenticationresult

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -TenantId mydomain.com | Get-CosmosAccessToken

    Description
    -----------
    This command retrieves configuration for specified CosmosDB account and database, and retrieves access token for it using well-known clientId of Azure PowerShell
#>

    param
    (
        [Parameter(ValueFromPipeline)]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
        $context = $script:Configuration
    )

    process
    {
        if([string]::IsNullOrEmpty($context))
        {
            throw ([CosmosLiteException]::new('NotInitialized', 'Call Connect-Cosmos first'))
        }

        if($null -eq $context.AuthFactory)
        {
            throw ([CosmosLiteException]::new('NotInitialized', "Call Connect-Cosmos first for CosmosDB account = $($context.AccountName)"))

        }
        #we specify scopes here in case that user pushes own factory without properly specified default scopes
        Get-AadToken -Factory $context.AuthFactory -Scopes $context.RequiredScopes
    }
}
function Get-CosmosCollectionPartitionKeyRanges
{
<#
.SYNOPSIS
    Retrieves partition key ranges for the collection

.DESCRIPTION
    Retrieves partition key ranges for the collection  
    This helps with execution of cross partition queries

.OUTPUTS
    Response containing partition key ranges for collection.

.EXAMPLE
    $rsp = Get-CosmosCollectioPartitionKeyRanges -Collection 'docs'
    $rsp.data

    Description
    -----------
    This command retrieves partition key ranges for collection 'docs'
#>
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
            #Name of collection conaining the document
        $Collection,

        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($context.Endpoint)/colls/$collection/pkranges"
        $outstandingRequests=@()
    }

    process
    {
        $rq = Get-CosmosRequest -Context $Context -Collection $Collection
        $rq.Uri = new-object System.Uri("$url")

        $rq.Method = [System.Net.Http.HttpMethod]::Get

        $outstandingRequests+=SendRequestInternal -rq $rq -Context $Context
        if($outstandingRequests.Count -ge $batchSize)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
            $outstandingRequests=@()
        }
    }
    end
    {
        if($outstandingRequests.Count -gt 0)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
        }
    }
}
function Get-CosmosConnection
{
<#
.SYNOPSIS
    Returns most recently created Cosmos connection object

.DESCRIPTION
    Returns most recently created cosmos connection object that is cached inside the module.
    Useful when you do not want to keep connection object in variable and reach for it only when needed

.OUTPUTS
    Connection configuration object.

#>
    param ()

    process
    {
        $script:Configuration
    }
}
function Get-CosmosDocument
{
<#
.SYNOPSIS
    Retrieves document from the collection

.DESCRIPTION
    Retrieves document from the collection by id and partition key
    Command supports parallel processing.

.OUTPUTS
    Response containing retrieved document parsed from JSON format.

.EXAMPLE
    $rsp = Get-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs'
    $rsp.data

    Description
    -----------
    This command retrieves document with id = '123' and partition key 'test-docs' from collection 'docs'
#>
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
            #Id of the document
        $Id,

        [Parameter(Mandatory)]
        [string[]]
            #value of partition key for the document
        $PartitionKey,

        [Parameter(Mandatory)]
        [string]
            #Name of collection conaining the document
        $Collection,

        [Parameter()]
        [string]
            #ETag to check. Document is retrieved only if server version of document has different ETag
        $Etag,

        [Parameter()]
        [ValidateSet('High','Low')]
        [string]
            #Priority assigned to request
            #High priority requests have less chance to get throttled than Low priority requests when throttlig occurs
            #Default: High
        $Priority,

        [Parameter()]
        [int]
            #Degree of paralelism for pipeline processing
        $BatchSize = 1,

        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($context.Endpoint)/colls/$collection/docs"
        $outstandingRequests=@()
    }

    process
    {
        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Context $Context -Collection $Collection
        $rq.Method = [System.Net.Http.HttpMethod]::Get
        $rq.Uri = new-object System.Uri("$url/$id")
        $rq.ETag = $ETag
        $rq.PriorityLevel = $Priority

        $outstandingRequests+=SendRequestInternal -rq $rq -Context $Context
        if($outstandingRequests.Count -ge $batchSize)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
            $outstandingRequests=@()
        }
    }
    end
    {
        if($outstandingRequests.Count -gt 0)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
        }
    }
}
function Invoke-CosmosQuery
{
<#
.SYNOPSIS
    Queries collection for documents

.DESCRIPTION
    Queries the collection and returns documents that fulfill query conditions.
    Data returned may not be complete; in such case, returned object contains continuation token in 'Continuation' property. To receive more data, execute command again with parameter ContinuationToken set to value returned in Continuation field by previous command call.
    
.OUTPUTS
    Response describing result of operation

.EXAMPLE
    $query = "select * from c where c.itemType = @itemType"
    $queryParams = @{
        '@itemType' = 'person'
    }
    $totalRuConsumption = 0
    $data = @()
    do
    {
        $rsp = Invoke-CosmosQuery -Query $query -QueryParameters $queryParams -Collection 'docs' -ContinuationToken $rsp.Continuation
        if($rsp.IsSuccess)
        {
            $data += $rsp.data.Documents
        }
        $totalRuConsumption+=$rsp.Charge
    }while($null -ne $rsp.Continuation)
    "Total RU consumption: $totalRuConsumption"

    Description
    -----------
    This command performs cross partition parametrized query and iteratively fetches all matching documents. Command also measures total RU consumption of the query
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
            #Query string
        $Query,

        [Parameter()]
        [System.Collections.Hashtable]
            #Query parameters if the query string contains parameter placeholders
            #Parameter names must start with '@' char
        $QueryParameters,

        [Parameter()]
        [string[]]
            #Partition key for partition where query operates. If not specified, query queries all partitions - it's cross-partition query (expensive)
        $PartitionKey,

        [Parameter()]
        [string[]]
            #Partition key range id retrieved from Get-CosmosCollectionPartitionKeyRanges command
            #Helps execution cross-partition queries
        $PartitionKeyRangeId,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection
        $Collection,

        [Parameter()]
        [NUllable[UInt32]]
            #Maximum number of documents to be returned by query
            #When not specified, all matching documents are returned
        $MaxItems,

        [Parameter()]
        [string]
            #Continuation token. Used to ask for next page of results
        $ContinuationToken,

        [switch]
            #when response contains continuation token, returns the reesponse and automatically sends new request with continuation token
            #this simnlifies getting all data from query for large datasets
        $AutoContinue,

        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($context.Endpoint)/colls/$collection/docs"
    }

    process
    {
        do
        {
            $rq = Get-CosmosRequest `
                -PartitionKey $partitionKey `
                -PartitionKeyRangeId $PartitionKeyRangeId `
                -Type Query `
                -MaxItems $MaxItems `
                -Continuation $ContinuationToken `
                -Context $Context `
                -Collection $Collection

            $QueryDefinition = @{
                query = $Query
            }
            if($null -ne $QueryParameters)
            {
                $QueryDefinition['parameters']=@()
                foreach($key in $QueryParameters.Keys)
                {
                    $QueryDefinition['parameters']+=@{
                        name=$key
                        value=$QueryParameters[$key]
                    }
                }
            }
            $rq.Method = [System.Net.Http.HttpMethod]::Post
            $uri = "$url"
            $rq.Uri = New-Object System.Uri($uri)
            $rq.Payload = ($QueryDefinition | ConvertTo-Json -Depth 99 -Compress)
            $rq.ContentType = 'application/query+json'

            $response = ProcessRequestBatchInternal -Batch (SendRequestInternal -rq $rq -Context $Context) -Context $Context
            $response
            #auto-continue if requested
            if(-not $AutoContinue) {break;}
            if([string]::IsNullOrEmpty($response.Continuation)) {break;}
            $ContinuationToken = $response.Continuation
        }while($true)
    }
}
function Invoke-CosmosStoredProcedure
{
<#
.SYNOPSIS
    Call stored procedure

.DESCRIPTION
    Calls stored procedure.
    Command supports parallel processing.
    Note: Stored procedures that return large dataset also support continuation token, however, continuation token must be passed as parameter, corretly passed to query inside store procedure logivc, and returned as part of stored procedure response.
      This means that stored procedure logic is fully responsible for handling paging via continuation tokens. 
      For details, see Cosmos DB server side programming reference
    
.OUTPUTS
    Response describing result of operation

.EXAMPLE
    $params = @('123', 'test')
    $rsp = Invoke-CosmosStoredProcedure -Name testSP -Parameters ($params | ConvertTo-Json) -Collection 'docs' -PartitionKey 'test-docs'
    $rsp

    Description
    -----------
    This command calls stored procedure and shows result.
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
            #Name of stored procedure to call
        $Name,

        [Parameter(ValueFromPipeline)]
        [string]
            #Array of parameters to pass to stored procedure, serialized to JSON string
            #When passing array of objects as single parameter, be sure that array is properly formatted so as it is a single parameter object rather than array of parameters
        $Parameters,

        [Parameter()]
        [string[]]
            #Partition key identifying partition to operate upon.
            #Stored procedures are currently required to operate upon single partition only
        $PartitionKey,

        [Parameter(Mandatory)]
        [string]
            #Name of collection containing the stored procedure to call
        $Collection,

        [Parameter()]
        [int]
            #Degree of paralelism for pipelinr processing
        $BatchSize = 1,

        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($Context.Endpoint)/colls/$collection/sprocs"
        $outstandingRequests=@()
    }

    process
    {
        $rq = Get-CosmosRequest `
            -PartitionKey $partitionKey `
            -Type SpCall `
            -MaxItems $MaxItems `
            -Context $Context `
            -Collection $Collection
        
        $rq.Method = [System.Net.Http.HttpMethod]::Post
        $rq.Uri = new-object System.Uri("$url/$Name")
        $rq.Payload = $Parameters
        $rq.ContentType = 'application/json'

        $outstandingRequests+=SendRequestInternal -rq $rq -Context $Context
        if($outstandingRequests.Count -ge $batchSize)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
            $outstandingRequests=@()
        }
    }
    end
    {
        if($outstandingRequests.Count -gt 0)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
        }
    }
}
function New-CosmosDocumentUpdate
{
<#
.SYNOPSIS
    Constructs document update specification object expected by Update-CosmosDocument command

.DESCRIPTION
    Constructs document update description. Used together with Update-CosmosDocument and New-CosmoUpdateOperation commands.

.OUTPUTS
    Document update specification

.EXAMPLE
    $query = 'select c.id,c.pk from c where c.quantity < @threshold'
    $queryParams = @{
        '@threshold' = 10
    }
    $cntinuation = $null
    do
    {
        $rslt = Invoke-CosmosQuery -Query $query -QueryParameters $queryParams -Collection 'docs' ContinuationToken $continuation
        if(!$rslt.IsSuccess)
        {
            throw $rslt.Data
        }
        $rslt.Data.Documents | Foreach-Object {
            $DocUpdate = $_ | New-CosmosDocumentUpdate -PartitiokKeyAttribute pk
            $DocUpdate.Updates+=New-CosmosUpdateOperation -Operation Increament -TargetPath '/quantitiy' -Value 50
        } | Update-CosmosDocument -Collection 'docs' -BatchSize 4
        $continuation = $rslt.Continuation
    }while($null -ne $continuation)

    Description
    -----------
    This command increaments field 'quantity' by 50 on each documents that has value of this fields lower than 10
    Update is performed in parallel; up to 4 updates are performed at the same time
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string]
            #Id of the document to be replaced
        $Id,

        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string[]]
            #Partition key of new document
        $PartitionKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #Object representing document to create
            #Command performs JSON serialization via ConvertTo-Json -Depth 99
        $DocumentObject,

        [Parameter(Mandatory, ParameterSetName = 'DocumentObject')]
        [string[]]
            #attribute of DocumentObject used as partition key
        $PartitionKeyAttribute,

        [Parameter()]
        [string]
            #condition evaluated by the server that must be met to perform the updates
        $Condition
    )

    process
    {
        if($PSCmdlet.ParameterSetName -eq 'DocumentObject')
        {
            $id = $DocumentObject.id
            foreach($attribute in $PartitionKeyAttribute)
            {
                $PartitionKey+=$DocumentObject."$attribute"
            }
        }

        [PSCustomObject]@{
            PSTypeName = "CosmosLite.Update"
            Id = $Id
            PartitionKey = $PartitionKey
            Condition = $Condition
            Updates = @()
        }
    }
}
function New-CosmosDocument
{
<#
.SYNOPSIS
    Inserts new document into collection

.DESCRIPTION
    Inserts new document into collection, or replaces existing when asked to perform upsert.
    Command supports parallel processing.

.OUTPUTS
    Response describing result of operation

.EXAMPLE
    $doc = [Ordered]@{
        id = '123'
        pk = 'test-docs'
        content = 'this is content data'
    }
    New-CosmosDocument -Document ($doc | ConvertTo-Json) -PartitionKey 'test-docs' -Collection 'docs' -IsUpsert

    Description
    -----------
    This command creates new document with id = '123' and partition key 'test-docs' collection 'docs', replacing potentially existing document with same id and partition key
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'RawPayload')]
        [string]
            #JSON string representing the document data
        $Document,

        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string[]]
            #Partition key of new document
        $PartitionKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #Object representing document to create
            #Command performs JSON serialization via ConvertTo-Json -Depth 99
        $DocumentObject,

        [Parameter(Mandatory, ParameterSetName = 'DocumentObject')]
        [string[]]
            #attribute of DocumentObject used as partition key
        $PartitionKeyAttribute,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection where to store document in
        $Collection,

        [Parameter()]
        [string]
            #ETag to check. Document is upserted only if server version of document has the same Etag
        $Etag,

        [Parameter()]
        [ValidateSet('High','Low')]
        [string]
            #Priority assigned to request
            #High priority requests have less chance to get throttled than Low priority requests when throttlig occurs
        $Priority,

        [switch]
            #Whether to replace existing document with same Id and Partition key
        $IsUpsert,

        [switch]
            #asks server not to include created document in response data
        $NoContentOnResponse,

        [Parameter()]
        [int]
            #Degree of paralelism
        $BatchSize = 1,

        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($context.Endpoint)/colls/$collection/docs"
        $outstandingRequests=@()
    }

    process
    {
        if($PSCmdlet.ParameterSetName -eq 'DocumentObject')
        {
            $Document = $DocumentObject | ConvertTo-Json -Depth 99 -Compress
            #when in pipeline in PS5.1, parameter retains value across invocations
            $PartitionKey = @()
            foreach($attribute in $PartitionKeyAttribute)
            {
                $PartitionKey+=$DocumentObject."$attribute"
            }
        }

        $rq = Get-CosmosRequest `
            -PartitionKey $partitionKey `
            -Type Document `
            -Context $Context `
            -Collection $Collection `
            -Upsert:$IsUpsert
        
        $rq.Method = [System.Net.Http.HttpMethod]::Post
        $rq.Uri = new-object System.Uri($url)
        $rq.Payload = $Document
        $rq.ETag = $ETag
        $rq.PriorityLevel = $Priority
        $rq.NoContentOnResponse = $NoContentOnResponse.IsPresent
        $rq.ContentType = 'application/json'

        $outstandingRequests+=SendRequestInternal -rq $rq -Context $Context
        if($outstandingRequests.Count -ge $batchSize)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
            $outstandingRequests=@()
        }
    }
    end
    {
        if($outstandingRequests.Count -gt 0)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
        }
    }
}
function New-CosmosUpdateOperation
{
<#
.SYNOPSIS
    Constructs document update description

.DESCRIPTION
    Constructs document update description. Used together with Update-CosmosDocument command.
    
.OUTPUTS
    Document update descriptor

.EXAMPLE
    $Updates = @()
    $Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -value 'This is new data for propery content'
    $Updates += New-CosmosUpdateOperation -Operation Add -TargetPath '/arrData/-' -value 'New value to be appended to the end of array'
    Update-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs' -Updates $Updates

    Description
    -----------
    This command replaces field 'content' and adds value to array field 'arrData' in root of the document with ID '123' and partition key 'test-docs' in collection 'docs'
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('Add','Set','Replace','Remove','Increment')]
        [string]
            #Type of update operation to perform
        $Operation,

        [Parameter(Mandatory)]
        [string]
            #Path to field to be updated
            # /path/path/fieldName format
        $TargetPath,

        [Parameter()]
            #value to be used by operation
        $Value
    )
    begin
    {
        $ops = @{
            Add = 'add'
            Set = 'set'
            Remove = 'remove'
            Replace = 'replace'
            Increment = 'incr'
        }
    }
    process
    {
        [PSCustomObject]@{
            PSTypeName = 'CosmosLite.UpdateOperation'
            op = $ops[$Operation]
            path = $TargetPath
            value = $Value
        }
    }
}
function Remove-CosmosDocument
{
<#
.SYNOPSIS
    Removes document from collection

.DESCRIPTION
    Removes document from collection.
    Command supports parallel processing.

.OUTPUTS
    Response describing result of operation

.EXAMPLE
    Remove-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs'

    Description
    -----------
    This command creates new document with id = '123' and partition key 'test-docs' collection 'docs', replacing potentially existing document with same id and partition key
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'RawPayload')]
        [string]
            #Id of the document
        $Id,

        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string[]]
            #Partition key value of the document
        $PartitionKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #Object representing document to remove
        $DocumentObject,

        [Parameter(Mandatory, ParameterSetName = 'DocumentObject')]
        [string[]]
            #attribute of DocumentObject used as partition key
        $PartitionKeyAttribute,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection that contains the document to be removed
        $Collection,

        [Parameter()]
        [int]
            #Degree of paralelism for pipeline processing
        $BatchSize = 1,

        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($context.Endpoint)/colls/$collection/docs"
        $outstandingRequests=@()
    }

    process
    {
        if($PSCmdlet.ParameterSetName -eq 'DocumentObject')
        {
            $Id = $DocumentObject.id
            $PartitionKey = @()
            foreach($attribute in $PartitionKeyAttribute)
            {
                $PartitionKey+=$DocumentObject."$attribute"
            }
        }
        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Context $Context -Collection $Collection
        $rq.Method = [System.Net.Http.HttpMethod]::Delete
        $rq.Uri = new-object System.Uri("$url/$id")

        $outstandingRequests+=SendRequestInternal -rq $rq -Context $Context
        if($outstandingRequests.Count -ge $batchSize)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
            $outstandingRequests=@()
        }
    }
    end
    {
        if($outstandingRequests.Count -gt 0)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
        }
    }
}
function Set-CosmosDocument
{
<#
.SYNOPSIS
    Replaces document with new document

.DESCRIPTION
    Replaces document data completely with new data. Document must exist for oepration to succeed.
    When ETag parameter is specified, document is updated only if etag on server version of document is different.
    Command supports parallel processing.
    
.OUTPUTS
    Response describing result of operation

.EXAMPLE
    $doc = [Ordered]@{
        id = '123'
        pk = 'test-docs'
        content = 'this is content data'
    }
    Set-CosmosDocument -Id '123' Document ($doc | ConvertTo-Json) -PartitionKey 'test-docs' -Collection 'docs'

    Description
    -----------
    This command replaces entire document with ID '123' and partition key 'test-docs' in collection 'docs' with new content
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string]
            #Id of the document to be replaced
        $Id,

        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string]
            #new document data
        $Document,

        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string[]]
            #Partition key of document to be replaced
        $PartitionKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #Object representing document to create
            #Command performs JSON serialization via ConvertTo-Json -Depth 99
        $DocumentObject,

        [Parameter(Mandatory, ParameterSetName = 'DocumentObject')]
        [string[]]
            #attribute of DocumentObject used as partition key
        $PartitionKeyAttribute,
        
        [Parameter(Mandatory)]
        [string]
            #Name of collection containing the document
        $Collection,

        [switch]
            #asks server not to include replaced document in response data
        $NoContentOnResponse,
        
        [Parameter()]
        [string]
            #ETag to check. Document is updated only if server version of document has the same Etag
        $Etag,

        [Parameter()]
        [int]
            #Degree of paralelism
        $BatchSize = 1,

        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($Context.Endpoint)/colls/$collection/docs"
        $outstandingRequests=@()
    }

    process
    {
        if($PSCmdlet.ParameterSetName -eq 'DocumentObject')
        {
            #to change document Id, you cannot use DocumentObject parameter set
            $Id = $DocumentObject.id
            #when in pipeline in PS5.1, parameter retains value across invocations
            $PartitionKey = @()

            foreach($attribute in $PartitionKeyAttribute)
            {
                $PartitionKey+=$DocumentObject."$attribute"
            }
            $Document = $DocumentObject | ConvertTo-Json -Depth 99 -Compress
        }

        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Type Document -Context $Context -Collection $Collection
        $rq.Method = [System.Net.Http.HttpMethod]::Put
        $rq.Uri = new-object System.Uri("$url/$id")
        $rq.Payload = $Document
        $rq.ETag = $ETag
        $rq.NoContentOnResponse = $NoContentOnResponse.IsPresent
        $rq.ContentType = 'application/json'

        $outstandingRequests+=SendRequestInternal -rq $rq -Context $Context
        if($outstandingRequests.Count -ge $batchSize)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
            $outstandingRequests=@()
        }
    }
    end
    {
        if($outstandingRequests.Count -gt 0)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
        }
    }
}
function Set-CosmosRetryCount
{
<#
.SYNOPSIS
    Sets up maximum number of retries when requests are throttled

.DESCRIPTION
    When requests are throttled (server return http 429 code), ruuntime retries the operation for # of times specified here. Default number of retries is 10.
    Waiting time between operations is specified by server together with http 429 response
    
.OUTPUTS
    No output

.EXAMPLE
    Set-CosmosRetryCount -RetryCount 20

    Description
    -----------
    This command sets maximus retries for throttled requests to 20
#>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [int]
            #Number of retries
        $RetryCount,
        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    process
    {
        $Context.RetryCount = $RetryCount
    }
}
function Update-CosmosDocument
{
<#
.SYNOPSIS
    Updates content of the document

.DESCRIPTION
    Updates document data according to update operations provided.
    This command uses Cosmos DB Partial document update API to perform changes on server side without the need to download the document to client, modify it on client side and upload back to server
    Command supports parallel processing.

.OUTPUTS
    Response describing result of operation

.EXAMPLE
    $DocUpdate = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'test-docs'
    $DocUpdate.Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -value 'This is new data for property content'
    Update-CosmosDocument -UpdateObject $DocUpdate -Collection 'docs'

    Description
    -----------
    This command replaces field 'content' in root of the document with ID '123' and partition key 'test-docs' in collection 'docs' with new value
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('CosmosLite.Update')]
            #Object representing document update specification produced by New-CosmosDocumentUpdate
            #and containing collection od up to 10 updates produced by New-CosmosUpdateOperation
        $UpdateObject,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection containing updated document
        $Collection,

        [switch]
            #asks server not to include updated document in response data
        $NoContentOnResponse,

        [Parameter()]
        [int]
            #Degree of paralelism for pipeline processing
        $BatchSize = 1,
        
        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($Context.Endpoint)/colls/$collection/docs"
        $outstandingRequests=@()
    }

    process
    {
        $rq = Get-CosmosRequest -PartitionKey $UpdateObject.PartitionKey -Type Document -Context $Context -Collection $Collection
        #PS5.1 does not suppoort Patch method
        $rq.Method = [System.Net.Http.HttpMethod]::new('PATCH')
        $rq.Uri = new-object System.Uri("$url/$($UpdateObject.Id)")
        $rq.NoContentOnResponse = $NoContentOnResponse.IsPresent
        $patches = @{
            operations = $UpdateObject.Updates
        }
        if(-not [string]::IsNullOrWhiteSpace($UpdateObject.Condition))
        {
            $patches['condition'] = $UpdateObject.Condition
        }
        $rq.Payload =  $patches | ConvertTo-Json -Depth 99 -Compress
        $rq.ContentType = 'application/json_patch+json'

        $outstandingRequests+=SendRequestInternal -rq $rq -Context $Context

        if($outstandingRequests.Count -ge $batchSize)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
            $outstandingRequests=@()
        }
    }
    end
    {
        if($outstandingRequests.Count -gt 0)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
        }
    }
}
#endregion Public

#region Internal
function Get-CosmosRequest
{
    param(
        [Switch]$Upsert,
        [Parameter()]
        [NUllable[UInt32]]$MaxItems,
        [Parameter()]
        [string]$Continuation,
        [Parameter()]
        [string[]]$PartitionKey,
        [Parameter()]
        [string[]]$PartitionKeyRangeId,
        [Parameter(Mandatory)]
        [string]$Collection,
        [Parameter()]
        [ValidateSet('Query','SpCall','Document','Other')]
        [string]$Type = 'Other',
        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]$Context = $script:Configuration
    )

    process
    {
        $token = Get-CosmosAccessToken -Context $context
        
        [PSCustomObject]@{
            AccessToken = $token.AccessToken
            Type = $Type
            MaxItems = $MaxItems
            Continuation = $Continuation
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
            NoContentOnResponse = $false
            Version = $Context.ApiVersion
        }
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
        $retVal.Headers.Add('x-ms-version', $rq.Version)
        $retVal.RequestUri = $rq.Uri
        $retVal.Method = $rq.Method
        if(-not [string]::IsNullOrEmpty($rq.Session))
        {
            #Write-Verbose "Setting 'x-ms-session-token' to $($rq.Session)"
            $retVal.Headers.Add('x-ms-session-token', $rq.Session)
        }

        switch($rq.Type)
        {
            'Query' {
                $retVal.Content = new-object System.Net.Http.StringContent($rq.payload,$null ,$rq.ContentType)
                $retVal.Content.Headers.ContentType.CharSet=[string]::Empty
                #Write-Verbose "Setting 'x-ms-documentdb-isquery' to True"
                $retVal.Headers.Add('x-ms-documentdb-isquery', 'True')

                #avoid RequestTooLarge error because of continuation token size
                $retVal.Headers.Add('x-ms-documentdb-responsecontinuationtokenlimitinkb', '8')

                if($null -ne $rq.MaxItems)
                {
                    #Write-Verbose "Setting 'x-ms-max-item-count' to $($rq.MaxItems)"
                    $retVal.Headers.Add('x-ms-max-item-count', $rq.MaxItems)
                }
                if($rq.PartitionKey.Count -eq 0)
                {
                    #Write-Verbose "Setting 'x-ms-documentdb-query-enablecrosspartition' to True"
                    $retVal.Headers.Add('x-ms-documentdb-query-enablecrosspartition', 'True')
                }
                if(-not [string]::IsNullOrEmpty($rq.Continuation))
                {
                    #Write-Verbose "Setting 'x-ms-continuation' to $($rq.Continuation)"
                    $retVal.Headers.Add('x-ms-continuation', $rq.Continuation)
                }
                if(-not [string]::IsNullOrEmpty($rq.PartitionKeyRangeId))
                {
                    #Write-Verbose "Setting 'x-ms-documentdb-partitionkeyrangeid' to $($rq.PartitionKeyRangeId)"
                    $retVal.Headers.Add('x-ms-documentdb-partitionkeyrangeid', $rq.PartitionKeyRangeId)
                }
                break;
            }
            {$_ -in 'SpCall','Document'} {
                $retVal.Content = new-object System.Net.Http.StringContent($rq.payload,$null ,$rq.ContentType)
                $retVal.Content.Headers.ContentType.CharSet=[string]::Empty
                if(-not [string]::IsNullOrEmpty($rq.ETag))
                {
                    #etag is expected to be double-quoted by http specs
                    if($rq.Etag[0] -ne '"') {$headerValue = "`"$($rq.ETag)`""} else {$headerValue = $rq.ETag}
                    $retVal.Headers.IfMatch.Add($headerValue)
                }
                if($rq.NoContentOnResponse)
                {
                    $retVal.Headers.Add('Prefer', 'return=minimal')
                }
                break
            }
            default {
                if(-not [string]::IsNullOrEmpty($rq.ETag))
                {
                    #etag is expected to be double-quoted by http specs
                    if($rq.Etag[0] -ne '"') {$headerValue = "`"$($rq.ETag)`""} else {$headerValue = $rq.ETag}
                    $retVal.Headers.IfNoneMatch.Add($headerValue)
                }
                if(-not [string]::IsNullOrEmpty($rq.PriorityLevel))
                {
                    #Write-Verbose "Setting 'x-ms-cosmos-priority-level' to $($rq.x-ms-cosmos-priority-level)"
                    $retVal.Headers.Add('x-ms-cosmos-priority-level', $rq.PriorityLevel)
                }

                break;
            }
        }
        if($rq.Upsert)
        {
            #Write-Verbose "Setting 'x-ms-documentdb-is-upsert' to True"
            $retVal.Headers.Add('x-ms-documentdb-is-upsert', 'True');
        }
        if($rq.PartitionKey.Count -gt 0)
        {
            $headerValue = $rq.PartitionKey | ConvertTo-Json -Compress
            if($headerValue[0] -ne '[') {$headerValue = "[$headerValue]"}
            $retVal.Headers.Add('x-ms-documentdb-partitionkey', $headerValue)
        }

        $retVal
    }
}
function ProcessCosmosResponseInternal
{
    [CmdletBinding()]
    param (

        [Parameter(Mandatory)]
        [PSCustomObject]
        $ResponseContext,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context
    )

    begin
    {
        $provider =  [System.Globalization.CultureInfo]::CreateSpecificCulture("en-US")
    }
    process
    {
        #get response associated with request
        $rsp = $ResponseContext.HttpTask.Result
        #get collection request was using
        $collection = $ResponseContext.CosmosLiteRequest.Collection
        #create return structure
        $retVal=[ordered]@{
            PSTypeName = "CosmosLite.Response"
            IsSuccess = $false
            HttpCode = 0
            Charge = -1
            Data = $null
            Continuation = $null
        }

        $retVal['IsSuccess'] = $rsp.IsSuccessStatusCode
        $retVal['HttpCode'] = $rsp.StatusCode
        $val = $null
        #retrieve important headers
        if($rsp.Headers.TryGetValues('x-ms-request-charge', [ref]$val)) {
            #we do not want fractions of RU - round to whole number
            $retVal['Charge'] = [int][double]::Parse($val[0],$provider)
        }
        
        if($rsp.Headers.TryGetValues('x-ms-continuation', [ref]$val)) {
            $retVal['Continuation'] = $val[0]
        }

        #store session token for container
        if($rsp.Headers.TryGetValues('x-ms-session-token', [ref]$val)) {
            $Context.Session[$Collection] = $val[0]
        }
        #get raw response headers
        if($Context.CollectResponseHeaders)
        {
            $retVal['Headers']=@{}
            $rsp.Headers.ForEach{
                $retVal['Headers']["$($_.Key)"] = $_.Value
            }
        }
        #retrieve response data
        if($null -ne $rsp.Content)
        {
            $s = $rsp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            try {
                $retVal['Data'] = ($s | ConvertFrom-Json -ErrorAction Stop)
            }
            catch {
                throw new-object System.FormatException("InvalidJsonPayloadReceived. Error: $($_.Exception.Message)`nPayload: $s")
            }
        }
        if(-not $retVal['IsSuccess'])
        {
            $ex = [CosmosLiteException]::new($retVal['Data'].code, $retVal['Data'].message, $ResponseContext.CosmosLiteRequest)
            switch($ErrorActionPreference)
            {
                'Stop' {
                    throw $ex
                    break;
                }
                'Continue' {
                    Write-Error -Exception $ex
                    break;
                }
            }
        }
        [PSCustomObject]$retVal
    }
}
function ProcessRequestBatchInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Batch,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context
    )

    begin
    {
        $outstandingRequests=@()
        $batch | ForEach-Object{$outstandingRequests+=$_}
        $maxRetries = $Context.RetryCount
    }
    process
    {
        do
        {
            #we have enough HttpRequests sent - wait for completion
            [System.Threading.Tasks.Task]::WaitAll($outstandingRequests.HttpTask)
            
            #process reponses
            #bag for requests to retry
            $requestsToRetry=@()
            #total time to wait in case of throttled
            $waitTime=0
            foreach($request in $outstandingRequests)
            {
                #dispose related httpRequestMessage
                $request.HttpRequest.Dispose()

                #get httpResponseMessage
                $httpResponse = $request.HttpTask.Result
                #and associated CosmosLiteRequest
                $cosmosRequest = $request.CosmosLiteRequest
                if($httpResponse.IsSuccessStatusCode) {
                    #successful - process response
                    ProcessCosmosResponseInternal -ResponseContext $request -Context $Context
                }
                else
                {
                    if($httpResponse.StatusCode -eq 429 -and $maxRetries -gt 0)
                    {
                        #get waitTime
                        $val = $null
                        if($httpResponse.Headers.TryGetValues('x-ms-retry-after-ms', [ref]$val)) {$wait = [long]$val[0]} else {$wait=1000}
                        #we wait for longest time returned by all 429 responses
                        if($waitTime -lt $wait) {$waitTime = $wait}
                        $requestsToRetry+=$cosmosRequest
                    }
                    else {
                        #failed or maxRetries exhausted
                        ProcessCosmosResponseInternal -ResponseContext $request -Context $Context
                    }
                }
                #dispose httpResponseMessage
                $httpResponse.Dispose()
            }

            #retry throttled requests
            if($requestsToRetry.Count -gt 0)
            {
                $outstandingRequests=@()
                $maxRetries--
                Write-Verbose "Throttled`tRequestsToRetry`t$($requestsToRetry.Count)`tWaitTime`t$waitTime`tRetriesRemaining`t$maxRetries"
                Start-Sleep -Milliseconds $waitTime
                foreach($cosmosRequest in $requestsToRetry)
                {
                    $outstandingRequests+=SendRequestInternal -rq $cosmosRequest -Context $Context
                }
            }
            else {
                #no requests to retry
                break
            }
        }while($true)
    }
}
function SendRequestInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$rq,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context
    )

    process
    {
        $httpRequest = GetCosmosRequestInternal -rq $rq
        #pair our request to task for possible retry and batch executing tasks
        [PSCustomObject]@{
            CosmosLiteRequest = $rq
            HttpRequest = $httpRequest
            HttpTask = $script:httpClient.SendAsync($httpRequest)
        }
    }
}
#endregion Internal

