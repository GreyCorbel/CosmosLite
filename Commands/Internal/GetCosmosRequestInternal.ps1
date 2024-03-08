function GetCosmosRequestInternal {
    param (
        [Parameter(Mandatory)]
        $rq
    )
    
    process
    {
        $retVal = New-Object System.Net.Http.HttpRequestMessage
        $retVal.Headers.TryAddWithoutValidation('Authorization', [System.Web.HttpUtility]::UrlEncode("type=aad`&ver=1.0`&sig=$($rq.AccessToken)")) | out-null
        $retVal.Headers.Add('x-ms-date', [DateTime]::UtcNow.ToString('r',[System.Globalization.CultureInfo]::GetCultureInfo('en-US')))
        $retVal.Headers.Add('x-ms-version', $rq.Version)
        $retVal.RequestUri = $rq.Uri
        $retVal.Method = $rq.Method
        if(-not [string]::IsNullOrEmpty($rq.Session))
        {
            #Write-Verbose "Setting 'x-ms-session-token' to $($rq.Session)"
            $retVal.Headers.Add('x-ms-session-token', $rq.Session)
        }

        switch($rq.Type)
        {
            'Query' {
                $retVal.Content = new-object System.Net.Http.StringContent($rq.payload,$null ,$rq.ContentType)
                $retVal.Content.Headers.ContentType.CharSet=[string]::Empty
                #Write-Verbose "Setting 'x-ms-documentdb-isquery' to True"
                $retVal.Headers.Add('x-ms-documentdb-isquery', 'True')

                #avoid RequestTooLarge error because of continuation token size
                $retVal.Headers.Add('x-ms-documentdb-responsecontinuationtokenlimitinkb', '8')

                if($null -ne $rq.MaxItems)
                {
                    #Write-Verbose "Setting 'x-ms-max-item-count' to $($rq.MaxItems)"
                    $retVal.Headers.Add('x-ms-max-item-count', $rq.MaxItems)
                }
                if($rq.PartitionKey.Count -eq 0)
                {
                    #Write-Verbose "Setting 'x-ms-documentdb-query-enablecrosspartition' to True"
                    $retVal.Headers.Add('x-ms-documentdb-query-enablecrosspartition', 'True')
                }
                if(-not [string]::IsNullOrEmpty($rq.Continuation))
                {
                    #Write-Verbose "Setting 'x-ms-continuation' to $($rq.Continuation)"
                    $retVal.Headers.Add('x-ms-continuation', $rq.Continuation)
                }
                if(-not [string]::IsNullOrEmpty($rq.PartitionKeyRangeId))
                {
                    #Write-Verbose "Setting 'x-ms-documentdb-partitionkeyrangeid' to $($rq.PartitionKeyRangeId)"
                    $retVal.Headers.Add('x-ms-documentdb-partitionkeyrangeid', $rq.PartitionKeyRangeId)
                }
                break;
            }
            {$_ -in 'SpCall','Document'} {
                $retVal.Content = new-object System.Net.Http.StringContent($rq.payload,$null ,$rq.ContentType)
                $retVal.Content.Headers.ContentType.CharSet=[string]::Empty
                if(-not [string]::IsNullOrEmpty($rq.ETag))
                {
                    #etag is expected to be double-quoted by http specs
                    if($rq.Etag[0] -ne '"') {$headerValue = "`"$($rq.ETag)`""} else {$headerValue = $rq.ETag}
                    $retVal.Headers.IfMatch.Add($headerValue)
                }
                if($rq.NoContentOnResponse)
                {
                    $retVal.Headers.Add('Prefer', 'return=minimal')
                }
                break
            }
            default {
                if(-not [string]::IsNullOrEmpty($rq.ETag))
                {
                    #etag is expected to be double-quoted by http specs
                    if($rq.Etag[0] -ne '"') {$headerValue = "`"$($rq.ETag)`""} else {$headerValue = $rq.ETag}
                    $retVal.Headers.IfNoneMatch.Add($headerValue)
                }
                if(-not [string]::IsNullOrEmpty($rq.PriorityLevel))
                {
                    #Write-Verbose "Setting 'x-ms-cosmos-priority-level' to $($rq.x-ms-cosmos-priority-level)"
                    $retVal.Headers.Add('x-ms-cosmos-priority-level', $rq.PriorityLevel)
                }

                break;
            }
        }
        if($rq.Upsert)
        {
            #Write-Verbose "Setting 'x-ms-documentdb-is-upsert' to True"
            $retVal.Headers.Add('x-ms-documentdb-is-upsert', 'True');
        }
        if($rq.PartitionKey.Count -gt 0)
        {
            $headerValue = $rq.PartitionKey | ConvertTo-Json -Compress
            if($headerValue[0] -ne '[') {$headerValue = "[$headerValue]"}
            $retVal.Headers.Add('x-ms-documentdb-partitionkey', $headerValue)
        }

        $retVal
    }
}