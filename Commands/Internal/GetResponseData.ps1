function GetResponseData
{
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Payload,
        [Parameter()]
        [Type]$TargetType
    )

    process
    {
        if($null -eq $TargetType)
        {
            $Payload | ConvertFrom-Json
        }
        else {
            switch($PSVersionTable.PSEdition)
            {
                'Desktop' 
                {
                    $script:DesktopSerializer.Deserialize($Payload, $TargetType)
                }
                'Core' 
                {
                    [System.Text.Json.JsonSerializer]::Deserialize($Payload, $TargetType, $Script:JsonSerializerOptions)
                }
            }
        }
    }
}