#region Public commands
function Assert-CosmosResult
{
<#
.SYNOPSIS
    Validates a CosmosLite response and throws on failure.

.DESCRIPTION
    Checks the IsSuccess flag on an input CosmosLite response object.
    When the operation succeeded, the original response object is passed through.
    When the operation failed, the command throws a CosmosLiteException built from the response error payload.

.OUTPUTS
    CosmosLite response object when successful.

.NOTES
    The exception thrown by this command does not include request context.
    To preserve request details, use -ErrorAction Stop on the original command and handle that exception directly.

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myCosmosDb -TenantId mydomain.com -AuthMode Interactive
    Get-CosmosDocument -Collection 'myCollection' -Id '1' -PartitionKey 'documents' | Assert-CosmosResult

    Description
    -----------
    Retrieves a document and throws immediately if the request failed.

#>
param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        $CosmosResult
    )

    process
    {
        if($CosmosResult.IsSuccess)
        {
            $CosmosResult
        }
        else 
        {
            $ex = [CosmosLiteException]::new($CosmosResult.Data.code, $CosmosResult.Data.message)
            throw $ex
        }
    }
}
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
    Retrieves an access token for the current CosmosLite connection.

.DESCRIPTION
    Acquires a Microsoft Entra ID token for the configured Cosmos DB account.
    This command is primarily useful for troubleshooting or diagnostics.
    Most commands acquire and refresh tokens automatically when needed.

.OUTPUTS
    Microsoft.Identity.Client.AuthenticationResult.

.NOTES
    See https://learn.microsoft.com/en-us/dotnet/api/microsoft.identity.client.authenticationresult

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -TenantId mydomain.com | Get-CosmosAccessToken

    Description
    -----------
    Creates a connection and returns the access token for that context.
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
    Returns partition key ranges for a collection.

.DESCRIPTION
    Retrieves partition key range metadata for the specified collection.
    This is useful for advanced query scenarios, such as manual fan-out across ranges.

.OUTPUTS
    CosmosLite response object containing partition key range metadata.

.EXAMPLE
    $rsp = Get-CosmosCollectionPartitionKeyRanges -Collection veryLargeCollection
    foreach($id in $rsp.data.PartitionKeyRanges.Id) {
        Invoke-CosmosQuery -Query 'select * from c' -collection veryLargeCollection -PartitionKeyRangeId $id -AutoContinue
    }

    Description
    -----------
    Demonstrates using explicit partition key ranges for large cross-partition query workloads.
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
        $outstandingRequests = [System.Collections.Generic.List[object]]::new()
    }

    process
    {
        $rq = Get-CosmosRequest -Context $Context -Collection $Collection
        $rq.Uri = new-object System.Uri("$url")
        $rq.Method = [System.Net.Http.HttpMethod]::Get

        $outstandingRequests.Add((SendRequestInternal -rq $rq -Context $Context))
    }
    end
    {
        InvokeCosmosWindowInternal -InFlight $outstandingRequests -Context $Context
    }
}
function Get-CosmosConnection
{
<#
.SYNOPSIS
    Returns the currently cached CosmosLite connection.

.DESCRIPTION
    Returns the most recently created CosmosLite connection object stored in module scope.
    Use this when you want to inspect or reuse the active context without storing it in a separate variable.

.OUTPUTS
    CosmosLite.Connection object.

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
    Retrieves a document by id and partition key.

.DESCRIPTION
    Reads one or more documents from the specified collection.
    Supports pipeline input and batched parallel request processing via -BatchSize.

.OUTPUTS
    CosmosLite response object containing the requested document.

.EXAMPLE
    $rsp = Get-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs'
    $rsp.data

    Description
    -----------
    Retrieves document 123 from collection docs in partition test-docs.
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
        #Custom type to serialize documents returned by query to
        #When specified, custom serializer is used and returns objects of specified type
        #When not specified, ConvertFrom-Json command is used that returns documents as PSCustomObject
        [Type]$TargetType,

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
        $outstandingRequests = [System.Collections.Generic.List[object]]::new()
    }

    process
    {
        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Context $Context -Collection $Collection -TargetType $TargetType
        $rq.Method = [System.Net.Http.HttpMethod]::Get
        $rq.Uri = new-object System.Uri("$url/$id")
        $rq.ETag = $ETag
        $rq.PriorityLevel = $Priority

        InvokeCosmosWindowInternal -rq $rq -InFlight $outstandingRequests -BatchSize $batchSize -Context $Context
    }
    end
    {
        InvokeCosmosWindowInternal -InFlight $outstandingRequests -Context $Context
    }
}
function Invoke-CosmosQuery
{
<#
.SYNOPSIS
    Executes a SQL query against a Cosmos DB collection.

.DESCRIPTION
    Executes a query and returns matching documents.
    Results can be paged. When more data is available, the response contains a continuation token.
    Use -ContinuationToken to request the next page, or use -AutoContinue to iterate automatically.
    
.OUTPUTS
    CosmosLite response object for each query page.

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
    Performs a parameterized cross-partition query and manually follows continuation tokens.

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myCosmosDb -UseManagedIdentity -CollectResponseHeaders
    $query = "select * from c where c.itemType = @itemType"
    $queryParams = @{
        '@itemType' = 'person'
    }
    $rsp = Invoke-CosmosQuery -Query $query -QueryParameters $queryParams -Collection 'docs' -MaxItems 10 -AutoContinue -PopulateMetrics
    if($rsp.IsSuccess)
    {
        $rsp.data.Documents
        "Total RU consumption: $($rsp | Measure-Object -Property Charge -Sum | select -ExpandProperty Sum)"
    }

    Description
    -----------
    Performs a parameterized query and automatically iterates pages and partition ranges with -AutoContinue.
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
            #Query string
        $Query,

        [Parameter()]
        [Alias('Parameters')]
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
            #Custom type to serialize documents returned by query to
            #When specified, custom serializer is used and returns objects of specified type
            #When not specified, ConvertFrom-Json command is used that returns documents as PSCustomObject
        [Type]$TargetType,

        [Parameter()]
        [string]
            #Continuation token. Used to ask for next page of results
        $ContinuationToken,

        [switch]
            #Populates query metrics in response object
        $PopulateMetrics,

        [switch]
            #when response contains continuation token, returns the response and automatically sends new request with continuation token
            #on large collection with multiple partitions, it also iterates over all partition key ranges and queries them one by one
            #this simplifies getting all data from query for large datasets
        $AutoContinue,

        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $uri = new-object System.Uri("$($context.Endpoint)/colls/$collection/docs")

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
        $queryRequestPayload = ($QueryDefinition | ConvertTo-Json -Depth 99 -Compress)
    }

    process
    {
        if($null -ne $TargetType)
        {
            #create custom type for response
            $expression = "class QueryResponse {
                [string]`$_rid
                [int]`$_count
                [System.Collections.Generic.List[$($targetType.Name)]]`$Documents
                }"
            Invoke-Expression $expression
            $Type = [QueryResponse]
        }
        else {$Type=$null}
        if($AutoContinue -and $null -eq $PartitionKeyRangeId)
        {
            Write-Verbose "AutoContinue specified but PartitionKeyRangeId not specified. Retrieving all partition key ranges for collection $Collection"
            #get all partition key ranges for the collection
            $rsp = Get-CosmosCollectionPartitionKeyRanges -Collection $Collection -Context $Context
            if(-not $rsp.IsSuccess)
            {
                Write-Warning "Failed to retrieve partition key ranges for collection $Collection. Error: $($rsp.Data)"
                return
            }
            $partitionKeyRangeIds = $rsp.data.PartitionKeyRanges.Id
        }
        else {
            $partitionKeyRangeIds = @($PartitionKeyRangeId)
        }

        foreach($id in $partitionKeyRangeIds)
        {
            if($null -ne $id) { Write-Verbose "Querying PartitionKeyRangeId $id" }
            do
            {
                $rq = Get-CosmosRequest `
                    -PartitionKey $partitionKey `
                    -PartitionKeyRangeId $id `
                    -Type Query `
                    -MaxItems $MaxItems `
                    -Continuation $ContinuationToken `
                    -PopulateMetrics:$PopulateMetrics `
                    -Context $Context `
                    -Collection $Collection `
                    -TargetType $Type

                $rq.Method = [System.Net.Http.HttpMethod]::Post
                $rq.Uri = $uri
                $rq.Payload = $queryRequestPayload
                $rq.ContentType = 'application/query+json'

                $inFlight = [System.Collections.Generic.List[object]]::new()
                $inFlight.Add((SendRequestInternal -rq $rq -Context $Context))
                $response = InvokeCosmosWindowInternal -InFlight $inFlight -Context $Context
                $response
                #auto-continue if requested
                if(-not $AutoContinue) {break;}
                $ContinuationToken = $response.Continuation
                if([string]::IsNullOrEmpty($ContinuationToken)) {break;}
                Write-Verbose "Continuing query with continuation token: $ContinuationToken"
            }while($true)
        }
    }
}
function Invoke-CosmosStoredProcedure
{
<#
.SYNOPSIS
    Executes a stored procedure.

.DESCRIPTION
    Calls a stored procedure in the specified collection and partition.
    Supports pipeline input and batched parallel request processing.
    Paging behavior for stored procedures is implemented by the stored procedure itself. If paging is needed,
    the procedure must accept, propagate, and return continuation state explicitly.
    
.OUTPUTS
    CosmosLite response object containing stored procedure output.

.EXAMPLE
    $params = @('123', 'test')
    $rsp = Invoke-CosmosStoredProcedure -Name testSP -Parameters ($params | ConvertTo-Json) -Collection 'docs' -PartitionKey 'test-docs'
    $rsp

    Description
    -----------
    Executes a stored procedure with two input parameters and returns its response.
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
        $outstandingRequests = [System.Collections.Generic.List[object]]::new()
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

        InvokeCosmosWindowInternal -rq $rq -InFlight $outstandingRequests -BatchSize $batchSize -Context $Context
    }
    end
    {
        InvokeCosmosWindowInternal -InFlight $outstandingRequests -Context $Context
    }
}
function New-CosmosDocument
{
<#
.SYNOPSIS
    Creates a new document in a collection.

.DESCRIPTION
    Inserts a document into the target collection.
    When -IsUpsert is specified, an existing document with the same id and partition key is replaced.
    Supports pipeline input and batched parallel request processing.

.OUTPUTS
    CosmosLite response object.

.EXAMPLE
    $doc = [Ordered]@{
        id = '123'
        pk = 'test-docs'
        content = 'this is content data'
    }
    New-CosmosDocument -Document ($doc | ConvertTo-Json) -PartitionKey 'test-docs' -Collection 'docs' -IsUpsert

    Description
    -----------
    Upserts a document with id 123 in collection docs and partition test-docs.
#>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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
        $outstandingRequests = [System.Collections.Generic.List[object]]::new()
    }

    process
    {
        $documentId = $null
        if($PSCmdlet.ParameterSetName -eq 'DocumentObject')
        {
            $Document = $DocumentObject | ConvertTo-Json -Depth 99 -Compress
            $documentId = $DocumentObject.id
            #when in pipeline in PS5.1, parameter retains value across invocations
            $PartitionKey = @()
            foreach($attribute in $PartitionKeyAttribute)
            {
                $PartitionKey+=$DocumentObject."$attribute"
            }
        }

        $target = if([string]::IsNullOrEmpty($documentId)) { "$Collection/<unknown-id>" } else { "$Collection/$documentId" }
        $operation = if($IsUpsert.IsPresent) { 'Upsert Cosmos document' } else { 'Create Cosmos document' }

        if($PSCmdlet.ShouldProcess($target, $operation))
        {
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

            InvokeCosmosWindowInternal -rq $rq -InFlight $outstandingRequests -BatchSize $batchSize -Context $Context
        }
    }
    end
    {
        InvokeCosmosWindowInternal -InFlight $outstandingRequests -Context $Context
    }
}
function New-CosmosDocumentUpdate
{
<#
.SYNOPSIS
    Creates a document update descriptor for partial updates.

.DESCRIPTION
    Builds a CosmosLite.Update object used by Update-CosmosDocument.
    Combine it with one or more operations created by New-CosmosUpdateOperation.

.OUTPUTS
    CosmosLite.Update object.

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
    Builds update payloads and increments quantity by 50 for matching documents.
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
function New-CosmosUpdateOperation
{
<#
.SYNOPSIS
    Creates a single partial update operation.

.DESCRIPTION
    Builds one CosmosLite.UpdateOperation entry for use in a CosmosLite.Update object.
    Use this command with New-CosmosDocumentUpdate and Update-CosmosDocument.
    
.OUTPUTS
    CosmosLite.UpdateOperation object.

.EXAMPLE
    $Updates = @()
    $Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -value 'This is new data for propery content'
    $Updates += New-CosmosUpdateOperation -Operation Add -TargetPath '/arrData/-' -value 'New value to be appended to the end of array'
    Update-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs' -Updates $Updates

    Description
    -----------
    Creates multiple patch operations and applies them to a document.
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('Add','Set','Replace','Remove','Increment','Move')]
        [string]
            #Type of update operation to perform
        $Operation,

        [Parameter(Mandatory)]
        [string]
            #Path to field to be updated
            # /path/path/fieldName format
        $TargetPath,

        [Parameter(ParameterSetName = 'NonMove')]
            #value to be used by operation
        $Value,
        
        [Parameter(Mandatory, ParameterSetName = 'Move')]
            #source path for move operation
        [string]$From
    )
    begin
    {
        $ops = @{
            Add = 'add'
            Set = 'set'
            Remove = 'remove'
            Replace = 'replace'
            Increment = 'incr'
            Move = 'move'
        }
    }
    process
    {
        $retVal = @{
            PSTypeName = 'CosmosLite.UpdateOperation'
            op = $ops[$Operation]
            path = $TargetPath
        }
        switch($PSCmdlet.ParameterSetName)
        {
            'Move' {
                $retVal.from = $From
                break;
            }
            default {
                switch($Operation)
                {
                    'Remove' {
                        #nothing more to do for remove operation
                        break;
                    }
                    default {
                        $retVal.value = $Value
                        break;
                    }
                }
            }
        }
        [PSCustomObject]$retVal
    }
}
function Remove-CosmosDocument
{
<#
.SYNOPSIS
    Deletes a document from a collection.

.DESCRIPTION
    Removes one or more documents identified by id and partition key.
    Supports pipeline input and batched parallel request processing.
    Supports ShouldProcess (-WhatIf and -Confirm).

.OUTPUTS
    CosmosLite response object.

.EXAMPLE
    Remove-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs'

    Description
    -----------
    Deletes document 123 from collection docs in partition test-docs.
#>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
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
        $outstandingRequests = [System.Collections.Generic.List[object]]::new()
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
        if($PSCmdlet.ShouldProcess("$Collection/$Id", 'Remove Cosmos document'))
        {
            $rq = Get-CosmosRequest -PartitionKey $partitionKey -Context $Context -Collection $Collection
            $rq.Method = [System.Net.Http.HttpMethod]::Delete
            $rq.Uri = new-object System.Uri("$url/$id")

            InvokeCosmosWindowInternal -rq $rq -InFlight $outstandingRequests -BatchSize $batchSize -Context $Context
        }
        else
        {
            Write-Verbose "Skipping document $Collection/$Id"
        }
    }
    end
    {
        InvokeCosmosWindowInternal -InFlight $outstandingRequests -Context $Context
    }
}
function Set-CosmosDocument
{
<#
.SYNOPSIS
    Replaces an existing document.

.DESCRIPTION
    Replaces document content with the supplied payload.
    The document must exist.
    When -Etag is supplied, replacement is conditional on the current server ETag.
    Supports pipeline input and batched parallel request processing.
    
.OUTPUTS
    CosmosLite response object.

.EXAMPLE
    $doc = [Ordered]@{
        id = '123'
        pk = 'test-docs'
        content = 'this is content data'
    }
    Set-CosmosDocument -Id '123' Document ($doc | ConvertTo-Json) -PartitionKey 'test-docs' -Collection 'docs'

    Description
    -----------
    Replaces the full document body for document 123 in collection docs.
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
        $outstandingRequests = [System.Collections.Generic.List[object]]::new()
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

        InvokeCosmosWindowInternal -rq $rq -InFlight $outstandingRequests -BatchSize $batchSize -Context $Context
    }
    end
    {
        InvokeCosmosWindowInternal -InFlight $outstandingRequests -Context $Context
    }
}
function Set-CosmosRetryCount
{
<#
.SYNOPSIS
    Sets the retry count for throttled requests.

.DESCRIPTION
    Updates the maximum retry attempts used when Cosmos DB responds with HTTP 429 (Too Many Requests).
    Retry delay is taken from server-provided headers.
    
.OUTPUTS
    None.

.EXAMPLE
    Set-CosmosRetryCount -RetryCount 20

    Description
    -----------
    Sets the throttling retry limit to 20 for the active context.
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
    Applies partial updates to a document.

.DESCRIPTION
    Applies patch operations to documents by using the Cosmos DB partial document update API.
    This avoids downloading the full document, editing client-side, and replacing the complete payload.
    Supports pipeline input, batched parallel processing, and ShouldProcess (-WhatIf and -Confirm).

.OUTPUTS
    CosmosLite response object.

.EXAMPLE
    $DocUpdate = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'test-docs'
    $DocUpdate.Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -value 'This is new data for property content'
    Update-CosmosDocument -UpdateObject $DocUpdate -Collection 'docs'

    Description
    -----------
    Applies a single patch operation to update the content property of a document.
#>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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
        $outstandingRequests = [System.Collections.Generic.List[object]]::new()
    }

    process
    {
        if($PSCmdlet.ShouldProcess("$Collection/$($UpdateObject.Id)", 'Update Cosmos document'))
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

            InvokeCosmosWindowInternal -rq $rq -InFlight $outstandingRequests -BatchSize $batchSize -Context $Context
        }
    }
    end
    {
        InvokeCosmosWindowInternal -InFlight $outstandingRequests -Context $Context
    }
}
#endregion Public commands
#region Internal commands
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
function Get-CosmosRequest
{
    param(
        [Switch]$Upsert,
        [Parameter()]
        [NUllable[UInt32]]$MaxItems,
        [Parameter()]
        [Type]$TargetType,
        [Parameter()]
        [string]$Continuation,
        [Parameter()]
        [int]$MaxContinuationTokenSizeInKb = 6,
        [Parameter()]
        [string[]]$PartitionKey,
        [Parameter()]
        [string[]]$PartitionKeyRangeId,
        [Parameter(Mandatory)]
        [string]$Collection,
        [Parameter()]
        [ValidateSet('Query','SpCall','Document','Other')]
        [string]$Type = 'Other',
        [switch]$PopulateMetrics,
        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]$Context = $script:Configuration
    )

    process
    {
        $token = Get-CosmosAccessToken -Context $context
 
        [PSCustomObject]@{
            AccessToken = $token.AccessToken
            Type = $Type
            TargetType = $TargetType
            MaxItems = $MaxItems
            Continuation = $Continuation
            MaxContinuationTokenSizeInKb = $Context.MaxContinuationTokenSizeInKb
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
            PopulateMetrics = $PopulateMetrics
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
                $retVal.Headers.Add('x-ms-documentdb-responsecontinuationtokenlimitinkb', "$($rq.MaxContinuationTokenSizeInKb)")

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
                if($rq.PopulateMetrics)
                {
                    #Write-Verbose "Setting 'x-ms-documentdb-populatequerymetrics' to True"
                    $retVal.Headers.Add('x-ms-documentdb-populatequerymetrics', 'True')
                    $retVal.Headers.Add('x-ms-cosmos-populateindexmetrics', 'True')
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
function GetResponseData
{
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Payload,
        [Parameter()]
        [Type]$TargetType
    )

    process
    {
        if($null -eq $TargetType)
        {
            $Payload | ConvertFrom-Json
        }
        else {
            switch($PSVersionTable.PSEdition)
            {
                'Desktop' 
                {
                    $script:DesktopSerializer.Deserialize($Payload, $TargetType)
                }
                'Core' 
                {
                    [System.Text.Json.JsonSerializer]::Deserialize($Payload, $TargetType, $Script:JsonSerializerOptions)
                }
            }
        }
    }
}
# Maintains a sliding concurrency window for in-flight Cosmos DB HTTP requests.
#
# Submit mode  ($rq provided): starts one HTTP request and blocks until a slot is free
#   (Count < BatchSize), then returns so the caller can process the next pipeline item.
#   Used in process blocks.
#
# Drain mode ($rq omitted): flushes all remaining in-flight requests to completion.
#   Used in end blocks.
function InvokeCosmosWindowInternal
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [PSCustomObject]
            #CosmosLiteRequest to start. Omit (or pass $null) to switch to drain mode.
        $rq = $null,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$InFlight,
        [Parameter()]
        [int]
            #Maximum number of concurrent requests. Only used in submit mode.
        $BatchSize = 1,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context
    )

    process
    {
        $limit = 1
        if ($null -ne $rq)
        {
            [void]$InFlight.Add((SendRequestInternal -rq $rq -Context $Context))
            $limit = $BatchSize
        }
        # Submit mode: loop while window is at capacity  (Count >= BatchSize)
        # Drain  mode: loop while anything remains       (limit = 1  →  Count >= 1)
        while ($InFlight.Count -ge $limit)
        {
            WaitAndProcessOneInternal -InFlight $InFlight -Context $Context
        }
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
                $header = $_
                switch($header.Key)
                {
                    'x-ms-documentdb-query-metrics' {
                        $retVal['Headers']["$($header.Key)"] = $header.Value[0].Split(';')
                        break
                    }
                    'x-ms-cosmos-index-utilization' {
                        $iu = $header.Value[0]
                        $retVal['Headers']["$($header.Key)"] = [system.text.encoding]::UTF8.GetString([Convert]::FromBase64String($iu)) | ConvertFrom-Json
                        break
                    }
                    default {
                        $retVal['Headers']["$($header.Key)"] = $header.Value
                        break
                    }
                }
            }
        }
        #retrieve response data
        if($null -ne $rsp.Content -and $rsp.StatusCode -ne [System.Net.HttpStatusCode]::NoContent)
        {
            #we expect to receive some payload
            $s = $rsp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if(-not [string]::IsNullOrWhiteSpace($s))
            {
                try {
                    $retVal['Data'] = ($s | GetResponseData -TargetType $ResponseContext.CosmosLiteRequest.TargetType  -ErrorAction Stop)
                }
                catch {
                    throw new-object System.FormatException("InvalidJsonPayloadReceived. Error: $($_.Exception.Message)`nPayload: $s")
                }
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
function SendRequestInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$rq,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context,
        [Parameter()]
        [int]
            #Remaining retry attempts for this request. Defaults to Context.RetryCount on first send.
        $RetriesRemaining = -1
    )

    process
    {
        $httpRequest = GetCosmosRequestInternal -rq $rq
        [PSCustomObject]@{
            CosmosLiteRequest  = $rq
            HttpRequest        = $httpRequest
            HttpTask           = $Context.HttpClient.SendAsync($httpRequest)
            RetriesRemaining   = if ($RetriesRemaining -lt 0) { $Context.RetryCount } else { $RetriesRemaining }
        }
    }
}
# Atomic unit: wait for exactly ONE in-flight HTTP task to complete and handle its result.
# Called by InvokeCosmosWindowInternal in both submit and drain modes.
function WaitAndProcessOneInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$InFlight,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context
    )

    process
    {
        $tasks = [System.Threading.Tasks.Task[]]($InFlight | ForEach-Object { $_.HttpTask })
        $idx   = [System.Threading.Tasks.Task]::WaitAny($tasks)
        $completed = $InFlight[$idx]
        [void]$InFlight.RemoveAt($idx)

        $completed.HttpRequest.Dispose()
        $httpResponse = $completed.HttpTask.Result
        try
        {
            if ($httpResponse.IsSuccessStatusCode)
            {
                ProcessCosmosResponseInternal -ResponseContext $completed -Context $Context
            }
            elseif ($httpResponse.StatusCode -eq 429 -and $completed.RetriesRemaining -gt 0)
            {
                $val = $null
                if ($httpResponse.Headers.TryGetValues('x-ms-retry-after-ms', [ref]$val)) { $wait = [long]$val[0] } else { $wait = 1000 }
                $remaining = $completed.RetriesRemaining - 1
                Write-Verbose "Throttled`tWaitTime`t$wait`tRetriesRemaining`t$remaining"
                Start-Sleep -Milliseconds $wait
                [void]$InFlight.Add((SendRequestInternal -rq $completed.CosmosLiteRequest -Context $Context -RetriesRemaining $remaining))
            }
            else
            {
                # Failed response or retries exhausted — surface as error via ProcessCosmosResponseInternal
                ProcessCosmosResponseInternal -ResponseContext $completed -Context $Context
            }
        }
        finally
        {
            $httpResponse.Dispose()
        }
    }
}


#endregion Internal commands
#region Module initialization
if($PSEdition -eq 'Desktop')
{
    add-type -AssemblyName System.Collections
    add-type -AssemblyName system.web
    add-type -AssemblyName System.Web.Extensions
    $script:DesktopSerializer = [System.Web.Script.Serialization.JavaScriptSerializer]::new()
    $script:DesktopSerializer.MaxJsonLength = [int]::MaxValue
    $script:DesktopSerializer.RecursionLimit = 100
}
else {
    add-type -AssemblyName System.Collections
    add-type -AssemblyName System.Text.Json
    $Script:JsonSerializerOptions = [System.Text.Json.JsonSerializerOptions]@{
        PropertyNameCaseInsensitive = $true
        PropertyNamingPolicy = [System.Text.Json.JsonNamingPolicy]::CamelCase
        ReadCommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
        AllowTrailingCommas = $true
        MaxDepth = 100
    }
}
#endregion Module initialization
