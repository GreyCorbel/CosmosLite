# CosmosLite PowerShell module

## Overview
This simple module is specialized on data manipulation in Cosmos DB. I originally used [PlagueHO/CosmosDB](https://github.com/PlagueHO/CosmosDB) module, however found it too difficult, because:
- it contains much more functionality than actually needed for data manipulation
- dev updates are slow
- did not support [AAD authentication and RBAC](https://docs.microsoft.com/en-us/azure/cosmos-db/how-to-setup-rbac) at the time I started wotking on this module
- it does unnecessary modifications on the documents, so you cannot simply do something like Get-Document | Update-Document
  - it adds props like attachments, timestamp, etc and those properties get written back to DB if you are not careful, bloating the doc with unwanted duplicate data

So I ended up with this module that contains just data manipulation routines, is designed primarily for Core edition of PowerShell and uses OAuth authetication (no plans to add access key based auth)

*Note*: CosmosLite uses [AadAuthenticationFactory](https://github.com/GreyCorbel/AadAuthenticationFactory) module that implements various ways for authentication with Azure AD - form interactive login as user, over unattended authentication with Client ID and secret/certificate to AAD Managed Identity.

I wish that Powershell would have built-in Public and Confidential client that would allow the same, so we would not have to pack dependencies and worry about MS modules version mismatches!

## Features
Module offers the following features:
- Creating, Reading, Replacing and Deleting of documents
- Updating of docuuments via [Partial document updates API](https://docs.microsoft.com/en-us/azure/cosmos-db/partial-document-update)
- Querying of collections
- Calling of stored procedures

All operations support retrying on throttling. For all operations, it's easy to know RU charge and detailed errors when they occur.  
Commands support bulk mode when multiple requests can be sent to CosmosDB at the same time.

All operations return unified response object that contains below fields:
- `IsSuccess`: Booleans success indicator
- `HttpCode`: Http status code returned by CosmosDB REST API
- `Charge`: RU charge caused by request processing
- `Data`: Payload returned by Cosmos DB REST API (if any)
  - For commands that return documents, contains document(s) returned
  - For failed requests contains detailed error message returned by CosmosDB REST API as JSON string
- `Continuation`: in case that operation returned partial dataset, contains continuation token to be used to retrieve next page of results
  - *Note*: Continuation mechanism for stored procedures returning large datasets needs to be implemented by stored procedure logic

Optionally, response object may also contain Headers field - complete set of headers as returned by server. This functionality is turned on via `CollectResponseHeader` switch of `Connect-Cosmos` command and may be usable for troubleshooting.

## Bulk processing support and performance
Bulk processing is supported for most commands implemented by modul via `BatchSize` parameter. By default, `BatchSize` has value 1, which means that bulk processing is turned off. This means that when running as part of pipeline, command waits until response is returned from Cosmos DB before sending another request. By increasing `BatchSize` parameter, command does not wait for Cosmos DB  response and sends another request immediately. Command sends up to `BatchSize` requests without waiting, and only after then in checks response for all outstaning requests. This can significantly increase performance for workloads where performance is critical.

Let's demostrate it on simple test code that uses `Update-CosmosDocument` command.
We have simple testing document in Cosmos DB container:
```json
{
  "id": "1",
  "val": 0,
  "partitionKey": "test",
}
```
We will update the `val` attribute via partial document update 500 times by test script with various batch sizes to see overall performace of test.
```powershell
#Create a scriptblock that will feed the Update-CosmosDocument command
$scriptBlock = {
  param(
    [Parameter(Mandatory,ValueFromPipeline)][int]$i
  )
  process{
    $update = New-CosmosDocumentUpdate -Id 1 -PartitionKey test
    $update.updates+=New-CosmosUpdateOperation -Operation Increment -TargetPath '/val' -Value $i
    $update
  }
}

#do the test by updating test document 500 times
$batchSizes = 1,5,10,20,50
#perform the test for all batch sizes
foreach($batchSize in $batchSizes)
{
  $start=(get-date)
  1..500 | &$scriptBlock | Update-CosmosDocument -Collection requests -BatchSize $batchSize | Out-Null
  $duration = (get-date)-$start
  [PSCustomObject]@{BatchSize = $batchSize; Duration = [int]$duration.TotalMilliseconds}
}
```
Output shows significant performance gain for batch sizes > 1:

|Batch Size |Duration [ms]|
|---------  |--------
|       1   | 40473 
|       5   | 16884 
|      10   | 11296
|      20   | 10265
|      50   | 8164

## Authentication
Module supports OAuth/OpenId Connect authentication with Azure AD in Delegated and Application contexts.

No other authentication mechanisms are currently supported - I don't plan to implement them here and want to focus on RBAC and OAuth only. Target audience is both ad-hoc interactive scripting (with Delegated authentication) and backend processes with explicit app identity (authentication with ClientSecret or X.509 certificate) or implicit identity (authenticated with Azure Managed Identity)

Authentication is implemented by utility module [AadAuthenticationFactory](https://github.com/GreyCorbel/AadAuthenticationFactory) this module depends on.

For Public client flow, authentication uses well-known ClientId for Azure Powershell by default, or you can use your app registered with your tenant, if you wish.

For Confidential client flow, use own ClientId with Client Secret or Certificate.

For Azure Managed identity, supported environments are Azure VM and Azure App Service / App Function / Azure Automation - all cases with System Managed Identity and User-assigned Managed Identity.  
Arc-enabled server running out of Azure are also supported.

Supported authentication flows for Public client are `Interactive` (via web view/browser) or `DeviceCode` (with code displayed on command line and authentication handled by user in independent browser session)

Authentication allows separate credentials for every Cosmos DB account, so in single script / powershell session, you can connect to multiple Cosmos DB accounts and databases with different credentials at the same time - just store connection returned by `Connect-Cosmos` command in variable and use it as needed.

## Samples
Few samples below, also see help that comes with commands of the module.

### Connection to DB
```powershell
#connect to cosmos db account test-acct and db test with well-known clientId for Azure PowerShell (1950a258-227b-4e31-a9cf-717495945fc2)
$ctx = Connect-Cosmos -AccountName 'test-acct' -Database 'test' -TenantId 'mydomain.com' -AuthMode Interactive

#connect to cosmos db account myCosmosDbAccount and db myDbInCosmosAccount with appID and certificate
#returned context is automatically stored and used for subsequent call of other commands
$thumbprint = 'e827f78a7acf532eb539479d6afe9c7f703173d5'
$appId = '1b69b00f-08fc-4798-9976-af325f7f7526'
$cert = dir Cert:\CurrentUser\My\ | where-object{$_.Thumbprint -eq $thumbprint}
Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -TenantId mycompany.com -ClientId $appId -X509Certificate $cert

#connect Cosmos with System assigned Managed Identity or identity of Arc-enabled server
Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -UseManagedIdentity

#connect Cosmos with User assigned Managed Identity
Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -ClientId '3a174b1e-7b2a-4f21-a326-90365ff741cf' -UseManagedIdentity

#connect Cosmos with User assigned Managed Identity and collect server response headers
Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -ClientId '3a174b1e-7b2a-4f21-a326-90365ff741cf' -UseManagedIdentity -CollectResponseHeaders

```
### Working with documents

```powershell
#get document by id and partition key from container test-coll
#first request causes authentication
#this command uses automatically stored conteext from last Connect-Cosmos command
Get-CosmosDocument -Id '123' -PartitionKey 'sample-docs' -Collection 'docs'

#get document by id and partition key from container test-coll
#first request causes authentication
#this command uses explicit context to point to DB account and get appropriate credentials
$ctx = Connect-Cosmos -AccountName 'test-acct' -Database 'test' -TenantId 'mydomain.com' -AuthMode Interactive
Get-CosmosDocument -Id '123' -PartitionKey 'sample-docs' -Collection 'docs' -Context $ctx
```
### Queries
Query string completely built in powershell code:
```powershell
#invoke Cosmos query returning large resultset and measure total RU consumption
$query = "select * from c where c.partitionKey = 'sample-docs'"
$totalRU = 0
do
{
  $rslt = Invoke-CosmosQuery -Query $query -PartitionKey 'sample-docs' -ContinuationToken $rslt.Continuation
  if($rslt.IsSuccess)
  {
    $totalRU+=$rslt.charge
    $rslt.Data.Documents
  }
  else
  {
    #contains error returned by server
    throw $rslt.data
  }
}while($null -ne $rslt.Continuation)
```

Parametrized query that pipes returned documents to be updated by bulk update:
```powershell
#invoke Cosmos query returning large resultset and measure total RU consumption
$query = "select * from c where c.partitionKey = @pk"
$queryParams=@{
  '@pk' = 'sample-docs'
}
do
{
  $rslt = Invoke-CosmosQuery -Query $query -QueryParameters $queryParameters -PartitionKey 'sample-docs' -ContinuationToken $rslt.Continuation
  if($rslt.IsSuccess)
  {
    $rslt.Data.Documents | Foreach-Object{
        $docUpdate = $_ | New-CosmosDocumentUpdate -PartitionKeyAttribute pk
        $docUpdate.Updates+=New-CosmosUpdateOperation -Operation Increment -TargetPath '/val' -Value 1
        $docUpdate
    } | Update-CosmosDocument -Collection test -BatchSize 20 -Verbose | Format-Table @{N='Id'; E={$_.Data.Id};Width=10}, Charge, HttpCode
  }
  else
  {
    #contains error returned by server
    throw $rslt.data
  }
}while($null -ne $rslt.Continuation)

```
### Stored procedures
Invoke Cosmos stored procedure:
```powershell
#invoke Cosmos stored procedure
#  procedure takes 2 parameters - first is array of objects, second is a number
#  parameter formatting is important - params have to be passed as an array with # of members same as # of parameters of procedure, so as they are properly processed
#  formatting is reponsibility of caller. Parameters are passed as JSON string representing properly formatted parameters

$arrParam = @(
  @{
    key1 = "value1"
    key2 = "value2"
  },
  @{
    key1 = "value3"
    key2 = "value4"
  }
)

$numParam = 5

$params = @($arrParam, $numParam) | ConvertTo-Json -AsArray

$rslt = Invoke-CosmosStoredProcedure -Name sp_MyProc -Parameters $params -Collection myCollection -PartitionKey myPK
  if($rslt.IsSuccess)
  {
    $totalRU+=$rslt.charge
    $rslt.Data.Documents
  }
  else
  {
    #contains error returned by server
    throw $rslt.data
  }

```

### Partial document updates
Conditional update:
```powershell
#Module supports Cosmos DB partial document updates
#Updates are passed as document update object
#For easy working with updates, update specifications can be easily constructed by New-CosmosUpdateOperation command
#Document update can be Conditional - update is applied only when provided condition is satisfied.
#If condition not satisfied, document is not update and PreconditionFailed HttpCode is returned in response
$DocumentUpdate = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'test-docs' -Condition 'from c where c.contentVersion='1.0''
$DocumentUpdate.Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -value 'This is new data for property content'
$DocumentUpdate.Updates += New-CosmosUpdateOperation -Operation Add -TargetPath '/arrData/-' -value 'New value to be appended to the end of array data'

#multiple updates are sent to Cosmos DB in single update specification
#up to 10 updates can be sent this way
$rslt = $DocumentUpdate | Update-CosmosDocument -Collection 'docs'
if(-not $rslt.IsSuccess)
{
  if($rslt.HttpCode -eq [System.Net.HttpStatusCode]::PreconditionFailed)
  {
    #document was not updated because filter condition was not fulfilled
  }
  else
  {
    #other error - throw error returned by server
    throw $rsp.Data
  }
}
```

## Roadmap
Feel free to suggest features and functionality extensions.
