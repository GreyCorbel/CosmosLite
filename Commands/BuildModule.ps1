param
(
    [string]$rootPath = '.'
)
$moduleFile = "$rootPath\Module\CosmosLite\CosmosLite.psm1"
'#region Public commands' | Out-File -FilePath $moduleFile
foreach($file in Get-ChildItem -Path "$rootPath\Commands\Public")
{
    Get-Content $file.FullName | Out-File -FilePath $moduleFile -Append
}
'#endregion Public commands' | Out-File -FilePath $moduleFile -Append

'#region Internal commands' | Out-File -FilePath $moduleFile -Append
foreach($file in Get-ChildItem -Path "$rootPath\Commands\Internal")
{
    Get-Content $file.FullName | Out-File -FilePath $moduleFile -Append
}
'#endregion Internal commands' | Out-File -FilePath $moduleFile -Append
