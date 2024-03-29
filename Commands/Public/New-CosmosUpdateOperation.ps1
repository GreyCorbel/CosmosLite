function New-CosmosUpdateOperation
{
<#
.SYNOPSIS
    Constructs document update description

.DESCRIPTION
    Constructs document update description. Used together with Update-CosmosDocument command.
    
.OUTPUTS
    Document update descriptor

.EXAMPLE
    $Updates = @()
    $Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -value 'This is new data for propery content'
    $Updates += New-CosmosUpdateOperation -Operation Add -TargetPath '/arrData/-' -value 'New value to be appended to the end of array'
    Update-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs' -Updates $Updates

    Description
    -----------
    This command replaces field 'content' and adds value to array field 'arrData' in root of the document with ID '123' and partition key 'test-docs' in collection 'docs'
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('Add','Set','Replace','Remove','Increment')]
        [string]
            #Type of update operation to perform
        $Operation,

        [Parameter(Mandatory)]
        [string]
            #Path to field to be updated
            # /path/path/fieldName format
        $TargetPath,

        [Parameter()]
            #value to be used by operation
        $Value
    )
    begin
    {
        $ops = @{
            Add = 'add'
            Set = 'set'
            Remove = 'remove'
            Replace = 'replace'
            Increment = 'incr'
        }
    }
    process
    {
        [PSCustomObject]@{
            PSTypeName = 'CosmosLite.UpdateOperation'
            op = $ops[$Operation]
            path = $TargetPath
            value = $Value
        }
    }
}