# Partial Updates

Cosmos DB partial document updates let you apply targeted patch operations to a document without reading and rewriting the entire payload. This is more efficient and avoids race conditions on unrelated fields.

The workflow is:
1. **`New-CosmosDocumentUpdate`** — create an update descriptor (id + partition key + optional condition)
2. **`New-CosmosUpdateOperation`** — add one or more patch operations to the descriptor
3. **`Update-CosmosDocument`** — send the update to Cosmos DB

Up to **10 operations** can be included in a single update.

---

## New-CosmosDocumentUpdate

Creates a `CosmosLite.Update` descriptor that identifies the target document and collects patch operations.

### Parameter Sets

| Set | Description |
|---|---|
| `RawPayload` | Specify `Id` and `PartitionKey` explicitly. |
| `DocumentObject` | Pipe a `PSCustomObject`; `Id` and partition key are read from the object's properties. |

### Parameters

| Parameter | Type | Required | Set | Description |
|---|---|---|---|---|
| `Id` | `String` | **Yes** | `RawPayload` | Document identifier. |
| `PartitionKey` | `String[]` | **Yes** | `RawPayload` | Partition key value(s). |
| `DocumentObject` | `PSCustomObject` | **Yes** | `DocumentObject` | Source document object. Accepts pipeline input. |
| `PartitionKeyAttribute` | `String[]` | **Yes** | `DocumentObject` | Attribute name(s) of the object used as partition key. |
| `Condition` | `String` | No | Both | Server-side filter condition. Update is applied only if the condition is satisfied. Uses Cosmos DB SQL `from c where ...` syntax. |

### Examples

```powershell
# Explicit Id and partition key
$upd = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'test-docs'
```

```powershell
# Conditional update — only apply if version matches
$upd = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'test-docs' `
    -Condition "from c where c.version = '1.0'"
```

```powershell
# From pipeline — derive Id and partition key from document's properties
$queryResult.Data.Documents | New-CosmosDocumentUpdate -PartitionKeyAttribute 'pk'
```

---

## New-CosmosUpdateOperation

Creates a single `CosmosLite.UpdateOperation` patch entry. Add the result to a `CosmosLite.Update.Updates` array.

### Supported Operations

| Operation | Description | Requires `Value` | Requires `From` |
|---|---|---|---|
| `Add` | Append to an array or add a new field | **Yes** | No |
| `Set` | Set field value (creates field if absent) | **Yes** | No |
| `Replace` | Replace existing field value (field must exist) | **Yes** | No |
| `Remove` | Delete a field | No | No |
| `Increment` | Add a numeric delta to a field | **Yes** | No |
| `Move` | Move a field to a new path | No | **Yes** |

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Operation` | `String` | **Yes** | One of: `Add`, `Set`, `Replace`, `Remove`, `Increment`, `Move`. |
| `TargetPath` | `String` | **Yes** | JSON path to the target field (e.g. `/status`, `/items/-` to append). |
| `Value` | `Object` | Depends | Value for the operation. Required for all operations except `Remove` and `Move`. |
| `From` | `String` | `Move` only | Source path for a `Move` operation. |

### Examples

```powershell
# Set a string field
$op = New-CosmosUpdateOperation -Operation Set -TargetPath '/status' -Value 'active'
```

```powershell
# Increment a counter
$op = New-CosmosUpdateOperation -Operation Increment -TargetPath '/viewCount' -Value 1
```

```powershell
# Append to an array
$op = New-CosmosUpdateOperation -Operation Add -TargetPath '/tags/-' -Value 'new-tag'
```

```powershell
# Remove a field
$op = New-CosmosUpdateOperation -Operation Remove -TargetPath '/temporaryField'
```

```powershell
# Move a field
$op = New-CosmosUpdateOperation -Operation Move -TargetPath '/newLocation' -From '/oldLocation'
```

---

## Update-CosmosDocument

Sends the patch operations in a `CosmosLite.Update` object to Cosmos DB. Supports `-WhatIf` and `-Confirm`.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `UpdateObject` | `CosmosLite.Update` | **Yes** | Update descriptor produced by `New-CosmosDocumentUpdate`. Accepts pipeline input. |
| `Collection` | `String` | **Yes** | Collection containing the document. |
| `NoContentOnResponse` | `Switch` | No | Ask the server not to return the updated document in the response. |
| `BatchSize` | `Int` | No | Parallel request degree. Default: `1`. |
| `Context` | `CosmosLite.Connection` | No | Connection context. Default: last `Connect-Cosmos` result. |

### Examples

```powershell
# Set a single field
$upd = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'test-docs'
$upd.Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/status' -Value 'archived'
$rsp = Update-CosmosDocument -UpdateObject $upd -Collection 'docs'
```

```powershell
# Multiple operations in one call
$upd = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'test-docs'
$upd.Updates += New-CosmosUpdateOperation -Operation Set     -TargetPath '/content'    -Value 'updated text'
$upd.Updates += New-CosmosUpdateOperation -Operation Add     -TargetPath '/history/-'  -Value (Get-Date -Format 'o')
$upd.Updates += New-CosmosUpdateOperation -Operation Increment -TargetPath '/version'  -Value 1
Update-CosmosDocument -UpdateObject $upd -Collection 'docs'
```

```powershell
# Conditional update — apply only when version matches
$upd = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'test-docs' `
    -Condition "from c where c.contentVersion = '1.0'"
$upd.Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -Value 'new text'
$rsp = Update-CosmosDocument -UpdateObject $upd -Collection 'docs'
if ($rsp.HttpCode -eq [System.Net.HttpStatusCode]::PreconditionFailed) {
    Write-Warning "Document version mismatch — update skipped."
}
```

```powershell
# Bulk update from query results via pipeline
Invoke-CosmosQuery -Query 'select * from c where c.status = @s' `
    -QueryParameters @{ '@s' = 'pending' } `
    -Collection 'docs' -AutoContinue |
    Where-Object IsSuccess |
    ForEach-Object { $_.Data.Documents } |
    ForEach-Object {
        $upd = $_ | New-CosmosDocumentUpdate -PartitionKeyAttribute 'pk'
        $upd.Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/status' -Value 'processed'
        $upd
    } |
    Update-CosmosDocument -Collection 'docs' -BatchSize 20
```

```powershell
# Preview without sending
$upd = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'pk'
$upd.Updates += New-CosmosUpdateOperation -Operation Remove -TargetPath '/oldField'
Update-CosmosDocument -UpdateObject $upd -Collection 'docs' -WhatIf
```

### Notes

- Maximum **10 operations** per `Update-CosmosDocument` call (Cosmos DB API limit).
- `Condition` uses the Cosmos DB filter syntax `from c where <predicate>`. When the condition is not satisfied, the server returns HTTP `412 PreconditionFailed` and the document is unchanged.
- For maximum throughput in update-heavy workloads, combine `-BatchSize` with pipeline input. See [Bulk Processing](Bulk-Processing) for performance guidance.
