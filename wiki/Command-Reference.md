# Command Reference

Quick-reference table of all commands exported by the `CosmosLite` module.

## All Exported Commands

| Command | Category | Description |
|---|---|---|
| [`Connect-Cosmos`](Connection#connect-cosmos) | Connection | Creates a CosmosLite connection context (supports 6 authentication modes). |
| [`Get-CosmosConnection`](Connection#get-cosmosconnection) | Connection | Returns the currently cached connection object. |
| [`Get-CosmosAccessToken`](Connection#get-cosmosaccesstoken) | Connection | Acquires an Entra ID access token for the current connection (diagnostics). |
| [`Set-CosmosRetryCount`](Connection#set-cosmosretrycount) | Connection | Updates the HTTP 429 retry limit on an existing connection. |
| [`Get-CosmosDocument`](Documents#get-cosmosdocument) | Documents | Reads a document by `Id` and `PartitionKey`. |
| [`New-CosmosDocument`](Documents#new-cosmosdocument) | Documents | Inserts or upserts a document. |
| [`Set-CosmosDocument`](Documents#set-cosmosdocument) | Documents | Replaces an existing document completely. |
| [`Remove-CosmosDocument`](Documents#remove-cosmosdocument) | Documents | Deletes one or more documents. |
| [`Invoke-CosmosQuery`](Queries#invoke-cosmosquery) | Queries | Executes a SQL query with optional pagination, parameterization, and auto-continue. |
| [`New-CosmosDocumentUpdate`](Partial-Updates#new-cosmosdocumentupdate) | Partial Updates | Creates an update descriptor for `Update-CosmosDocument`. |
| [`New-CosmosUpdateOperation`](Partial-Updates#new-cosmosupdateoperation) | Partial Updates | Creates a single patch operation (Add/Set/Replace/Remove/Increment/Move). |
| [`Update-CosmosDocument`](Partial-Updates#update-cosmosdocument) | Partial Updates | Sends partial patch operations to Cosmos DB. |
| [`Invoke-CosmosStoredProcedure`](Stored-Procedures#invoke-cosmosstoredprocedure) | Stored Procedures | Executes a stored procedure within a partition. |
| [`Get-CosmosCollectionPartitionKeyRanges`](Partition-Key-Ranges#get-cosmoscollectionpartitionkeyranges) | Infrastructure | Returns partition key range metadata for cross-partition query fan-out. |
| [`Assert-CosmosResult`](Response-Handling#assert-cosmosresult) | Utilities | Validates a response object and throws `CosmosLiteException` on failure. |

## Response Object Fields

| Field | Type | Description |
|---|---|---|
| `IsSuccess` | `Boolean` | `$true` on HTTP 2xx |
| `HttpCode` | `HttpStatusCode` | HTTP status code |
| `Charge` | `Double` | RU cost |
| `Data` | `Object` | Documents or error payload |
| `Continuation` | `String` | Pagination token (`$null` on last page) |
| `Headers` | `Hashtable` | Server headers (when `CollectResponseHeaders` is set) |

## Common Parameters on Data Commands

| Parameter | Default | Description |
|---|---|---|
| `Collection` | — | Target collection name (required on all data commands) |
| `Context` | last `Connect-Cosmos` result | `CosmosLite.Connection` object |
| `BatchSize` | `1` | Degree of parallel request processing |

## Module Information

| Property | Value |
|---|---|
| Module version | 3.1.2 |
| PowerShell compatibility | Core + Desktop |
| Author | Jiri Formacek |
| Company | GreyCorbel Solutions |
| PSGallery | [CosmosLite](https://www.powershellgallery.com/packages/CosmosLite) |
| Project | [github.com/GreyCorbel/CosmosLite](https://github.com/GreyCorbel/CosmosLite) |
| Required module | [AadAuthenticationFactory](https://github.com/GreyCorbel/AadAuthenticationFactory) ≥ 3.0.2 |

## Installation

```powershell
Install-Module AadAuthenticationFactory   # required
Install-Module CosmosLite
```
