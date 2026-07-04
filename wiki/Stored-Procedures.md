# Stored Procedures

## Invoke-CosmosStoredProcedure

Executes a JavaScript stored procedure registered in a Cosmos DB collection.

Stored procedures run within a single partition. If pagination of a large result set is needed, the stored procedure itself must implement the continuation logic and return a continuation token in its response.

### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Name` | `String` | **Yes** | Name of the stored procedure to invoke. |
| `Collection` | `String` | **Yes** | Collection that contains the stored procedure. |
| `Parameters` | `String` | No | JSON-serialized array of parameters to pass. Accepts pipeline input. |
| `PartitionKey` | `String[]` | No | Partition key identifying the partition to operate upon. Stored procedures must operate on a single partition. |
| `BatchSize` | `Int` | No | Parallel request degree. Default: `1`. |
| `Context` | `CosmosLite.Connection` | No | Connection context. Default: last `Connect-Cosmos` result. |

### Parameter Formatting

Parameters are passed as a **JSON array** where each element corresponds to one parameter of the stored procedure. The number of array elements must exactly match the number of procedure parameters.

```powershell
# Stored procedure signature: function myProc(name, count)
$params = @('Alice', 42) | ConvertTo-Json -AsArray
Invoke-CosmosStoredProcedure -Name 'myProc' -Parameters $params -Collection 'docs' -PartitionKey 'pk'
```

When passing an object as a single parameter, wrap it in an outer array so it is received as one argument:

```powershell
# Stored procedure signature: function myProc(inputObj)
$obj = @{ key1 = 'value1'; key2 = 'value2' }
$params = @(,$obj) | ConvertTo-Json -Depth 10   # @(,$obj) forces a single-element array
Invoke-CosmosStoredProcedure -Name 'myProc' -Parameters $params -Collection 'docs' -PartitionKey 'pk'
```

### Examples

```powershell
# Simple stored procedure with two scalar parameters
$params = @('test-docs', 100) | ConvertTo-Json -AsArray
$rsp = Invoke-CosmosStoredProcedure -Name 'sp_ProcessBatch' `
    -Parameters $params -Collection 'docs' -PartitionKey 'test-docs'
if ($rsp.IsSuccess) { $rsp.Data }
```

```powershell
# Stored procedure with an array and a number as parameters (from README example)
$arrParam = @(
    @{ key1 = 'value1'; key2 = 'value2' }
    @{ key1 = 'value3'; key2 = 'value4' }
)
$numParam = 5
$params = @($arrParam, $numParam) | ConvertTo-Json -AsArray -Depth 10

$rsp = Invoke-CosmosStoredProcedure -Name 'sp_MyProc' `
    -Parameters $params -Collection 'myCollection' -PartitionKey 'myPK'
if ($rsp.IsSuccess) { $rsp.Data }
else { throw $rsp.Data }
```

```powershell
# Procedure that implements its own continuation logic
$continuation = $null
do {
    $params = @($continuation) | ConvertTo-Json -AsArray
    $rsp = Invoke-CosmosStoredProcedure -Name 'sp_GetPagedData' `
        -Parameters $params -Collection 'docs' -PartitionKey 'myPK'
    if (-not $rsp.IsSuccess) { throw $rsp.Data }
    $rsp.Data.results   # process this page
    $continuation = $rsp.Data.continuation
} while ($null -ne $continuation)
```

### Notes

- Stored procedures execute entirely server-side in JavaScript and are limited to a single partition.
- The Cosmos DB REST API wraps the stored procedure return value in a response object; access it via `$rsp.Data`.
- For procedures that time out on large datasets, implement continuation in the stored procedure and call it in a loop as shown above.
- Stored procedures can read, write, and delete documents, making them useful for atomic multi-document operations within a partition.
