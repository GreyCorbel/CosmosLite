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
        $retVal.Headers.Add('x-ms-version', '2018-12-31')
        $retVal.RequestUri = $rq.Uri
        $retVal.Method = $rq.Method
        if(-not [string]::IsNullOrEmpty($rq.Session))
        {
            Write-Verbose "Setting 'x-ms-session-token' to $($rq.Session)"
            $retVal.Headers.Add('x-ms-session-token', $rq.Session)
        }

        switch($rq.Type)
        {
            'Query' {
                $retVal.Content = new-object System.Net.Http.StringContent($rq.payload,$null ,$rq.ContentType)
                $retVal.Content.Headers.ContentType.CharSet=[string]::Empty
                Write-Verbose "Setting 'x-ms-documentdb-isquery' to True"
                $retVal.Headers.Add('x-ms-documentdb-isquery', 'True')

                #avoid RequestTooLarge error because of continuation token size
                $retVal.Headers.Add('x-ms-documentdb-responsecontinuationtokenlimitinkb', '8')

                if($null -ne $rq.MaxItems)
                {
                    Write-Verbose "Setting 'x-ms-max-item-count' to $($rq.MaxItems)"
                    $retVal.Headers.Add('x-ms-max-item-count', $rq.MaxItems)
                }
                if([string]::IsNullOrEmpty($rq.PartitionKey))
                {
                    Write-Verbose "Setting 'x-ms-documentdb-query-enablecrosspartition' to True"
                    $retVal.Headers.Add('x-ms-documentdb-query-enablecrosspartition', 'True')
                }
                if(-not [string]::IsNullOrEmpty($rq.Continuation))
                {
                    Write-Verbose "Setting 'x-ms-continuation' to $($rq.Continuation)"
                    $retVal.Headers.Add('x-ms-continuation', $rq.Continuation)
                }
                break;
            }
            {$_ -in 'SpCall','Document'} {
                Write-Verbose "Setting Content"
                $retVal.Content = new-object System.Net.Http.StringContent($rq.payload,$null ,$rq.ContentType)
                $retVal.Content.Headers.ContentType.CharSet=[string]::Empty
                break
            }
            default {}
        }
        if($rq.Upsert)
        {
            Write-Verbose "Setting 'x-ms-documentdb-is-upsert' to True"
            $retVal.Headers.Add('x-ms-documentdb-is-upsert', 'True');
        }
        if(-not [string]::IsNullOrEmpty($rq.PartitionKey))
        {
            Write-Verbose "Setting 'x-ms-documentdb-partitionkey' to [`"$($rq.PartitionKey)`"]"
            $retVal.Headers.Add('x-ms-documentdb-partitionkey', "[`"$($rq.PartitionKey)`"]")
        }

        $retVal
    }
}