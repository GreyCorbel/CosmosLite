# CosmosLite
This simple module is specialized on data manipulation in Cosmos DB. I originally used [PlagueHO/CosmosDB](https://github.com/PlagueHO/CosmosDB) module, however found it too difficult, because:
- it contains much more functionality than actually needed for data manipulation
- dev updates are slow
- does not support [AAD authentication and RBAC](https://docs.microsoft.com/en-us/azure/cosmos-db/how-to-setup-rbac) (yet)
- it does unnecessary modifications on the documents, so you cannot simply do something like Get-Document | Update-Document
  - it adds props like attachments, timestamp, etc and those properties get written back to DB if you are not careful, bloating the doc with unwanted duplicate data

So I ended up with this module that contains just data manipulation routines, is designed primarily for Core edition of PowerShell and uses OAuth authetication (no plans to add access key based auth)

*Note*: Design goal was to minimize dependencies. Only dependency here is MSAL module `Microsoft.Identity.Client`, with small wrapper module `GreyCorbel.Identity.Authentication` that simplifies working with Public and Confidential client runtime. 

I don't like relying on compiled code, if someone knows how to implement Public and Confidential client flows directly in PowerShell, I would be happy to reuse - feel free to let me know.

I wish that Powershell would have built-in Public and Confidential client that would allow the same, so we would not have to pack dependencies and worry about MS modules version mismatches!

## Features
Module offers the following features:
- Creating, Reading, Replacing and Deleting of documents
- Updating of docuuments via [Partial document updates API](https://docs.microsoft.com/en-us/azure/cosmos-db/partial-document-update)
- Querying of collections with continuation token support
- Calling of stored procedures

All operations support retrying on throttling. For all operations, it's easy to know RU charge and detailed errors when they occur.

All operations return unified response object that contains below fields:
- `IsSuccess`: Booleans success indicator
- `HttpCode`: Http status code returned by CosmosDB REST API
- `Charge`: RU charge caused by request processing
- `Data`: Payload returned by REST API (if any)
  - For commands that return documents, contains document(s) returned
  - For failed requests contains detailed error message returned by CosmosDB REST API as JSON string
- `Continuation`: in case that operation returned partial dataset, contains continuation token to be used to retrieve next page of results
  - *Notes*: 
    - Implementation protects against oversized continuation tokens
    - Continuation for stored procedures returning large datasets needs to be implemented by stored procedure logic

## Authentication
Module supports OAuth authentication with AAD in Delegated and Application contexts.

No other authentication mechanisms are currently supported - I don't plan to implement them here and want to focus on RBAC only. Target audience is both ad-hoc interactive scripting (with Delegated authentication) and backend processes (authentication with ClientSecret or X.509 certificate)

Authentication uses simple library that implements Public and Confidential client flows.

For Public client flow, authentication uses well-known ClientId for Azure Powershell by defsault, or you can use your app registered with your tenant, if you wish.
For Confidential client flow, use own ClientId with Client Secret or Certificate.

Library relies on Microsoft.Identity.Client assembly that is also packed with module. 

Supported authentication flows for Public client are `Interactive` (via web view/browser) or `DeviceCode` (with code displayed on command line and authentication handled by user in independent browser session)

Authentication library allows separate credentials for every CosmosDB account, so in single script / powershell session, you can connect to multiple CosmosDB accounts with different credentials at the same time.

## Samples
Few sample below, also see help that comes with commands of the module.

```powershell
#connect to cosmos db account test-acct and db test with well-known clientId for Azure PowerShell (1950a258-227b-4e31-a9cf-717495945fc2)
$ctx = Connect-Cosmos -AccountName 'test-acct' -Database 'test' -TenantId 'mydomain.com' -AuthMode Interactive

#connect to cosmos db account test-acct-2 and db test with appID and certificate
#returned context is automatically stored and used for last called Connect-Cosmos 
$thumbprint = 'e827f78a78cf532eb539479d6afe9c7f703173d5'
$appId = '1b69b00f-08f0-4798-9976-af325f7f7526'
$cert = dir Cert:\CurrentUser\My\ | where-object{$_.Thumbprint -eq $thumbprint}
Connect-Cosmos -AccountName dhl-o365-onboarding-uat -Database onboarding -TenantId dhl.com -ClientId $appId -X509Certificate $cert



#get document by id and partition key from container test-coll
#first request causes authentication
#this command uses automatically stored conteext from last Connect-Cosmos command
Get-CosmosDocument -Id '123' -PartitionKey 'sample-docs' -Collection 'docs'

#get document by id and partition key from container test-coll
#first request causes authentication
#this command uses explicit context to point to DB account and get appropriate credentials
Get-CosmosDocument -Id '123' -PartitionKey 'sample-docs' -Collection 'docs' -Context $ctx

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