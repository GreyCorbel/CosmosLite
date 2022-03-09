# CosmosLite
This simple module is specialized on data manipulation in Cosmos DB. I originally used [PlagueHO/CosmosDB](https://github.com/PlagueHO/CosmosDB), however found it too difficult, because:
- it contains much more functionality than actually needed for data manipulation
- dev updates are slow
- does not support OAuth authentication (yet)
- it does unnecessary modifications on the documents, so you cannot simply do something like Get-Document | Update-Document
  - it adds props like attachments, timestamp, etc and those properties get written back to DB if you are not careful

So I ended up with this module that contains just data manipilation routines, is designed primarily for Core edition of PowerShell and uses OAuth authetication (no plans to add access key based auth)
*Note*: For authentication, companion library GreyCorbel.PublicClient.Authentication is used, along with ADAL module Microsoft.Identity.Client. I don't like relying on compiled code, if someone knows how to implement public client flow directly in PowerShell, I would be happy to reuse - feel free to let me know.

## Features
Module offers the following features:
- Creating, Reading, Replacing and Deleting of documents
- Updating of docuuments via [Partial document updates API](https://docs.microsoft.com/en-us/azure/cosmos-db/partial-document-update)
- Querying of collections
- Calling of stored procedures

All operations support retrying on throttling. For all operations,it's easy to know RU charge and detailed errors when they occur.

All operations return unified response object that contains below fields:
- `IsSuccess`: Booleans success indicator
- `HttpCode`: Http status code returned by CosmosDB REST API
- `Charge`: RU charge caused by request processing
- `Data`: Payload returned by REST API (if any)
  - For commands that return documents, contains documents returned
  - For failed requests contains detailed error message returned by CosmosDB REST API as JSON string
- `Continuation`: in case that operation returned partial dataset, contains continuation token to be used to retrieve next page of results
  - *Note*: Continuation for stored procedures returning large datasets needs to be implemented by stored procedure logic

## Authentication
Module supports OAuth authentication with AAD in Delegated context (CosmosDB auth with AAD does not currently support Application context).

No other authentication mechanisms are currently supported (let's see if other auth means - like access keys - will be needed/required). Target audience is now ad-hoc interactive scripting.

Authentication uses simple Public Client library that allows specifying own ClientId or uses well-known ClientId for Azure Powershell. Library relies on Microsoft.Identity.Client assembly that is also packed with module. 

I wish that Powershell would have built-in Public and Confidential client that would allow the same, so we would not have to pack dependencies and worry about version mismatch!

Supported authentication flows are `Interactive` (via web view/browser) or `DeviceCode` (with code displayed on command line and authentication handled by user in independent browser session)

## Samples
Few sample below, also see help that comes with commands of the module.

```powershell
#connect to cosmos db account test-acct and db test with well-known clientId for Azure PowerShell (1950a258-227b-4e31-a9cf-717495945fc2)
Connect-Cosmos -AccountName 'test-acct' -Database 'test' -TenantId 'mydomain.com'

#get document by id and partition key from container test-coll
#first request causes authentication
Get-CosmosDocument -Id '123' -PartitionKey 'sample-docs' -Collection 'docs'

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

## Roadmap
Feel free to suggest features and functionality extensions.