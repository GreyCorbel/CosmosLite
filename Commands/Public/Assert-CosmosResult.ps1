function Assert-CosmosResult
{
<#
.SYNOPSIS
    This command ensures that CosmosDB operation was successful, and returns result object or throws exception

.DESCRIPTION
    This command ensures that CosmosDB operation was successful, and returns result object or throws exception of type CosmosLiteException

.OUTPUTS
    Response describing result of operation if operation was successful. Otherwise, throws exception of type CosmosLiteException

.NOTES
    Request field on exception thrown is not set as the command does not have access to request context. To access request context, use -ErrorAction:Stop on command that throws exception with request field set in case of error.

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myCosmosDb -TenantId mydomain.com -AuthMode Interactive
    Get-DosmosDocument -Collection 'myCollection' -Id '1' -PartitionKey 'documents' | Assert-CosmosResult

    Description
    -----------
    This command returns document with id = 1 stored in partition 'documents' in collection 'myCollection'. If document is not found, command throws exception of type CosmosLiteException

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