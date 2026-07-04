# Connection

These commands manage the CosmosLite connection context used by all data commands.

---

## Connect-Cosmos

Creates a `CosmosLite.Connection` object and stores it in module scope. No network call is made at this point; authentication and token acquisition happen on the first data operation.

The most recently created context is cached automatically and used by all other commands when `-Context` is omitted.

### Parameter Sets

| Parameter Set | Use case |
|---|---|
| `PublicClient` | Interactive, DeviceCode, WIA, or WAM delegated auth |
| `ConfidentialClientWithSecret` | App identity with client secret |
| `ConfidentialClientWithCertificate` | App identity with X.509 certificate |
| `MSI` | Azure Managed Identity (system or user-assigned) |
| `ResourceOwnerPassword` | Resource owner password credential flow |
| `ExistingFactory` | Pass a pre-built `AadAuthenticationFactory` object |

### Common Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `AccountName` | `String` | **Yes** | Name of the Cosmos DB account (e.g. `my-cosmos-acct`). |
| `Database` | `String` | **Yes** | Database name inside the account. |
| `ClientId` | `String` | No | App registration client ID. Defaults to the well-known Azure PowerShell client ID. |
| `Scope` | `String` | No | Custom OAuth scope override. Default: `https://{AccountName}.documents.azure.com/.default`. |
| `LoginApi` | `String` | No | AAD authority endpoint. Default: `https://login.microsoftonline.com`. |
| `CollectResponseHeaders` | `Switch` | No | Collect full server response headers in every response object's `Headers` field. |
| `Preview` | `Switch` | No | Use the preview Cosmos DB REST API version (enables hierarchical partition keys and other preview features). |
| `RetryCount` | `Int` | No | Maximum retries on HTTP 429. Default: `10`. |
| `MaxContinuationTokenSizeInKb` | `Int` | No | Maximum continuation token size in KB. Default: `4`. Reduce when receiving "Request too large" errors. |

### Auth-specific Parameters

| Parameter | Type | Parameter Set | Description |
|---|---|---|---|
| `TenantId` | `String` | Public/Confidential/ROPC | Tenant ID or domain (e.g. `mydomain.com`). Required for non-MSI flows. |
| `AuthMode` | `String` | `PublicClient` | `Interactive`, `DeviceCode`, `WIA`, or `WAM`. |
| `UserNameHint` | `String` | `PublicClient` | Username hint for interactive flows. |
| `ClientSecret` | `String` | `ConfidentialClientWithSecret` | Client secret string. |
| `X509Certificate` | `X509Certificate2` | `ConfidentialClientWithCertificate` | Certificate object. |
| `ResourceOwnerCredential` | `PSCredential` | `ResourceOwnerPassword` | Username + password credential. |
| `UseManagedIdentity` | `Switch` | `MSI` | Use local MSI endpoint. |
| `Factory` | `Object` | `ExistingFactory` | Pre-built `AadAuthenticationFactory` instance. |
| `RedirectUri` | `Uri` | Public/Confidential | OAuth redirect URI override. |
| `Proxy` | `WebProxy` | Public/Confidential/ROPC | Web proxy for Azure connectivity. |

### Examples

```powershell
# Interactive delegated auth (prompts browser)
$ctx = Connect-Cosmos -AccountName 'my-cosmos-acct' -Database 'mydb' `
    -TenantId 'mydomain.com' -AuthMode Interactive
```

```powershell
# Device code flow (useful in headless environments)
Connect-Cosmos -AccountName 'my-cosmos-acct' -Database 'mydb' `
    -TenantId 'mydomain.com' -AuthMode DeviceCode
```

```powershell
# Confidential client with certificate
$cert = Get-Item 'Cert:\CurrentUser\My\<thumbprint>'
Connect-Cosmos -AccountName 'my-cosmos-acct' -Database 'mydb' `
    -TenantId 'mycompany.com' -ClientId 'your-app-id' -X509Certificate $cert
```

```powershell
# Confidential client with secret
Connect-Cosmos -AccountName 'my-cosmos-acct' -Database 'mydb' `
    -TenantId 'mycompany.com' -ClientId 'your-app-id' -ClientSecret 'your-secret'
```

```powershell
# System-assigned Managed Identity
Connect-Cosmos -AccountName 'my-cosmos-acct' -Database 'mydb' -UseManagedIdentity
```

```powershell
# User-assigned Managed Identity
Connect-Cosmos -AccountName 'my-cosmos-acct' -Database 'mydb' `
    -ClientId '3a174b1e-7b2a-4f21-a326-90365ff741cf' -UseManagedIdentity
```

```powershell
# Enable response header collection and limit continuation token size
Connect-Cosmos -AccountName 'my-cosmos-acct' -Database 'mydb' `
    -UseManagedIdentity -CollectResponseHeaders -MaxContinuationTokenSizeInKb 4
```

```powershell
# Use preview API for hierarchical partition key support
Connect-Cosmos -AccountName 'my-cosmos-acct' -Database 'mydb' `
    -TenantId 'mydomain.com' -AuthMode Interactive -Preview
```

```powershell
# Pass a pre-built factory (e.g. shared across multiple connections)
$factory = New-AadAuthenticationFactory -TenantId 'mycompany.com' -ClientId 'app-id' -ClientSecret 'secret'
Connect-Cosmos -AccountName 'my-cosmos-acct' -Database 'mydb' -Factory $factory
```

### Outputs

`CosmosLite.Connection` object. This is also stored in module scope and used as the default context.

### Notes

- Multiple connections to different accounts or databases can coexist in the same session — store each in a variable and pass via `-Context`.
- Authentication happens lazily on the first data command call.
- The custom scope override is useful for non-default Cosmos DB resource URLs (sovereign clouds, etc.).

---

## Get-CosmosConnection

Returns the most recently cached `CosmosLite.Connection` object from module scope.

### Parameters

None.

### Examples

```powershell
$ctx = Get-CosmosConnection
$ctx.AccountName
```

```powershell
# Inspect the active context endpoint
(Get-CosmosConnection).Endpoint
```

---

## Get-CosmosAccessToken

Acquires a Microsoft Entra ID access token for the configured Cosmos DB account. Primarily useful for troubleshooting and diagnostics — all data commands acquire tokens automatically.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Context` | `CosmosLite.Connection` | No | Connection context. Default: last `Connect-Cosmos` result. Accepts pipeline input. |

### Examples

```powershell
# Get token for the current default context
Get-CosmosAccessToken
```

```powershell
# Get token immediately after connecting
Connect-Cosmos -AccountName 'my-cosmos-acct' -Database 'mydb' -UseManagedIdentity | Get-CosmosAccessToken
```

---

## Set-CosmosRetryCount

Updates the maximum retry attempts for HTTP 429 (Too Many Requests) responses on an existing connection.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `RetryCount` | `Int` | **Yes** | New maximum retry count. |
| `Context` | `CosmosLite.Connection` | No | Connection context. Default: last `Connect-Cosmos` result. |

### Examples

```powershell
# Increase retry tolerance for a batch-heavy workload
Set-CosmosRetryCount -RetryCount 30
```

```powershell
# Apply to a specific stored connection
Set-CosmosRetryCount -RetryCount 20 -Context $ctx
```

### Notes

- Retry delay is taken from the `x-ms-retry-after-ms` header returned by the server.
- The initial `RetryCount` value can also be set in `Connect-Cosmos`.
