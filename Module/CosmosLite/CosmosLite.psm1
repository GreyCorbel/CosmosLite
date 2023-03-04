#region Public commands
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
                        if($ClientId -ne '1950a258-227b-4e31-a9cf-717495945fc2')
                        {
                            $script:AuthFactories[$AccountName] = New-AadAuthenticationFactory -ClientId $clientId -RequiredScopes $RequiredScopes -UseManagedIdentity
                        }
                        else 
                        {
                            #default clientId does not fit here - we do not pass it to the factory
                            $script:AuthFactories[$AccountName] = New-AadAuthenticationFactory -RequiredScopes $RequiredScopes -UseManagedIdentity
                        }
                        break;
                    }
                    'ResourceOwnerPasssword' {
                        $script:AuthFactories[$AccountName] = New-AadAuthenticationFactory -TenantId $TenantId -ClientId $ClientId -ClientSecret $clientSecret -RequiredScopes $RequiredScopes -LoginApi $LoginApi -ResourceOwnerCredential $ResourceOwnerCredential
                        break;
                    }
                }
                $script:Configuration.psobject.typenames.Insert(0,'CosmosLite.Connection.Configuration')
                $script:Configuration
        }
        catch {
            throw $_.Exception
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

        Get-AadToken -Factory $script:AuthFactories[$context.AccountName]
    }
}
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
        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Context $Context -Collection $Collection
        $rq.Method = [System.Net.Http.HttpMethod]::Get
        $rq.Uri = new-object System.Uri("$url/$id")
        ProcessRequestBatchInternal -Batch (SendRequestInternal -rq $rq -Context $Context) -Context $Context
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
        $rsp = Invoke-CosmosQuery -Query $query -QueryParameters $queryParams -Collection 'test-docs' -ContinuationToken $rsp.Continuation
        if($rsp.IsSuccess)
        {
            $data += $rsp.data.Documents
        }
        $totalRuConsumption+=$rsp.Charge
    }while($null -ne $rsp.Continuation)

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

        $rq = Get-CosmosRequest `
            -PartitionKey $partitionKey `
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

        ProcessRequestBatchInternal -Batch (SendRequestInternal -rq $rq -Context $Context) -Context $Context
    }
}
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

        [Parameter(ValueFromPipeline)]
        [string]
            #Array of parameters to pass to stored procedure, serialized to JSON string
            #When passing array of objects as single parameter, be sure that array is properly formatted so as it is a single parameter object rather than array of parameters
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
        $Context = $script:Configuration,

        [Parameter()]
        [int]
            #Degree of paralelism
        $BatchSize = 1
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
    $query = 'select * from c where c.quantity < @threshold'
    $queryParams = @{
        '@threshold' = 10
    }
    $cntinuation = $null
    do
    {
        $rslt = Invoke-CosmosQuery -Query $query -QueryParameters $queryParams -Collection 'test-docs' ContinuationToken $continuation
        if(!$rslt.IsSuccess)
        {
            throw $rslt.Data
        }
        $rslt.Data.Documents | Foreach-Object {
            $DocUpdate = $_ | New-CosmosDocumentUpdate -PartitiokKeyAttribute
            $DocUpdate.Updates+=New-CosmosUpdateOperation -Operation Increament -TargetPath '/quantitiy' -Value 50
        } | Update-CosmosDocument -Collection 'test-docs' -BatchSize 4
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
        [string]
            #Partition key of new document
        $PartitionKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #Object representing document to create
            #Command performs JSON serialization via ConvertTo-Json -Depth 99
        $DocumentObject,

        [Parameter(Mandatory, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
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
            $PartitionKey = $DocumentObject."$PartitionKeyAttribute"
        }

        [PSCustomObject]@{
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
        [string]
            #Partition key of new document
        $PartitionKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #Object representing document to create
            #Command performs JSON serialization via ConvertTo-Json -Depth 99
        $DocumentObject,

        [Parameter(Mandatory, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #attribute of DocumentObject used as partition key
        $PartitionKeyAttribute,

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
        $Context = $script:Configuration,

        [Parameter()]
        [int]
            #Degree of paralelism
        $BatchSize = 1
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
            $PartitionKey = $DocumentObject."$PartitionKeyAttribute"
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
    Removes document from collection

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
        [string]
            #Partition key value of the document
        $PartitionKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #Object representing document to remove
        $DocumentObject,

        [Parameter(Mandatory, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #attribute of DocumentObject used as partition key
        $PartitionKeyAttribute,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection that contains the document to be removed
        $Collection,

        [Parameter()]
        [PSCustomObject]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration,

        [Parameter()]
        [int]
            #Degree of paralelism
        $BatchSize = 1
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
            $PartitionKey = $DocumentObject."$PartitionKeyAttribute"
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
        [string]
            #Partition key of document to be replaced
        $PartitionKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #Object representing document to create
            #Command performs JSON serialization via ConvertTo-Json -Depth 99
        $DocumentObject,

        [Parameter(Mandatory, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #attribute of DocumentObject used as partition key
        $PartitionKeyAttribute,
        
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
        $outstandingRequests=@()
    }

    process
    {
        if($PSCmdlet.ParameterSetName -eq 'DocumentObject')
        {
            #to change document Id, you cannot use DocumentObject parameter set
            $Id = $DocumentObject.id
            $PartitionKey = $DocumentObject."$PartitionKeyAttribute"
            $Document = $DocumentObject | ConvertTo-Json -Depth 99 -Compress
        }

        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Type Document -Context $Context -Collection $Collection
        $rq.Method = [System.Net.Http.HttpMethod]::Put
        $rq.Uri = new-object System.Uri("$url/$id")
        $rq.Payload = $Document
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
    $DocUpdate = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'test-docs'
    $DocUpdate.Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -value 'This is new data for propery content'
    Update-CosmosDocument -UpdateObject $DocUpdate -Collection 'docs'

Description
-----------
This command replaces field 'content' in root of the document with ID '123' and partition key 'test-docs' in collection 'docs' with new value
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]
            #Object representing document update specification produced by New-CosmosDocumentUpdate
            #and containing collection od up to 10 updates produced by New-CosmosUpdateOperation
        $UpdateObject,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection containing updated document
        $Collection,
        
        [Parameter()]
        [PSCustomObject]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration,

        [Parameter()]
        [int]
            #Degree of paralelism
        $BatchSize = 1
    )

    begin
    {
        $url = "$($Context.Endpoint)/colls/$collection/docs"
        $outstandingRequests=@()
    }

    process
    {
        $rq = Get-CosmosRequest -PartitionKey $UpdateObject.PartitionKey -Type Document -Context $Context -Collection $Collection
        $rq.Method = [System.Net.Http.HttpMethod]::Patch
        $rq.Uri = new-object System.Uri("$url/$($UpdateObject.Id)")
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
#endregion Public commands
#region Internal commands
function Get-CosmosRequest
{
    param(
        [Switch]$Upsert,
        [NUllable[UInt32]]$MaxItems,
        [string]$Continuation,
        [string]$PartitionKey,
        [string]$Collection,
        [Parameter()]
        [ValidateSet('Query','SpCall','Document','Other')]
        [string]$Type = 'Other',
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
            Session = $Context.Session[$Collection]
            Upsert = $Upsert
            PartitionKey = $PartitionKey
            Method = $null
            Uri = $null
            Payload = $null
            ContentType = $null
            MaxRetries = $Context.RetryCount
            Collection=$Collection
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
        $retVal.Headers.Add('x-ms-version', '2018-12-31')
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
                if([string]::IsNullOrEmpty($rq.PartitionKey))
                {
                    #Write-Verbose "Setting 'x-ms-documentdb-query-enablecrosspartition' to True"
                    $retVal.Headers.Add('x-ms-documentdb-query-enablecrosspartition', 'True')
                }
                if(-not [string]::IsNullOrEmpty($rq.Continuation))
                {
                    #Write-Verbose "Setting 'x-ms-continuation' to $($rq.Continuation)"
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
            #Write-Verbose "Setting 'x-ms-documentdb-is-upsert' to True"
            $retVal.Headers.Add('x-ms-documentdb-is-upsert', 'True');
        }
        if(-not [string]::IsNullOrEmpty($rq.PartitionKey))
        {
            #Write-Verbose "Setting 'x-ms-documentdb-partitionkey' to [`"$($rq.PartitionKey)`"]"
            $retVal.Headers.Add('x-ms-documentdb-partitionkey', "[`"$($rq.PartitionKey)`"]")
        }

        $retVal
    }
}
function ProcessCosmosResponseInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Net.Http.HttpResponseMessage]
        $rsp,
        [Parameter(Mandatory)]
        $Context,
        [Parameter(Mandatory)]
        $Collection
    )

    begin
    {
        $provider =  [System.Globalization.CultureInfo]::CreateSpecificCulture("en-US")
    }
    process
    {
        $retVal=[ordered]@{
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
        #return typed object
        $cosmosResponse = [PSCustomObject]$retVal
        $cosmosResponse.psobject.typenames.Insert(0,'CosmosLite.Response') | Out-Null
        $cosmosResponse
    }
}
function ProcessRequestBatchInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Batch,
        [Parameter(Mandatory)]
        $Context
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
                    ProcessCosmosResponseInternal -rsp $httpResponse -Context $Context -Collection $cosmosRequest.Collection
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
                        ProcessCosmosResponseInternal -rsp $httpResponse -Context $Context -Collection $cosmosRequest.Collection
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
        $Context
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
#endregion Internal commands
