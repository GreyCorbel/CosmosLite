if($PSEdition -eq 'Desktop')
{
    add-type -AssemblyName System.Collections
    add-type -AssemblyName system.web
    $script:DesktopSerializer = [System.Web.Script.Serialization.JavaScriptSerializer]::new()
    $script:DesktopSerializer.MaxJsonLength = [int]::MaxValue
    $script:DesktopSerializer.RecursionLimit = 100
}
else {
    add-type -AssemblyName System.Collections
    add-type -AssemblyName System.Text.Json
    $Script:JsonSerializerOptions = [System.Text.Json.JsonSerializerOptions]@{
        PropertyNameCaseInsensitive = $true
        PropertyNamingPolicy = [System.Text.Json.JsonNamingPolicy]::CamelCase
        ReadCommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
        AllowTrailingCommas = $true
        MaxDepth = 100
    }
}
