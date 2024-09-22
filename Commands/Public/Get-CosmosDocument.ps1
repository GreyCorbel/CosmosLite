function Get-CosmosDocument
{
<#
.SYNOPSIS
    Retrieves document from the collection

.DESCRIPTION
    Retrieves document from the collection by id and partition key
    Command supports parallel processing.

.OUTPUTS
    Response containing retrieved document parsed from JSON format.

.EXAMPLE
    $rsp = Get-CosmosDocument -Id '123' -PartitionKey 'test-docs' -Collection 'docs'
    $rsp.data

    Description
    -----------
    This command retrieves document with id = '123' and partition key 'test-docs' from collection 'docs'
#>
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
            #Id of the document
        $Id,

        [Parameter(Mandatory)]
        [string[]]
            #value of partition key for the document
        $PartitionKey,

        [Parameter(Mandatory)]
        [string]
            #Name of collection conaining the document
        $Collection,

        [Parameter()]
        #Custom type to serialize documents returned by query to
        #When specified, custom serializer is used and returns objects of specified type
        #When not specified, ConvertFrom-Json command is used that returns documents as PSCustomObject
        [Type]$TargetType,

        [Parameter()]
        [string]
            #ETag to check. Document is retrieved only if server version of document has different ETag
        $Etag,

        [Parameter()]
        [ValidateSet('High','Low')]
        [string]
            #Priority assigned to request
            #High priority requests have less chance to get throttled than Low priority requests when throttlig occurs
            #Default: High
        $Priority,

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
        $outstandingRequests=@()
    }

    process
    {
        $rq = Get-CosmosRequest -PartitionKey $partitionKey -Context $Context -Collection $Collection -TargetType $TargetType
        $rq.Method = [System.Net.Http.HttpMethod]::Get
        $rq.Uri = new-object System.Uri("$url/$id")
        $rq.ETag = $ETag
        $rq.PriorityLevel = $Priority

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