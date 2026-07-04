function Get-CosmosAccessToken
{
    <#
.SYNOPSIS
    Retrieves an access token for the current CosmosLite connection.

.DESCRIPTION
    Acquires a Microsoft Entra ID token for the configured Cosmos DB account.
    This command is primarily useful for troubleshooting or diagnostics.
    Most commands acquire and refresh tokens automatically when needed.

.OUTPUTS
    Microsoft.Identity.Client.AuthenticationResult.

.NOTES
    See https://learn.microsoft.com/en-us/dotnet/api/microsoft.identity.client.authenticationresult

.EXAMPLE
    Connect-Cosmos -AccountName myCosmosDbAccount -Database myDbInCosmosAccount -TenantId mydomain.com | Get-CosmosAccessToken

    Description
    -----------
    Creates a connection and returns the access token for that context.
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
            throw ([CosmosLiteException]::new('NotInitialized', 'Call Connect-Cosmos first'))
        }

        if($null -eq $context.AuthFactory)
        {
            throw ([CosmosLiteException]::new('NotInitialized', "Call Connect-Cosmos first for CosmosDB account = $($context.AccountName)"))

        }
        #we specify scopes here in case that user pushes own factory without properly specified default scopes
        Get-AadToken -Factory $context.AuthFactory -Scopes $context.RequiredScopes
    }
}