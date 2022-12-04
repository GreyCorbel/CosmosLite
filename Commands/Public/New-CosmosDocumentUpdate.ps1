function New-CosmosDocumentUpdate
{
<#
.SYNOPSIS
    Constructs document update specification object expected by Update-CosmosDocument command

.DESCRIPTION
    Constructs document update description. Used together with Update-CosmosDocument and New-CosmoUpdateOperation commands.
    
.OUTPUTS
    Document update specification

.EXAMPLE
    $query = 'select * from c where c.quantity < @threshold'
    $queryParams = @{
        '@threshold' = 10
    }
    $cntinuation = $null
    do
    {
        $rslt = Invoke-CosmosQuery -Query $query -QueryParameters $queryParams -Collection 'test-docs' ContinuationToken $continuation
        if(!$rslt.IsSuccess)
        {
            throw $rslt.Data
        }
        $rslt.Data.Documents | Foreach-Object {
            $DocUpdate = $_ | New-CosmosDocumentUpdate -PartitiokKeyAttribute
            $DocUpdate.Updates+=New-CosmosUpdateOperation -Operation Increament -TargetPath '/quantitiy' -Value 50
        } | Update-CosmosDocument -Collection 'test-docs' -BatchSize 4
        $continuation = $rslt.Continuation
    }while($null -ne $continuation)

Description
-----------
This command increaments field 'quantity' by 50 on each documents that has value of this fields lower than 10
Update is performed in parallel; up to 4 updates are performed at the same time
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string]
            #Id of the document to be replaced
        $Id,

        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string]
            #Partition key of new document
        $PartitionKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #Object representing document to create
            #Command performs JSON serialization via ConvertTo-Json -Depth 99
        $DocumentObject,

        [Parameter(Mandatory, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
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
            $PartitionKey = $DocumentObject."$PartitionKeyAttribute"
        }

        [PSCustomObject]@{
            Id = $Id
            PartitionKey = $PartitionKey
            Condition = $Condition
            Updates = @()
        }
    }
}