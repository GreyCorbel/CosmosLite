function Assert-CosmosResult
{
<#
.SYNOPSIS
    Validates a CosmosLite response and throws on failure.

.DESCRIPTION
    Checks the IsSuccess flag on an input CosmosLite response object.
    When the operation succeeded, the original response object is passed through.
    When the operation failed, the command throws a CosmosLiteException built from the response error payload.

.OUTPUTS
    CosmosLite response object when successful.

.NOTES
    The exception thrown by this command does not include request context.
    To preserve request details, use -ErrorAction Stop on the original command and handle that exception directly.

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myCosmosDb -TenantId mydomain.com -AuthMode Interactive
    Get-CosmosDocument -Collection 'myCollection' -Id '1' -PartitionKey 'documents' | Assert-CosmosResult

    Description
    -----------
    Retrieves a document and throws immediately if the request failed.

#>
param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        $CosmosResult
    )

    process
    {
        if($CosmosResult.IsSuccess)
        {
            $CosmosResult
        }
        else 
        {
            $ex = [CosmosLiteException]::new($CosmosResult.Data.code, $CosmosResult.Data.message)
            throw $ex
        }
    }
}