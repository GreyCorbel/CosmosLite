function Get-CosmosAccessToken
{
    <#
.SYNOPSIS
    Retrieves AAD token for authentication with selected CosmosDB

.DESCRIPTION
    Retrieves AAD token for authentication with selected CosmosDB.
    Can be used for debug purposes; module itself gets token as needed, including refreshing the tokens when they expire

.OUTPUTS
    AuthenticationResult returned by AAD that contains access token and other information about logged-in identity.

.NOTES
    See https://learn.microsoft.com/en-us/dotnet/api/microsoft.identity.client.authenticationresult

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -TenantId mydomain.com | Get-CosmosAccessToken

    Description
    -----------
    This command retrieves configuration for specified CosmosDB account and database, and retrieves access token for it using well-known clientId of Azure PowerShell
#>

    param
    (
        [Parameter(ValueFromPipeline)]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
        $context = $script:Configuration
    )

    process
    {
        if([string]::IsNullOrEmpty($context))
        {
            throw "Call Connect-Cosmos first"
        }

        if($null -eq $script:AuthFactories[$context.AccountName])
        {
            throw "Call Connect-Cosmos first for CosmosDB account = $($context.AccountName)"
        }

        Get-AadToken -Factory $script:AuthFactories[$context.AccountName]
    }
}