# Partition Key Ranges

## Get-CosmosCollectionPartitionKeyRanges

Returns the partition key range metadata for a collection. This is used for advanced cross-partition query scenarios where you want to query each physical partition explicitly rather than relying on the gateway to fan out.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Collection` | `String` | **Yes** | Collection name to retrieve ranges for. Accepts pipeline input. |
| `Context` | `CosmosLite.Connection` | No | Connection context. Default: last `Connect-Cosmos` result. |

### Outputs

A `CosmosLite` response object where `Data.PartitionKeyRanges` contains an array of partition range objects, each with an `id` property.

### Examples

```powershell
# Get all partition key ranges for a collection
$rsp = Get-CosmosCollectionPartitionKeyRanges -Collection 'largeCollection'
$rsp.Data.PartitionKeyRanges | Select-Object id, minInclusive, maxExclusive
```

```powershell
# Fan-out query across all partitions
$rsp = Get-CosmosCollectionPartitionKeyRanges -Collection 'largeCollection'
foreach ($range in $rsp.Data.PartitionKeyRanges) {
    Invoke-CosmosQuery -Query 'select * from c' `
        -Collection 'largeCollection' -PartitionKeyRangeId $range.id |
        Where-Object IsSuccess | ForEach-Object { $_.Data.Documents }
}
```

```powershell
# Fan-out with AutoContinue per range
$rsp = Get-CosmosCollectionPartitionKeyRanges -Collection 'largeCollection'
$allDocuments = foreach ($range in $rsp.Data.PartitionKeyRanges) {
    Invoke-CosmosQuery -Query 'select c.id, c.category from c' `
        -Collection 'largeCollection' `
        -PartitionKeyRangeId $range.id -AutoContinue |
        Where-Object IsSuccess | ForEach-Object { $_.Data.Documents }
}
```

---

## When to Use Explicit Partition Ranges

### The gateway cross-partition error

Large collections may be distributed across multiple physical partitions. If you run a cross-partition query (no `-PartitionKey`) and receive an error like:

> *The provided cross partition query can not be directly served by the gateway. This is a first chance (internal) exception that all newer clients will know how to handle gracefully.*

You can work around this by fetching the partition range IDs and querying each one explicitly.

### AutoContinue handles it automatically

When `-AutoContinue` is specified **without** `-PartitionKeyRangeId`, `Invoke-CosmosQuery` automatically retrieves all partition key ranges and queries them one by one. Use explicit ranges only when you need more control over the fan-out, such as parallel processing or checkpointing.

```powershell
# Automatic fan-out — simplest approach
Invoke-CosmosQuery -Query 'select * from c' -Collection 'largeCollection' -AutoContinue |
    Where-Object IsSuccess | ForEach-Object { $_.Data.Documents }
```

### Manual fan-out example

```powershell
$rangesRsp = Get-CosmosCollectionPartitionKeyRanges -Collection 'myCollection'
if (-not $rangesRsp.IsSuccess) { throw $rangesRsp.Data }

$query = "select * from c"
foreach ($range in $rangesRsp.Data.PartitionKeyRanges) {
    Write-Verbose "Querying partition range: $($range.id)"
    $rsp = Invoke-CosmosQuery -Query $query `
        -Collection 'myCollection' `
        -PartitionKeyRangeId $range.id
    if ($rsp.IsSuccess) {
        $rsp.Data.Documents
    } else {
        Write-Warning "Query failed on range $($range.id): $($rsp.Data)"
    }
}
```
