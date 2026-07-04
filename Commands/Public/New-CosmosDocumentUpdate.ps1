function New-CosmosDocumentUpdate
{
<#
.SYNOPSIS
    Creates a document update descriptor for partial updates.

.DESCRIPTION
    Builds a CosmosLite.Update object used by Update-CosmosDocument.
    Combine it with one or more operations created by New-CosmosUpdateOperation.

.OUTPUTS
    CosmosLite.Update object.

.EXAMPLE
    $query = 'select c.id,c.pk from c where c.quantity < @threshold'
    $queryParams = @{
        '@threshold' = 10
    }
    $cntinuation = $null
    do
    {
        $rslt = Invoke-CosmosQuery -Query $query -QueryParameters $queryParams -Collection 'docs' ContinuationToken $continuation
        if(!$rslt.IsSuccess)
        {
            throw $rslt.Data
        }
        $rslt.Data.Documents | Foreach-Object {
            $DocUpdate = $_ | New-CosmosDocumentUpdate -PartitiokKeyAttribute pk
            $DocUpdate.Updates+=New-CosmosUpdateOperation -Operation Increament -TargetPath '/quantitiy' -Value 50
        } | Update-CosmosDocument -Collection 'docs' -BatchSize 4
        $continuation = $rslt.Continuation
    }while($null -ne $continuation)

    Description
    -----------
    Builds update payloads and increments quantity by 50 for matching documents.
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string]
            #Id of the document to be replaced
        $Id,

        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string[]]
            #Partition key of new document
        $PartitionKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #Object representing document to create
            #Command performs JSON serialization via ConvertTo-Json -Depth 99
        $DocumentObject,

        [Parameter(Mandatory, ParameterSetName = 'DocumentObject')]
        [string[]]
            #attribute of DocumentObject used as partition key
        $PartitionKeyAttribute,

        [Parameter()]
        [string]
            #condition evaluated by the server that must be met to perform the updates
        $Condition
    )

    process
    {
        if($PSCmdlet.ParameterSetName -eq 'DocumentObject')
        {
            $id = $DocumentObject.id
            foreach($attribute in $PartitionKeyAttribute)
            {
                $PartitionKey+=$DocumentObject."$attribute"
            }
        }

        [PSCustomObject]@{
            PSTypeName = "CosmosLite.Update"
            Id = $Id
            PartitionKey = $PartitionKey
            Condition = $Condition
            Updates = @()
        }
    }
}