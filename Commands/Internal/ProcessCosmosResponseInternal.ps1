function ProcessCosmosResponseInternal
{
    [CmdletBinding()]
    param (

        [Parameter(Mandatory)]
        [PSCustomObject]
        $ResponseContext,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context
    )

    begin
    {
        $provider =  [System.Globalization.CultureInfo]::CreateSpecificCulture("en-US")
    }
    process
    {
        #get response associated with request
        $rsp = $ResponseContext.HttpTask.Result
        #get collection request was using
        $collection = $ResponseContext.CosmosLiteRequest.Collection
        #create return structure
        $retVal=[ordered]@{
            PSTypeName = "CosmosLite.Response"
            IsSuccess = $false
            HttpCode = 0
            Charge = -1
            Data = $null
            Continuation = $null
        }

        $retVal['IsSuccess'] = $rsp.IsSuccessStatusCode
        $retVal['HttpCode'] = $rsp.StatusCode
        $val = $null
        #retrieve important headers
        if($rsp.Headers.TryGetValues('x-ms-request-charge', [ref]$val)) {
            #we do not want fractions of RU - round to whole number
            $retVal['Charge'] = [int][double]::Parse($val[0],$provider)
        }
        
        if($rsp.Headers.TryGetValues('x-ms-continuation', [ref]$val)) {
            $retVal['Continuation'] = $val[0]
        }

        #store session token for container
        if($rsp.Headers.TryGetValues('x-ms-session-token', [ref]$val)) {
            $Context.Session[$Collection] = $val[0]
        }
        #get raw response headers
        if($Context.CollectResponseHeaders)
        {
            $retVal['Headers']=@{}
            $rsp.Headers.ForEach{
                $header = $_
                switch($header.Key)
                {
                    'x-ms-documentdb-query-metrics' {
                        $retVal['Headers']["$($header.Key)"] = $header.Value[0].Split(';')
                        break
                    }
                    'x-ms-cosmos-index-utilization' {
                        $iu = $header.Value[0]
                        $retVal['Headers']["$($header.Key)"] = [system.text.encoding]::UTF8.GetString([Convert]::FromBase64String($iu)) | ConvertFrom-Json
                        break
                    }
                    default {
                        $retVal['Headers']["$($header.Key)"] = $header.Value
                        break
                    }
                }
            }
        }
        #retrieve response data
        if($null -ne $rsp.Content)
        {
            $s = $rsp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            try {
                $retVal['Data'] = ($s | GetResponseData -TargetType $ResponseContext.CosmosLiteRequest.TargetType  -ErrorAction Stop)
            }
            catch {
                throw new-object System.FormatException("InvalidJsonPayloadReceived. Error: $($_.Exception.Message)`nPayload: $s")
            }
        }
        if(-not $retVal['IsSuccess'])
        {
            $ex = [CosmosLiteException]::new($retVal['Data'].code, $retVal['Data'].message, $ResponseContext.CosmosLiteRequest)
            switch($ErrorActionPreference)
            {
                'Stop' {
                    throw $ex
                    break;
                }
                'Continue' {
                    Write-Error -Exception $ex
                    break;
                }
            }
        }
        [PSCustomObject]$retVal
    }
}