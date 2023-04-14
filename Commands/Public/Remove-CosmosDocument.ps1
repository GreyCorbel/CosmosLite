function Remove-CosmosDocument
{
<#
.SYNOPSIS
    Removes document from collection

.DESCRIPTION
    Removes document from collection

.OUTPUTS
    Response describing result of operation

.EXAMPLE
    Remove-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs'

Description
-----------
This command creates new document with id = '123' and partition key 'test-docs' collection 'docs', replacing potentially existing document with same id and partition key
#>

    [CmdletBinding()]
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
        [PSCustomObject]
            #Connection configuration object
            #Default: connection object produced by most recent call of Connect-Cosmos command
        $Context = $script:Configuration,

        [Parameter()]
        [int]
            #Degree of paralelism
        $BatchSize = 1
    )

    begin
    {
        $url = "$($context.Endpoint)/colls/$collection/docs"
        $outstandingRequests=@()
    }

    process
    {
        if($PSCmdlet.ParameterSetName -eq 'DocumentObject')
        {
            $Id = $DocumentObject.id
            foreach($attribute in $PartitionKeyAttribute)
            {
                $PartitionKey+=$DocumentObject."$attribute"
            }
        }
        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Context $Context -Collection $Collection
        $rq.Method = [System.Net.Http.HttpMethod]::Delete
        $rq.Uri = new-object System.Uri("$url/$id")

        $outstandingRequests+=SendRequestInternal -rq $rq -Context $Context
        if($outstandingRequests.Count -ge $batchSize)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
            $outstandingRequests=@()
        }
    }
    end
    {
        if($outstandingRequests.Count -gt 0)
        {
            ProcessRequestBatchInternal -Batch $outstandingRequests -Context $Context
        }
    }
}
