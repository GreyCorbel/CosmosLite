function Get-CosmosConnection
{
<#
.SYNOPSIS
    Returns most recently created Cosmos connection object

.DESCRIPTION
    Returns most recently created cosmos connection object that is cached inside the module.
    Useful when you do not want to keep connection object in variable and reach for it only when needed

.OUTPUTS
    Connection configuration object.

#>
    param ()

    process
    {
        $script:Configuration
    }
}