param
(
    [string]$rootPath = '.'
)
$moduleFile = "$rootPath\Module\CosmosLite\CosmosLite.psm1"

'' | Out-File -FilePath $moduleFile

$parts = 'Initialization', 'Definitions', 'Public', 'Internal'
foreach($part in $parts)
{
    "#region $part" | Out-File -FilePath $moduleFile -Append
    foreach($file in Get-ChildItem -Path "$rootPath\Commands\$part")
    {
        Get-Content $file.FullName | Out-File -FilePath $moduleFile -Append
    }
    "#endregion $part`n" | Out-File -FilePath $moduleFile -Append
}
