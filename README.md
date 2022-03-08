# CosmosLite
This simple module is specialized on data manipulation in Cosmos DB. I originally used [PlagueHO/CosmosDB](https://github.com/PlagueHO/CosmosDB), however found it too difficult, because:
- it contains much more functionality than actually needed for data manipulation
- dev updates are slow and my pull requests with bug fixes not processed
- does not support OAuth authentication (yet)
- it does unnecessary modifications on the documents, so you cannot simply do something like Get-Document | Update-Document
  - it adds props like attachments, timestamp, etc and those properties get written back to DB if you are not careful

So I ended up with this module that contains just data manipilation routines, is designed primarily for Core edition of PowerShell and uses OAuth authetication (no plans to add access key based auth)
*Note*: For authentication, companion library GreyCorbel.PublicClient.Authentication is used, along with ADAL module Microsoft.Identity.Client. I don't like relying on compiled code, if someone knows how to implement public client flow directly in PowerShell, I would be happy to reuse - feel free to let me know.

## Roadmap
CosmosDB now support [Patching of docs](https://docs.microsoft.com/en-us/azure/cosmos-db/partial-document-update) - will be covered in vNext

# Samples
```powershell
#connect to cosmos db account test-acct and db test with well-known clientId for Azure PowerShell (1950a258-227b-4e31-a9cf-717495945fc2)
Connect-Cosmos -AccountName 'test-acct' -Database 'test' -TenantId 'mydomain.com'

#get document by id and partition key from container test-coll
#first request causes authentication
Get-CosmosDocument -Id '123' -collection 'test-coll' -partitionKey 'sample-docs'

#invoke Cosmos query returning large resultset and measure total RU consumption
$query = 'select * from c where c.partitionKey = 'sample-docs'"
$totalRU = 0
do
{
  $rslt = Invoke-CosmosQuery -Query $query -PartitionKey 'sample-docs' -ContinuationTokeen $rslt.Continuation
  if($rslt.IsSuccess)
  {
    $totalRU+=$rslt.charge
    $rslt.data.Documents
  }
  else
  {
    #contains error returned by server
    throw $rslt.data
  }
}while($null -ne $rslt.Continuation)
```
