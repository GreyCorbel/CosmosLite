function ProcessCosmosResponseInternal
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Net.Http.HttpResponseMessage]
        $rsp,
        [Parameter(Mandatory)]
        [PSTypeName('CosmosLite.Connection')]$Context,
        [Parameter(Mandatory)]
        [string]$Collection
    )

    begin
    {
        $provider =  [System.Globalization.CultureInfo]::CreateSpecificCulture("en-US")
    }
    process
    {
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
                $retVal['Headers']["$($_.Key)"] = $_.Value
            }
        }
        #retrieve response data
        if($null -ne $rsp.Content)
        {
            $s = $rsp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            try {
                $retVal['Data'] = ($s | ConvertFrom-Json -ErrorAction Stop)
            }
            catch {
                throw new-object System.FormatException("InvalidJsonPayloadReceived. Error: $($_.Exception.Message)`nPayload: $s")
            }
        }
        [PSCustomObject]$retVal
    }
}