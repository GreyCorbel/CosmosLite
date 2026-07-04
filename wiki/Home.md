# CosmosLite

PowerShell module for data manipulation in Azure Cosmos DB using OAuth/Entra ID authentication and RBAC. Supports both PowerShell Core and Desktop editions.

## Features

- Create, Read, Replace, and Delete documents (CRUD)
- [Partial document updates](https://docs.microsoft.com/azure/cosmos-db/partial-document-update) (patch operations)
- SQL query execution with automatic or manual pagination
- Stored procedure execution
- Retry on throttling (HTTP 429)
- Bulk/parallel processing via `BatchSize`
- Strongly typed document deserialization
- RU charge tracking on every response
- Query and index diagnostics via response headers
- Preview API features (hierarchical partition keys)

## Requirements

| Module | Required | Purpose |
|---|---|---|
| [AadAuthenticationFactory](https://github.com/GreyCorbel/AadAuthenticationFactory) ≥ 3.0.2 | **Yes** | OAuth token acquisition for all auth flows |

```powershell
Install-Module AadAuthenticationFactory
Install-Module CosmosLite
```

## Response Object

Every data command returns a uniform response object:

| Field | Type | Description |
|---|---|---|
| `IsSuccess` | `Boolean` | `$true` when the operation succeeded |
| `HttpCode` | `HttpStatusCode` | HTTP status code from the Cosmos DB REST API |
| `Charge` | `Double` | Request Unit (RU) charge for the operation |
| `Data` | `Object` | Document(s) returned, or the JSON error payload on failure |
| `Continuation` | `String` | Continuation token when the result set is paginated |
| `Headers` | `Hashtable` | Full server response headers (only when `CollectResponseHeaders` is set on the connection) |

## Quick Start

```powershell
# 1. Connect (interactive delegated auth)
$ctx = Connect-Cosmos -AccountName 'my-cosmos-acct' -Database 'mydb' -TenantId 'mydomain.com' -AuthMode Interactive

# 2. Read a document
$rsp = Get-CosmosDocument -Id '123' -PartitionKey 'myPartition' -Collection 'myCollection'
if ($rsp.IsSuccess) { $rsp.Data }

# 3. Query
$rsp = Invoke-CosmosQuery -Query 'select * from c where c.type = @t' `
    -QueryParameters @{ '@t' = 'person' } `
    -Collection 'myCollection' -AutoContinue
$rsp | Where-Object IsSuccess | ForEach-Object { $_.Data.Documents }

# 4. Partial update
$upd = New-CosmosDocumentUpdate -Id '123' -PartitionKey 'myPartition'
$upd.Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/status' -Value 'active'
Update-CosmosDocument -UpdateObject $upd -Collection 'myCollection'
```

## Wiki Navigation

| Page | Contents |
|---|---|
| [Connection](Connection) | Connect-Cosmos, Get-CosmosConnection, Get-CosmosAccessToken, Set-CosmosRetryCount |
| [Documents](Documents) | Get, New, Set, Remove CosmosDocument |
| [Queries](Queries) | Invoke-CosmosQuery — pagination, cross-partition, diagnostics |
| [Partial Updates](Partial-Updates) | New-CosmosDocumentUpdate, New-CosmosUpdateOperation, Update-CosmosDocument |
| [Stored Procedures](Stored-Procedures) | Invoke-CosmosStoredProcedure |
| [Response Handling](Response-Handling) | Response object, Assert-CosmosResult, error patterns |
| [Bulk Processing](Bulk-Processing) | BatchSize, performance, pipeline patterns |
| [Partition Key Ranges](Partition-Key-Ranges) | Get-CosmosCollectionPartitionKeyRanges, fan-out queries |
| [Command Reference](Command-Reference) | Quick-reference table of all commands |
