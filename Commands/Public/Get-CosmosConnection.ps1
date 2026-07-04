function Get-CosmosConnection
{
<#
.SYNOPSIS
    Returns the currently cached CosmosLite connection.

.DESCRIPTION
    Returns the most recently created CosmosLite connection object stored in module scope.
    Use this when you want to inspect or reuse the active context without storing it in a separate variable.

.OUTPUTS
    CosmosLite.Connection object.

#>
    param ()

    process
    {
        $script:Configuration
    }
}