# Documents

These commands create, read, replace, and delete documents in Cosmos DB collections.

All commands support:
- **Pipeline input** for batch processing
- **`-BatchSize`** for parallel request dispatch (see [Bulk Processing](Bulk-Processing))
- **`-Context`** for multi-account sessions (defaults to the last `Connect-Cosmos` result)
- A uniform [response object](Response-Handling) with `IsSuccess`, `HttpCode`, `Charge`, `Data`, and `Continuation`

---

## Get-CosmosDocument

Retrieves one document by `Id` and `PartitionKey`.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Id` | `String` | **Yes** | Document identifier. Accepts pipeline input. |
| `PartitionKey` | `String[]` | **Yes** | Partition key value(s) for the document. |
| `Collection` | `String` | **Yes** | Target collection name. |
| `TargetType` | `Type` | No | .NET type to deserialize into. When omitted, `ConvertFrom-Json` is used (returns `PSCustomObject`). |
| `Etag` | `String` | No | Conditional read: return document only if the server ETag differs. |
| `Priority` | `String` | No | `High` (default) or `Low`. Low-priority requests are throttled first. |
| `BatchSize` | `Int` | No | Parallel request degree. Default: `1`. |
| `Context` | `CosmosLite.Connection` | No | Connection context. Default: last `Connect-Cosmos` result. |

### Examples

```powershell
# Read a single document
$rsp = Get-CosmosDocument -Id '123' -PartitionKey 'sample-docs' -Collection 'docs'
if ($rsp.IsSuccess) { $rsp.Data }
```

```powershell
# Read with explicit context
$rsp = Get-CosmosDocument -Id '123' -PartitionKey 'sample-docs' -Collection 'docs' -Context $ctx
```

```powershell
# Pipeline — read many documents in parallel
$ids | Get-CosmosDocument -PartitionKey 'sample-docs' -Collection 'docs' -BatchSize 10 |
    Where-Object IsSuccess | ForEach-Object { $_.Data }
```

```powershell
# Conditional read — skip if server document unchanged
$rsp = Get-CosmosDocument -Id '123' -PartitionKey 'sample-docs' -Collection 'docs' -Etag $knownEtag
# $rsp.HttpCode -eq 304 means document was not modified
```

```powershell
# Deserialize into a strongly typed class
Add-Type -TypeDefinition 'public class MyDoc { public string id; public string status; }'
$rsp = Get-CosmosDocument -Id '123' -PartitionKey 'pk' -Collection 'docs' -TargetType ([MyDoc])
```

---

## New-CosmosDocument

Creates a new document in a collection. Supports upsert (create-or-replace).

### Parameter Sets

| Set | Description |
|---|---|
| `RawPayload` | Supply `Id`, `PartitionKey`, and a pre-serialized JSON `Document` string. |
| `DocumentObject` | Supply a `PSCustomObject` and the attribute name(s) used as partition key — serialization is automatic. |

### Parameters

| Parameter | Type | Required | Set | Description |
|---|---|---|---|---|
| `Document` | `String` | **Yes** | `RawPayload` | Pre-serialized JSON document string. Accepts pipeline input. |
| `PartitionKey` | `String[]` | **Yes** | `RawPayload` | Partition key value(s). |
| `DocumentObject` | `PSCustomObject` | **Yes** | `DocumentObject` | Object to serialize and store. Accepts pipeline input. |
| `PartitionKeyAttribute` | `String[]` | **Yes** | `DocumentObject` | Attribute name(s) of `DocumentObject` used as partition key. |
| `Collection` | `String` | **Yes** | Both | Target collection name. |
| `IsUpsert` | `Switch` | No | Both | Replace an existing document with the same Id and partition key. |
| `Etag` | `String` | No | Both | Conditional upsert: only create/replace if server ETag matches. |
| `Priority` | `String` | No | Both | `High` or `Low` priority. |
| `NoContentOnResponse` | `Switch` | No | Both | Ask the server not to return the created document in the response. |
| `BatchSize` | `Int` | No | Both | Parallel request degree. Default: `1`. |
| `Context` | `CosmosLite.Connection` | No | Both | Connection context. |

### Examples

```powershell
# Create from a hashtable
$doc = [Ordered]@{ id = '123'; pk = 'test-docs'; content = 'hello world' }
New-CosmosDocument -Document ($doc | ConvertTo-Json) -PartitionKey 'test-docs' -Collection 'docs'
```

```powershell
# Upsert (create or replace)
New-CosmosDocument -Document ($doc | ConvertTo-Json) -PartitionKey 'test-docs' -Collection 'docs' -IsUpsert
```

```powershell
# From PSCustomObject via pipeline (DocumentObject param set)
$objects | New-CosmosDocument -PartitionKeyAttribute 'pk' -Collection 'docs' -IsUpsert -BatchSize 20
```

```powershell
# Suppress response body for better performance on large imports
New-CosmosDocument -Document $json -PartitionKey 'pk' -Collection 'docs' -NoContentOnResponse
```

---

## Set-CosmosDocument

Replaces an existing document completely. The document must already exist.

### Parameter Sets

| Set | Description |
|---|---|
| `RawPayload` | Supply `Id`, `PartitionKey`, and a JSON `Document` string. |
| `DocumentObject` | Supply a `PSCustomObject`; `Id` and partition key are read from the object. |

### Parameters

| Parameter | Type | Required | Set | Description |
|---|---|---|---|---|
| `Id` | `String` | **Yes** | `RawPayload` | Document identifier. |
| `Document` | `String` | **Yes** | `RawPayload` | Pre-serialized JSON replacement payload. |
| `PartitionKey` | `String[]` | **Yes** | `RawPayload` | Partition key value(s). |
| `DocumentObject` | `PSCustomObject` | **Yes** | `DocumentObject` | Object to serialize and replace. Accepts pipeline input. |
| `PartitionKeyAttribute` | `String[]` | **Yes** | `DocumentObject` | Attribute name(s) used as partition key. |
| `Collection` | `String` | **Yes** | Both | Target collection name. |
| `Etag` | `String` | No | Both | Conditional replace: only replace if server ETag matches. |
| `NoContentOnResponse` | `Switch` | No | Both | Skip returning the replaced document in the response. |
| `BatchSize` | `Int` | No | Both | Parallel request degree. Default: `1`. |
| `Context` | `CosmosLite.Connection` | No | Both | Connection context. |

### Examples

```powershell
# Replace with raw JSON
$doc = @{ id = '123'; pk = 'test-docs'; content = 'updated content' }
Set-CosmosDocument -Id '123' -Document ($doc | ConvertTo-Json) -PartitionKey 'test-docs' -Collection 'docs'
```

```powershell
# Conditional replace (only if ETag matches)
Set-CosmosDocument -Id '123' -Document $json -PartitionKey 'pk' -Collection 'docs' -Etag $currentEtag
```

```powershell
# Get-then-set pattern via pipeline
Get-CosmosDocument -Id '123' -PartitionKey 'pk' -Collection 'docs' |
    ForEach-Object {
        $doc = $_.Data
        $doc.status = 'archived'
        $doc
    } |
    Set-CosmosDocument -PartitionKeyAttribute 'pk' -Collection 'docs'
```

---

## Remove-CosmosDocument

Deletes one or more documents from a collection. Supports `-WhatIf` and `-Confirm`.

### Parameter Sets

| Set | Description |
|---|---|
| `RawPayload` | Supply `Id` and `PartitionKey` directly. |
| `DocumentObject` | Supply a `PSCustomObject`; `Id` and partition key are read from it. |

### Parameters

| Parameter | Type | Required | Set | Description |
|---|---|---|---|---|
| `Id` | `String` | **Yes** | `RawPayload` | Document identifier. Accepts pipeline input. |
| `PartitionKey` | `String[]` | **Yes** | `RawPayload` | Partition key value(s). |
| `DocumentObject` | `PSCustomObject` | **Yes** | `DocumentObject` | Document object to remove. Accepts pipeline input. |
| `PartitionKeyAttribute` | `String[]` | **Yes** | `DocumentObject` | Attribute name(s) used as partition key. |
| `Collection` | `String` | **Yes** | Both | Target collection name. |
| `BatchSize` | `Int` | No | Both | Parallel request degree. Default: `1`. |
| `Context` | `CosmosLite.Connection` | No | Both | Connection context. |

### Examples

```powershell
# Delete a single document
Remove-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs'
```

```powershell
# Preview without deleting
Remove-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs' -WhatIf
```

```powershell
# Delete many documents from pipeline query results
Invoke-CosmosQuery -Query 'select c.id, c.pk from c where c.expired = true' `
    -Collection 'docs' -AutoContinue |
    Where-Object IsSuccess |
    ForEach-Object { $_.Data.Documents } |
    Remove-CosmosDocument -PartitionKeyAttribute 'pk' -Collection 'docs' -BatchSize 10
```
