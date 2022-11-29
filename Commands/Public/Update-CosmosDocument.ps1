function Update-CosmosDocument
{
<#
.SYNOPSIS
    Updates content of the document

.DESCRIPTION
    Updates document data according to update operations provided.
    This command uses Cosmos DB Partial document update API to perform changes on server side without the need to download the document to client, modify it on client and upload back to server

.OUTPUTS
    Response describing result of operation

.EXAMPLE
    $Updates = @()
    $Updates += New-CosmosUpdateOperation -Operation Set -TargetPath '/content' -value 'This is new data for propery content'
    Update-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs' -Updates $Updates

Description
-----------
This command replaces field 'content' in root of the document with ID '123' and partition key 'test-docs' in collection 'docs' with new value
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
            #Id of the document
        $Id,

        [Parameter(Mandatory)]
        [string]
            #Partition key of the document
        $PartitionKey,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection containing updated document
        $Collection,
        
        [Parameter(Mandatory)]
        [PSCustomObject[]]
            #List of updates to perform upon the document
            #Updates are constructed by command New-CosmosDocumentUpdate
        $Updates,
        [Parameter()]
        [string]
            #condition evaluated by the server that must be met to perform the updates
        $Condition,
        [Parameter()]
        [PSCustomObject]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($Context.Endpoint)/colls/$collection/docs"
    }

    process
    {
        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Type Document -Context $Context -Collection $Collection
        $rq.Method = [System.Net.Http.HttpMethod]::Patch
        $uri = "$url/$id"
        $rq.Uri = new-object System.Uri($uri)
        $patches = @{
            operations = $Updates
        }
        if(-not [string]::IsNullOrWhiteSpace($condition))
        {
            $patches['condition'] = $Condition
        }
        $rq.Payload =  $patches | ConvertTo-Json -Depth 99
        $rq.ContentType = 'application/json_patch+json'
        ProcessRequestWithRetryInternal -rq $rq -Context $Context
    }
}