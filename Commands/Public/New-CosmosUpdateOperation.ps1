function New-CosmosUpdateOperation
{
<#
.SYNOPSIS
    Creates a single partial update operation.

.DESCRIPTION
    Builds one CosmosLite.UpdateOperation entry for use in a CosmosLite.Update object.
    Use this command with New-CosmosDocumentUpdate and Update-CosmosDocument.
    
.OUTPUTS
    CosmosLite.UpdateOperation object.

.EXAMPLE
    $Updates = @()
    $Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -value 'This is new data for propery content'
    $Updates += New-CosmosUpdateOperation -Operation Add -TargetPath '/arrData/-' -value 'New value to be appended to the end of array'
    Update-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs' -Updates $Updates

    Description
    -----------
    Creates multiple patch operations and applies them to a document.
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('Add','Set','Replace','Remove','Increment','Move')]
        [string]
            #Type of update operation to perform
        $Operation,

        [Parameter(Mandatory)]
        [string]
            #Path to field to be updated
            # /path/path/fieldName format
        $TargetPath,

        [Parameter(ParameterSetName = 'NonMove')]
            #value to be used by operation
        $Value,
        
        [Parameter(Mandatory, ParameterSetName = 'Move')]
            #source path for move operation
        [string]$From
    )
    begin
    {
        $ops = @{
            Add = 'add'
            Set = 'set'
            Remove = 'remove'
            Replace = 'replace'
            Increment = 'incr'
            Move = 'move'
        }
    }
    process
    {
        $retVal = @{
            PSTypeName = 'CosmosLite.UpdateOperation'
            op = $ops[$Operation]
            path = $TargetPath
        }
        switch($PSCmdlet.ParameterSetName)
        {
            'Move' {
                $retVal.from = $From
                break;
            }
            default {
                switch($Operation)
                {
                    'Remove' {
                        #nothing more to do for remove operation
                        break;
                    }
                    default {
                        $retVal.value = $Value
                        break;
                    }
                }
            }
        }
        [PSCustomObject]$retVal
    }
}
