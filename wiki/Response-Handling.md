# Response Handling

## CosmosLite Response Object

Every data command in CosmosLite returns a uniform response object:

| Field | Type | Description |
|---|---|---|
| `IsSuccess` | `Boolean` | `$true` when the operation succeeded (HTTP 2xx). |
| `HttpCode` | `HttpStatusCode` | HTTP status code from the Cosmos DB REST API. |
| `Charge` | `Double` | Request Units (RU) consumed by the operation. |
| `Data` | `Object` | On success: the document(s) or result payload. On failure: the JSON error object from the server. |
| `Continuation` | `String` | Pagination continuation token. `$null` on the last page. |
| `Headers` | `Hashtable` | Full server response headers. Populated only when `CollectResponseHeaders` was set on the connection. |

### Accessing Results

```powershell
$rsp = Get-CosmosDocument -Id '123' -PartitionKey 'pk' -Collection 'docs'
if ($rsp.IsSuccess) {
    $rsp.Data          # the document
    $rsp.Charge        # RU consumed
} else {
    Write-Warning "HTTP $($rsp.HttpCode): $($rsp.Data)"
}
```

For query responses, documents are nested under `Data.Documents`:

```powershell
$rsp = Invoke-CosmosQuery -Query 'select * from c' -Collection 'docs'
$rsp.Data.Documents   # array of documents on this page
```

---

## Assert-CosmosResult

Validates a CosmosLite response and throws a `CosmosLiteException` when `IsSuccess` is `$false`. Pass-through when the operation succeeded.

Use this for pipeline patterns where you want failures to terminate immediately without explicit `if` checks.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `CosmosResult` | `Object` | **Yes** | A CosmosLite response object. Accepts pipeline input. |

### Outputs

The original `CosmosLite` response object (pass-through on success).

### Examples

```powershell
# Throw immediately on failure
Get-CosmosDocument -Id '123' -PartitionKey 'pk' -Collection 'docs' | Assert-CosmosResult
```

```powershell
# Chain with further processing
$doc = (Get-CosmosDocument -Id '123' -PartitionKey 'pk' -Collection 'docs' | Assert-CosmosResult).Data
```

```powershell
# Pipeline — assert each response individually
$ids | Get-CosmosDocument -PartitionKey 'pk' -Collection 'docs' | Assert-CosmosResult |
    ForEach-Object { $_.Data }
```

### Notes

- The `CosmosLiteException` thrown contains the error `code` and `message` from `$rsp.Data`.
- For fine-grained error handling (e.g. distinguishing 404 from 412), check `$rsp.HttpCode` directly instead of using `Assert-CosmosResult`.

---

## Error Handling Patterns

### Check IsSuccess manually

Best when you need to handle specific status codes:

```powershell
$rsp = Set-CosmosDocument -Id '123' -Document $json -PartitionKey 'pk' -Collection 'docs' -Etag $etag
switch ($rsp.HttpCode) {
    200 { Write-Host "Updated successfully. RU: $($rsp.Charge)" }
    412 { Write-Warning "ETag mismatch — document was modified by another process." }
    429 { Write-Warning "Throttled (should not happen with automatic retry)." }
    default { throw "Unexpected error: $($rsp.Data)" }
}
```

### Conditional update pattern (PreconditionFailed)

```powershell
$upd = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'pk' `
    -Condition "from c where c.version = '2'"
$upd.Updates += New-CosmosUpdateOperation -Operation Increment -TargetPath '/version' -Value 1
$rsp = Update-CosmosDocument -UpdateObject $upd -Collection 'docs'
if ($rsp.HttpCode -eq [System.Net.HttpStatusCode]::PreconditionFailed) {
    Write-Warning "Condition not met — document not updated."
}
```

### Collecting total RU across pages

```powershell
$totalRU = 0
Invoke-CosmosQuery -Query 'select * from c' -Collection 'docs' -AutoContinue |
    ForEach-Object {
        if ($_.IsSuccess) { $totalRU += $_.Charge; $_.Data.Documents }
        else { throw $_.Data }
    }
Write-Host "Total RU consumed: $totalRU"
```

### Using response headers for diagnostics

```powershell
Connect-Cosmos -AccountName 'my-acct' -Database 'mydb' -UseManagedIdentity -CollectResponseHeaders

$rsp = Invoke-CosmosQuery -Query 'select * from c' -Collection 'docs' -PopulateMetrics
$rsp.Headers['x-ms-cosmos-index-utilization']
$rsp.Headers['x-ms-documentdb-query-metrics']
$rsp.Headers['x-ms-request-charge']
```
