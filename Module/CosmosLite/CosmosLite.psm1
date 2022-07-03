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
$thumbprint = 'e827f78a78cf532eb539479d6afe9c7f703173d5'
$appId = '1b69b00f-08f0-4798-9976-af325f7f7526'
$cert = dir Cert:\CurrentUser\My\ | where-object{$_.Thumbprint -eq $thumbprint}
Connect-Cosmos -AccountName dhl-o365-onboarding-uat -Database onboarding -TenantId dhl.com -ClientId $appId -X509Certificate $cert

Description
-----------
This command returns configuration object for working with CosmosDB account myCosmosDbAccount and database myDbInCosmosAccount in tenant mydomain.com, with Application auth flow

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

        [Parameter(Mandatory)]
        [string]
            #Id of tenant where to autenticate the user. Can be tenant id, or any registerd DNS domain
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
        }

        $RequiredScopes = @("https://$accountName`.documents.azure.com/.default")

        if($null -eq $script:AuthFactories) {$script:AuthFactories = @{}}
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
        }

        $script:Configuration
    }
}

#region Authentication

function Get-CosmosAccessToken
{
    <#
.SYNOPSIS
    Retrieves AAD token for authentication with selected CosmosDB

.DESCRIPTION
    Retrieves AAD token for authentication with selected CosmosDB.
    Can be used for debug purposes; module itself gets token as needed, including refreshing the tokens when they expire

.OUTPUTS
    OpentID token as returned by AAD.

.EXAMPLE
Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -TenantId mydomain.com | Get-CosmosAccessToken

Description
-----------
This command retrieves configuration for specified CosmosDB account and database, and retrieves access token for it using well-known clientId of Azure PowerShell

#>

    param
    (
        [Parameter(ValueFromPipeline)]
        [PSCustomObject]
            #Connection configuration object
        $context = $script:Configuration
    )

    process
    {
        if([string]::IsNullOrEmpty($context))
        {
            throw "Call Connect-Cosmos first"
        }

        if($null -eq $script:AuthFactories[$context.AccountName])
        {
            throw "Call Connect-Cosmos first for CosmosDB account = $($context.AccountName)"

        }

        $script:AuthFactories[$context.AccountName].AuthenticateAsync().GetAwaiter().GetResult()
    }
}

#region CosmosLiteDocs
function Get-CosmosDocument
{
<#
.SYNOPSIS
    Retrieves document from the collection

.DESCRIPTION
    Retrieves document from the collection by id and partition key

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
        [string]
            #value of partition key for the document
        $PartitionKey,
        [Parameter(Mandatory)]
        [string]
            #Name of collection conaining the document
        $Collection,
        [Parameter()]
        [PSCustomObject]
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
        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Context $Context
        $rq.Method = [System.Net.Http.HttpMethod]::Get
        $uri = "$url/$id"
        $rq.Uri = new-object System.Uri($uri)
        ProcessRequestWithRetryInternal -rq $rq
    }
}

function New-CosmosDocument
{
<#
.SYNOPSIS
    Inserts new document into collection

.DESCRIPTION
    Inserts new document into collection, or replaces existing when asked to perform upsert.

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
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
            #JSON string representing the document data
        $Document,

        [Parameter(Mandatory)]
        [string]
            #Partition key of new document
        $PartitionKey,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection where to store document in
        $Collection,
        [switch]
            #Whether to replace existing document with same Id and Partition key
        $IsUpsert,
        [Parameter()]
        [PSCustomObject]
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
        $rq = Get-CosmosRequest -PartitionKey $partitionKey  -Type Document -Upsert:$IsUpsert
        $rq.Method = [System.Net.Http.HttpMethod]::Post
        $uri = "$url"
        $rq.Uri = new-object System.Uri($uri)
        $rq.Payload = $Document
        $rq.ContentType = 'application/json'
        ProcessRequestWithRetryInternal -rq $rq
    }
}

function Remove-CosmosDocument
{
<#
.SYNOPSIS
    Removes document from collection

.DESCRIPTION
    Removes document from collection

.OUTPUTS
    Response describing result of operation

.EXAMPLE
    Remove-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs' -IsUpsert

Description
-----------
This command creates new document with id = '123' and partition key 'test-docs' collection 'docs', replacing potentially existing document with same id and partition key
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
            #Id of the document
        $Id,

        [Parameter(Mandatory)]
        [string]
            #Partition key value of the document
        $PartitionKey,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection that contains the document to be removed
        $Collection,

        [Parameter()]
        [PSCustomObject]
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
        $rq = Get-CosmosRequest -PartitionKey $partitionKey
        $rq.Method = [System.Net.Http.HttpMethod]::Delete
        $uri = "$url/$id"
        $rq.Uri = new-object System.Uri($uri)
        ProcessRequestWithRetryInternal -rq $rq
    }
}

function Update-CosmosDocument
{
<#
.SYNOPSIS
    Updates content of the document

.DESCRIPTION
    Updates document data according to update operations provided.
    This command uses Cosmos DB Partial document update API to perform changes on server side without the need to download the document to client, modify it on client and upload back to server

.OUTPUTS
    Response describing result of operation

.EXAMPLE
    $Updates = @()
    $Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -value 'This is new data for propery content'
    Update-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs' -Updates $Updates

Description
-----------
This command replaces field 'content' in root of the document with ID '123' and partition key 'test-docs' in collection 'docs' with new value
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
            #Id of the document
        $Id,

        [Parameter(Mandatory)]
        [string]
            #Partition key of the document
        $PartitionKey,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection containing updated document
        $Collection,

        [Parameter(Mandatory)]
        [PSCustomObject[]]
            #List of updates to perform upon the document
            #Updates are constructed by command New-CosmosDocumentUpdate
        $Updates,

        [Parameter()]
        [PSCustomObject]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($Context.Endpoint)/colls/$collection/docs"
    }

    process
    {
        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Type Document
        $rq.Method = [System.Net.Http.HttpMethod]::Patch
        $uri = "$url/$id"
        $rq.Uri = new-object System.Uri($uri)
        $rq.Payload = @{
            operations = $Updates
        } | ConvertTo-Json
        $rq.ContentType = 'application/json_patch+json'
        ProcessRequestWithRetryInternal -rq $rq
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

        [Parameter(Mandatory)]
            #value to be used by operation
        $Value
    )

    process
    {
        [PSCustomObject][ordered]@{
            op = $Operation.ToLower()
            path = $TargetPath
            value = $Value
        }
    }
}

function Set-CosmosDocument
{
<#
.SYNOPSIS
    Replaces document with new document

.DESCRIPTION
    replaces document data completely with new data. Document must exist for oepration to succeed.
    
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
        [Parameter(Mandatory)]
        [string]
            #Id of the document to be replaced
        $Id,

        [Parameter(Mandatory)]
        [string]
            #new document data
        $Document,

        [Parameter(Mandatory)]
        [string]
            #Partition key of document to be replaced
        $PartitionKey,

        [Parameter(Mandatory)]
        [string]
            #Name of collection containing the document
        $Collection,

        [Parameter()]
        [PSCustomObject]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($Context.Endpoint)/colls/$collection/docs"
    }

    process
    {
        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Type Document
        $rq.Method = [System.Net.Http.HttpMethod]::Put
        $uri = "$url/$id"
        $rq.Uri = new-object System.Uri($uri)
        $rq.Payload = $Document
        $rq.ContentType = 'application/json'
        ProcessRequestWithRetryInternal -rq $rq
    }
}
#endregion

#region CosmosLiteQuery
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
    $query = "select * from c where c.itemType = 'person'"
    $totalRuConsumption = 0
    $data = @()
    do
    {
        $rsp = Invoke-CosmosQuery -Query $query -Collection 'test-docs' -ContinuationToken $rsp.Continuation
        if($rsp.IsSuccess)
        {
            $data += $rsp.data.Documents
        }
        $totalRuConsumption+=$rsp.Charge
    }while($null -ne $rsp.Continuation)

Description
-----------
This command performs cross partition query and iteratively fetches all matching documents. Command also measures total RU consumption of the query
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
            #Query string
        $Query,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection
        $Collection,

        [Parameter()]
        [string]
            #Partition key for partition where query operates. If not specified, query queries all partitions - it's cross-partition query (expensive)
        $PartitionKey,

        [Parameter()]
        [NUllable[UInt32]]
            #Maximum number of documents to be returned by query
            #When not specified, all matching documents are returned
        $MaxItems,

        [Parameter()]
        [string]
            #Continuation token. Used to ask for next page of results
        $ContinuationToken,

        [Parameter()]
        [PSCustomObject]
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

        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Type Query -MaxItems $MaxItems
        $data = @{
            query = $Query
        }
        $rq.Method = [System.Net.Http.HttpMethod]::Post
        $uri = "$url"
        $rq.Uri = new-object System.Uri($uri)
        $rq.Payload = ($data | Convertto-json)
        $rq.ContentType = 'application/query+json'
        $rq.Continuation = $ContinuationToken
        ProcessRequestWithRetryInternal -rq $rq
    }
}

#endregion

#region CosmosLiteStoredProcedure
function Invoke-CosmosStoredProcedure
{
<#
.SYNOPSIS
    Call stored procedure

.DESCRIPTION
    Calls stored procedure.
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

        [Parameter()]
        [string]
            #Array of parameters to pass to stored procedure
            #When passing array of objects as single parameter, be sure that array is properly formatted so as it is to single parameter object rather than array of parameters
        $Parameters,

        [Parameter(Mandatory)]
        [string]
            #Name of collection containing the stored procedure to call
        $Collection,

        [Parameter()]
        [string]
            #Partition key identifying partition to operate upon.
            #Stored procedures are currently required to operate upon single partition only
        $PartitionKey,

        [Parameter()]
        [PSCustomObject]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($Context.Endpoint)/colls/$collection/sprocs"
    }

    process
    {

        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Type SpCall -MaxItems $MaxItems
        $rq.Method = [System.Net.Http.HttpMethod]::Post
        $uri = "$url/$Name"
        $rq.Uri = new-object System.Uri($uri)
        $rq.Payload = $Parameters
        $rq.ContentType = 'application/json'
        $rq.Continuation = $ContinuationToken
        ProcessRequestWithRetryInternal -rq $rq
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
This command replaces field 'content' in root of the document with ID '123' and partition key 'test-docs' in collection 'docs' with new value
#>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory, Position = 1)]
        [int]
            #Number of retries
        $RetryCount,
        [Parameter()]
        [PSCustomObject]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    process
    {
        $Context.RetryCount = $RetryCount
    }
}
#endregion

#region CosmosLiteInternals
function FormatCosmosResponseInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Net.Http.HttpResponseMessage]
        $rsp
    )

    begin
    {
        $retVal = [PSCustomObject]@{
            IsSuccess = $false
            HttpCode = 0
            Charge = -1
            Data = $null
            Continuation = $null
        }
        $provider =  [System.Globalization.CultureInfo]::CreateSpecificCulture("en-US")
    }
    process
    {
        $retVal.IsSuccess = $rsp.IsSuccessStatusCode
        $retVal.HttpCode = $rsp.StatusCode
        $val = $null
        if($rsp.Headers.TryGetValues('x-ms-request-charge', [ref]$val)) {
            $retVal.Charge = [double]::Parse($val[0],$provider)
        }
        if($rsp.Headers.TryGetValues('x-ms-continuation', [ref]$val)) {
            $retVal.Continuation = $val[0]
        }
        if($null -ne $rsp.Content)
        {
            $s = $rsp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $retVal.Data = ($s | ConvertFrom-Json -ErrorAction Stop)
        }
        return $retVal
    }
}
function ProcessRequestWithRetryInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject]$rq
    )

    process
    {
        do {

            try {
                $request = GetCosmosRequestInternal -rq $rq
                $rsp = $script:httpClient.SendAsync($request).GetAwaiter().GetResult()
                $request.Dispose()
                if($rsp.IsSuccessStatusCode) {return (FormatCosmosResponseInternal -rsp $rsp)}
                if($rsp.StatusCode -eq 429 -and $rq.maxRetries -gt 0)
                {
                    $val = $null
                    if($rsp.Headers.TryGetValues('x-ms-retry-after-ms', [ref]$val)) {$wait = [long]$val[0]} else {$wait=1000}
                    Start-Sleep -Milliseconds $wait
                    $rq.maxRetries--
                }
                else {return (FormatCosmosResponseInternal -rsp $rsp)}
    
            }
            catch {
                throw $_.Exception
            }
            finally {
                if($null -ne $rsp) {$rsp.Dispose()}
            }
        } until ($false)
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
        $retVal.Headers.Add('x-ms-version', '2018-12-31')
        $retVal.RequestUri = $rq.Uri
        $retVal.Method = $rq.Method

        switch($rq.Type)
        {
            'Query' {
                $retVal.Content = new-object System.Net.Http.StringContent($rq.payload,$null ,$rq.ContentType)
                $retVal.Content.Headers.ContentType.CharSet=[string]::Empty
                Write-Verbose "Setting 'x-ms-documentdb-isquery' to True"
                $retVal.Headers.Add('x-ms-documentdb-isquery', 'True')

                if($null -ne $rq.MaxItems)
                {
                    Write-Verbose "Setting 'x-ms-max-item-count' to $($rq.MaxItems)"
                    $retVal.Headers.Add('x-ms-max-item-count', $rq.MaxItems)
                }
                if([string]::IsNullOrEmpty($rq.PartitionKey))
                {
                    Write-Verbose "Setting 'x-ms-documentdb-query-enablecrosspartition' to True"
                    $retVal.Headers.Add('x-ms-documentdb-query-enablecrosspartition', 'True')
                }
                if(-not [string]::IsNullOrEmpty($rq.Continuation))
                {
                    Write-Verbose "Setting 'x-ms-continuation' to $($rq.Continuation)"
                    $retVal.Headers.Add('x-ms-continuation', $rq.Continuation)
                }
                break;
            }
            {$_ -in 'SpCall','Document'} {
                $retVal.Content = new-object System.Net.Http.StringContent($rq.payload,$null ,$rq.ContentType)
                $retVal.Content.Headers.ContentType.CharSet=[string]::Empty
                break
            }
            default {}
        }
        if($rq.Upsert)
        {
            Write-Verbose "Setting 'x-ms-documentdb-is-upsert' to True"
            $retVal.Headers.Add('x-ms-documentdb-is-upsert', 'True');
        }
        if(-not [string]::IsNullOrEmpty($rq.PartitionKey))
        {
            Write-Verbose "Setting 'x-ms-documentdb-partitionkey' to [`"$($rq.PartitionKey)`"]"
            $retVal.Headers.Add('x-ms-documentdb-partitionkey', "[`"$($rq.PartitionKey)`"]")
        }

        $retVal
    }
}

function Get-CosmosRequest
{
    param(
        [Switch]$Upsert,
        [NUllable[UInt32]]$MaxItems,
        [string]$Continuation,
        [string]$PartitionKey,
        [Parameter()]
        [ValidateSet('Query','SpCall','Document','Other')]
        [string]$Type = 'Other',
        [switch]$Patch,
        [PSCustomObject]$Context = $script:Configuration
    )

    process
    {
        $token = Get-CosmosAccessToken -Context $context
        
        [PSCustomObject]@{
            AccessToken = $token.AccessToken
            Type = $Type
            MaxItems = $MaxItems
            Continuation = $Continuation
            Upsert = $Upsert
            PartitionKey = $PartitionKey
            Method = $null
            Uri = $null
            Payload = $null
            ContentType = $null
            MaxRetries = $Context.RetryCount
        }
    }
}

#endregion
