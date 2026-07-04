# Bulk Processing

Most CosmosLite data commands accept a `-BatchSize` parameter that controls how many requests can be in-flight simultaneously. By default `BatchSize` is `1` (sequential), which means the command waits for each response before sending the next request.

Increasing `BatchSize` enables a **sliding-window concurrency model**: as soon as any in-flight request completes, a new request is sent immediately, keeping exactly `BatchSize` operations active at all times. This significantly increases throughput when processing many documents.

---

## How BatchSize Works

With `BatchSize = 1` (default — sequential):
```
→ Send request 1 → Wait for response 1 → Send request 2 → Wait for response 2 → ...
```

With `BatchSize = N` (sliding window):
```
→ Send requests 1..N in-flight
  → request 3 completes → send request N+1 immediately (still N in-flight)
  → request 1 completes → send request N+2 immediately
  → ...
```

Each completed request immediately frees its slot for the next pipeline item. There is no batch boundary — the window is continuous. The only pause is when a request returns HTTP 429 (throttled), in which case CosmosLite waits for the `x-ms-retry-after-ms` interval before re-sending that specific request.

---

## Commands that Support BatchSize

| Command | Default BatchSize |
|---|---|
| `Get-CosmosDocument` | 1 |
| `New-CosmosDocument` | 1 |
| `Set-CosmosDocument` | 1 |
| `Remove-CosmosDocument` | 1 |
| `Update-CosmosDocument` | 1 |
| `Invoke-CosmosStoredProcedure` | 1 |

---

## Performance Benchmark

The following benchmark updates a single document 500 times with various `BatchSize` values (from the README):

| BatchSize | Duration (ms) | Relative improvement |
|---|---|---|
| 1 | 40,473 | baseline |
| 5 | 16,884 | 2.4× faster |
| 10 | 11,296 | 3.6× faster |
| 20 | 10,265 | 3.9× faster |
| 50 | 8,164 | 5.0× faster |

Gains taper off at higher values because Cosmos DB throttling (HTTP 429) becomes the bottleneck. A `BatchSize` of 10–20 is a practical starting point for most workloads.

---

## Examples

### Bulk insert

```powershell
$documents = 1..1000 | ForEach-Object {
    @{ id = [guid]::NewGuid().ToString(); pk = 'bulk-insert'; index = $_ } | ConvertTo-Json
}
$documents | New-CosmosDocument -PartitionKey 'bulk-insert' -Collection 'docs' `
    -NoContentOnResponse -BatchSize 20
```

### Bulk partial update

```powershell
# Increment a counter on 500 documents in parallel
1..500 | ForEach-Object {
    $upd = New-CosmosDocumentUpdate -Id "doc-$_" -PartitionKey 'test'
    $upd.Updates += New-CosmosUpdateOperation -Operation Increment -TargetPath '/val' -Value $_
    $upd
} | Update-CosmosDocument -Collection 'requests' -BatchSize 20 | Out-Null
```

### Bulk delete from query

```powershell
Invoke-CosmosQuery -Query 'select c.id, c.pk from c where c.expired = true' `
    -Collection 'docs' -AutoContinue |
    Where-Object IsSuccess |
    ForEach-Object { $_.Data.Documents } |
    Remove-CosmosDocument -PartitionKeyAttribute 'pk' -Collection 'docs' -BatchSize 10 |
    Where-Object { -not $_.IsSuccess } |
    ForEach-Object { Write-Warning "Delete failed: $($_.Data)" }
```

### Measuring RU consumption during bulk operations

```powershell
$totalRU = 0
$updates | Update-CosmosDocument -Collection 'docs' -BatchSize 20 |
    ForEach-Object {
        $totalRU += $_.Charge
        if (-not $_.IsSuccess) { Write-Warning "Update failed: $($_.Data)" }
    }
Write-Host "Total RU: $totalRU"
```

---

## Tuning Guidelines

- **Start with `BatchSize = 10`** for most workloads and increase if Cosmos DB RU capacity allows.
- **Watch for HTTP 429** responses in the output — these indicate you're exceeding provisioned throughput. CosmosLite retries automatically per-request (up to `RetryCount` times, configurable via `Set-CosmosRetryCount`), but sustained throttling means `BatchSize` is too high.
- **`NoContentOnResponse`** reduces response payload size and slightly lowers RU cost for write operations.
- **Partition distribution:** Performance gains from `BatchSize` are highest when operations target documents spread across many partition keys, because Cosmos DB can process them on different backend nodes in parallel.
- **Output streams as requests complete:** With the sliding window, responses are emitted to the pipeline as each individual request finishes — you can pipe directly into further processing without waiting for all items to complete.


## Commands that Support BatchSize

| Command | Default BatchSize |
|---|---|
| `Get-CosmosDocument` | 1 |
| `New-CosmosDocument` | 1 |
| `Set-CosmosDocument` | 1 |
| `Remove-CosmosDocument` | 1 |
| `Update-CosmosDocument` | 1 |
| `Invoke-CosmosStoredProcedure` | 1 |

---

## Performance Benchmark

The following benchmark updates a single document 500 times with various `BatchSize` values (from the README):

| BatchSize | Duration (ms) | Relative improvement |
|---|---|---|
| 1 | 40,473 | baseline |
| 5 | 16,884 | 2.4× faster |
| 10 | 11,296 | 3.6× faster |
| 20 | 10,265 | 3.9× faster |
| 50 | 8,164 | 5.0× faster |

Gains taper off at higher values because Cosmos DB throttling (HTTP 429) becomes the bottleneck. A `BatchSize` of 10–20 is a practical starting point for most workloads.

---

## Examples

### Bulk insert

```powershell
$documents = 1..1000 | ForEach-Object {
    @{ id = [guid]::NewGuid().ToString(); pk = 'bulk-insert'; index = $_ } | ConvertTo-Json
}
$documents | New-CosmosDocument -PartitionKey 'bulk-insert' -Collection 'docs' `
    -NoContentOnResponse -BatchSize 20
```

### Bulk partial update

```powershell
# Increment a counter on 500 documents in parallel
1..500 | ForEach-Object {
    $upd = New-CosmosDocumentUpdate -Id "doc-$_" -PartitionKey 'test'
    $upd.Updates += New-CosmosUpdateOperation -Operation Increment -TargetPath '/val' -Value $_
    $upd
} | Update-CosmosDocument -Collection 'requests' -BatchSize 20 | Out-Null
```

### Bulk delete from query

```powershell
Invoke-CosmosQuery -Query 'select c.id, c.pk from c where c.expired = true' `
    -Collection 'docs' -AutoContinue |
    Where-Object IsSuccess |
    ForEach-Object { $_.Data.Documents } |
    Remove-CosmosDocument -PartitionKeyAttribute 'pk' -Collection 'docs' -BatchSize 10 |
    Where-Object { -not $_.IsSuccess } |
    ForEach-Object { Write-Warning "Delete failed: $($_.Data)" }
```

### Measuring RU consumption during bulk operations

```powershell
$totalRU = 0
$updates | Update-CosmosDocument -Collection 'docs' -BatchSize 20 |
    ForEach-Object {
        $totalRU += $_.Charge
        if (-not $_.IsSuccess) { Write-Warning "Update failed: $($_.Data)" }
    }
Write-Host "Total RU: $totalRU"
```

---

## Tuning Guidelines

- **Start with `BatchSize = 10`** for most workloads and increase if Cosmos DB RU capacity allows.
- **Watch for HTTP 429** responses in the output — these indicate you're exceeding provisioned throughput. CosmosLite retries automatically (up to `RetryCount` times), but sustained throttling means `BatchSize` is too high.
- **Adjust `RetryCount`** with `Set-CosmosRetryCount` if throttling is frequent — a higher retry count keeps processing running at the cost of increased latency.
- **`NoContentOnResponse`** reduces response payload size and slightly lowers RU cost for write operations.
- **Partition distribution:** Performance gains from `BatchSize` are highest when operations target documents spread across many partition keys, because Cosmos DB can process them on different backend nodes in parallel.
