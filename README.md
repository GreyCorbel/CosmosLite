# CosmosLite
This simple module is specialized on data manipulation in Cosmos DB. I originally used [PlagueHO/CosmosDB](https://github.com/PlagueHO/CosmosDB) module, however found it too difficult, because:
- it contains much more functionality than actually needed for data manipulation
- dev updates are slow
- does not support [AAD authentication and RBAC](https://docs.microsoft.com/en-us/azure/cosmos-db/how-to-setup-rbac) (yet)
- it does unnecessary modifications on the documents, so you cannot simply do something like Get-Document | Update-Document
  - it adds props like attachments, timestamp, etc and those properties get written back to DB if you are not careful, bloating the doc with unwanted duplicate data

So I ended up with this module that contains just data manipulation routines, is designed primarily for Core edition of PowerShell and uses OAuth authetication (no plans to add access key based auth)

*Note*: CosmosLIie uses [AadAuthenticationFactory](https://github.com/GreyCorbel/AadAuthenticationFactory) module that implements various ways for authentication with Azure AD - form interactive login as user, over unattended authentication with Client ID and secret/certificate to AAD Managed Identity.

I wish that Powershell would have built-in Public and Confidential client that would allow the same, so we would not have to pack dependencies and worry about MS modules version mismatches!

## Features
Module offers the following features:
- Creating, Reading, Replacing and Deleting of documents
- Updating of docuuments via [Partial document updates API](https://docs.microsoft.com/en-us/azure/cosmos-db/partial-document-update)
- Querying of collections
- Calling of stored procedures

All operations support retrying on throttling. For all operations, it's easy to know RU charge and detailed errors when they occur.

All operations return unified response object that contains below fields:
- `IsSuccess`: Booleans success indicator
- `HttpCode`: Http status code returned by CosmosDB REST API
- `Charge`: RU charge caused by request processing
- `Data`: Payload returned by Cosmos DB REST API (if any)
  - For commands that return documents, contains document(s) returned
  - For failed requests contains detailed error message returned by CosmosDB REST API as JSON string
- `Continuation`: in case that operation returned partial dataset, contains continuation token to be used to retrieve next page of results
  - *Note*: Continuation for stored procedures returning large datasets needs to be implemented by stored procedure logic

## Authentication
Module supports OAuth authentication with AAD in Delegated and Application contexts.

No other authentication mechanisms are currently supported - I don't plan to implement them here and want to focus on RBAC and OAuth only. Target audience is both ad-hoc interactive scripting (with Delegated authentication) and backend processes with explicit app identity (authentication with ClientSecret or X.509 certificate) or implicit identity (authenticated with Azure Managed Identity)

Authentication uses simple library that implements Public and Confidential client flows, and authentication with Azure Managed Identity.

For Public client flow, authentication uses well-known ClientId for Azure Powershell by defsault, or you can use your app registered with your tenant, if you wish.

For Confidential client flow, use own ClientId with Client Secret or Certificate.

For Azure Managed identity, supported environments are Azure VM and Azure App Service / App Function - all cases with System Managed Identity and User Managed Identity.

Library relies on Microsoft.Identity.Client assembly that is also packed with module. 

Supported authentication flows for Public client are `Interactive` (via web view/browser) or `DeviceCode` (with code displayed on command line and authentication handled by user in independent browser session)

Authentication library allows separate credentials for every CosmosDB account, so in single script / powershell session, you can connect to multiple CosmosDB accounts with different credentials at the same time.

## Samples
Few sample below, also see help that comes with commands of the module.

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

#connect Cosmos with System assigned Managed Identiy
Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -UseManagedIdentity

#connect Cosmos with User assigned Managed Identiy
Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -ClientId '3a174b1e-7b2a-4f21-a326-90365ff741cf' -UseManagedIdentity
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
Get-CosmosDocument -Id '123' -PartitionKey 'sample-docs' -Collection 'docs' -Context $ctx
```
### Queries

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
### Stored procedures

```powershell
#invoke Cosmos stored procedure
#  procedure takes 2 parameters - first is array of objects, second is a number
#  parameter formatting is important - params have to be passed as an array with # of members same as # of parameters of procedure
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

```powershell
#Module supports Cosmos DB partial document updates
#Updates are passed as an array of update specifrication objects
#For easy working with updates, updates spec objects can be easily constructed by New-CosmosUpdateOperation command
$Updates = @()
$Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -value 'This is new data for propery content'
$Updates += New-CosmosUpdateOperation -Operation Add -TargetPath '/arrData/-' -value 'New value to be appended to the end of array data'

#multiple updates are sent to Cosmos DB in single batch
Update-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs' -Updates $Updates

```


## Roadmap
Feel free to suggest features and functionality extensions.