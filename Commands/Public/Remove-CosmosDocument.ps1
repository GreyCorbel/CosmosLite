function Remove-CosmosDocument
{
<#
.SYNOPSIS
    Deletes a document from a collection.

.DESCRIPTION
    Removes one or more documents identified by id and partition key.
    Supports pipeline input and batched parallel request processing.
    Supports ShouldProcess (-WhatIf and -Confirm).

.OUTPUTS
    CosmosLite response object.

.EXAMPLE
    Remove-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs'

    Description
    -----------
    Deletes document 123 from collection docs in partition test-docs.
#>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'RawPayload')]
        [string]
            #Id of the document
        $Id,

        [Parameter(Mandatory, ParameterSetName = 'RawPayload')]
        [string[]]
            #Partition key value of the document
        $PartitionKey,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'DocumentObject')]
        [PSCustomObject]
            #Object representing document to remove
        $DocumentObject,

        [Parameter(Mandatory, ParameterSetName = 'DocumentObject')]
        [string[]]
            #attribute of DocumentObject used as partition key
        $PartitionKeyAttribute,

        [Parameter(Mandatory)]
        [string]
            #Name of the collection that contains the document to be removed
        $Collection,

        [Parameter()]
        [int]
            #Degree of paralelism for pipeline processing
        $BatchSize = 1,

        [Parameter()]
        [PSTypeName('CosmosLite.Connection')]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration
    )

    begin
    {
        $url = "$($context.Endpoint)/colls/$collection/docs"
        $outstandingRequests = [System.Collections.Generic.List[object]]::new()
    }

    process
    {
        if($PSCmdlet.ParameterSetName -eq 'DocumentObject')
        {
            $Id = $DocumentObject.id
            $PartitionKey = @()
            foreach($attribute in $PartitionKeyAttribute)
            {
                $PartitionKey+=$DocumentObject."$attribute"
            }
        }
        if($PSCmdlet.ShouldProcess("$Collection/$Id", 'Remove Cosmos document'))
        {
            $rq = Get-CosmosRequest -PartitionKey $partitionKey -Context $Context -Collection $Collection
            $rq.Method = [System.Net.Http.HttpMethod]::Delete
            $rq.Uri = new-object System.Uri("$url/$id")

            $outstandingRequests.Add((SendRequestInternal -rq $rq -Context $Context))
            while ($outstandingRequests.Count -ge $batchSize)
            {
                ProcessRequestBatchInternal -InFlight $outstandingRequests -Context $Context -DrainOne
            }
        }
        else
        {
            Write-Verbose "Skipping document $Collection/$Id"
        }
    }
    end
    {
        if ($outstandingRequests.Count -gt 0)
        {
            ProcessRequestBatchInternal -InFlight $outstandingRequests -Context $Context
        }
    }
}
