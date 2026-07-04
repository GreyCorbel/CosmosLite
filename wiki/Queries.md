# Queries

## Invoke-CosmosQuery

Executes a Cosmos DB SQL query against a collection and returns matching documents. Results may be paginated; use continuation tokens or `-AutoContinue` to retrieve the full dataset.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Query` | `String` | **Yes** | SQL query string. |
| `Collection` | `String` | **Yes** | Target collection name. |
| `QueryParameters` | `Hashtable` | No | Named parameters for parameterized queries. Keys must start with `@`. Alias: `-Parameters`. |
| `PartitionKey` | `String[]` | No | Restricts the query to a single partition. Omit for cross-partition queries. |
| `PartitionKeyRangeId` | `String[]` | No | Partition key range ID(s) from `Get-CosmosCollectionPartitionKeyRanges`. |
| `MaxItems` | `UInt32` | No | Maximum documents per page. When omitted, the server decides the page size. |
| `TargetType` | `Type` | No | .NET type to deserialize returned documents into. When omitted, `PSCustomObject` is used. |
| `ContinuationToken` | `String` | No | Resume from a previous page using the token from `$response.Continuation`. |
| `PopulateMetrics` | `Switch` | No | Includes query and index metrics in server response headers (requires `CollectResponseHeaders` on connection). |
| `AutoContinue` | `Switch` | No | Automatically follow continuation tokens and iterate over all partition key ranges. |
| `Context` | `CosmosLite.Connection` | No | Connection context. Default: last `Connect-Cosmos` result. |

### Outputs

One `CosmosLite` response object per page. Each response has:
- `IsSuccess` — success flag
- `Data.Documents` — array of documents for that page
- `Charge` — RU cost for that page
- `Continuation` — token for the next page (or `$null` on the last page)

---

### Examples

#### Basic query — manual pagination

```powershell
$query = "select * from c where c.partitionKey = 'sample-docs'"
$totalRU = 0
do {
    $rsp = Invoke-CosmosQuery -Query $query -PartitionKey 'sample-docs' `
        -Collection 'docs' -ContinuationToken $rsp.Continuation
    if ($rsp.IsSuccess) {
        $totalRU += $rsp.Charge
        $rsp.Data.Documents
    } else {
        throw $rsp.Data
    }
} while ($null -ne $rsp.Continuation)
Write-Host "Total RU: $totalRU"
```

#### Parameterized query with AutoContinue

```powershell
$query = "select * from c where c.itemType = @type"
$totalRU = 0
Invoke-CosmosQuery -Query $query `
    -QueryParameters @{ '@type' = 'person' } `
    -Collection 'docs' -AutoContinue |
    ForEach-Object {
        if ($_.IsSuccess) {
            $totalRU += $_.Charge
            $_.Data.Documents
        } else {
            throw $_.Data
        }
    }
Write-Host "Total RU: $totalRU"
```

#### Limit page size

```powershell
# Return at most 50 documents per page
$rsp = Invoke-CosmosQuery -Query 'select * from c' -Collection 'docs' -MaxItems 50
$rsp.Data.Documents
```

#### Cross-partition query with explicit partition ranges

```powershell
$rangeRsp = Get-CosmosCollectionPartitionKeyRanges -Collection 'largeCollection'
foreach ($range in $rangeRsp.Data.PartitionKeyRanges) {
    Invoke-CosmosQuery -Query 'select * from c' `
        -Collection 'largeCollection' `
        -PartitionKeyRangeId $range.id -AutoContinue |
        Where-Object IsSuccess | ForEach-Object { $_.Data.Documents }
}
```

#### Query with strongly typed deserialization

```powershell
Add-Type -TypeDefinition 'public class Person { public string id; public string name; public int age; }'
$rsp = Invoke-CosmosQuery -Query 'select c.id, c.name, c.age from c' `
    -Collection 'people' -AutoContinue -TargetType ([Person])
$rsp | Where-Object IsSuccess | ForEach-Object { $_.Data.Documents }
```

#### Query diagnostics

```powershell
# Connect with header collection enabled
Connect-Cosmos -AccountName 'my-acct' -Database 'mydb' -UseManagedIdentity -CollectResponseHeaders

$rsp = Invoke-CosmosQuery -Query 'select * from c where c.pk = @pk' `
    -QueryParameters @{ '@pk' = 'sample-docs' } `
    -Collection 'docs' -PopulateMetrics

# Index utilization
$rsp.Headers['x-ms-cosmos-index-utilization']
# Query metrics
$rsp.Headers['x-ms-documentdb-query-metrics']
```

### Notes

- **AutoContinue vs manual pagination:** `-AutoContinue` is simpler and handles both continuation tokens and partition ranges automatically. Use manual pagination when you need to checkpoint progress or process each page independently.
- **Cross-partition queries:** When `-PartitionKey` is omitted, Cosmos DB executes a cross-partition query, which is more expensive. For large collections, use explicit partition key ranges via `Get-CosmosCollectionPartitionKeyRanges`.
- **Cross-partition error:** If you receive "The provided cross partition query can not be directly served by the gateway", retrieve ranges with `Get-CosmosCollectionPartitionKeyRanges` and query each range using `-PartitionKeyRangeId`. See [Partition Key Ranges](Partition-Key-Ranges).
- **RU tracking:** Sum `$_.Charge` across pages to get total RU consumption for a query.
