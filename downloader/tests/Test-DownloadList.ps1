param([Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../DownloadList.ps1')
$root=Join-Path ([IO.Path]::GetFullPath($WorkRoot)) ('list-'+[guid]::NewGuid().ToString('N'))
$path=Join-Path $root 'download-list.json'
$script:checks=0
function Assert($value,$message){if(-not $value){throw "FAIL: $message"};$script:checks++;Write-Output "PASS: $message"}
Set-IpaLanguage 'en'
$ids=@(Resolve-DownloadList "101`r`nhttps://apps.apple.com/ru/app/example/id202?l=ru`n`n101`n303")
Assert (($ids -join ',') -eq '101,202,303') 'IDs and URLs deduplicate in first-seen order'
Save-DownloadList $path ($ids -join "`n")
Assert ((Read-DownloadList $path) -eq "101`r`n202`r`n303") 'Saved app list reloads'
$before=(Get-FileHash $path).Hash
try{Save-DownloadList $path "101`nhttps://apps.apple.com.evil.test/id202";throw 'accepted'}catch{Assert ($_.Exception.Message -like 'Line 2:*') 'Invalid entries identify their line'}
Assert ((Get-FileHash $path).Hash -eq $before) 'Invalid edit preserves the saved list'
Save-DownloadList $path '303'
Assert ((Read-DownloadList $path) -eq '303') 'Removing entries persists'
Save-DownloadList $path ''
Assert ((Read-DownloadList $path) -eq '') 'Clearing the saved list persists'
[IO.File]::WriteAllText($path,'{"Version":1,"Apps":["101","202"]}')
$legacy=@(Read-DownloadEntries $path)
Assert ($legacy.Count -eq 2 -and $legacy[0].Selected -and $legacy[0].Name -eq '') 'Version 1 list loads without losing IDs'
$legacy[0].Name='Example App'; $legacy[1].Selected=$false
Write-DownloadEntries $path $legacy
$updated=@(Read-DownloadEntries $path)
Assert ($updated[0].Name -eq 'Example App' -and -not $updated[1].Selected) 'Names and selected apps survive migration and restart'
$before=(Get-FileHash $path).Hash
try{Write-DownloadEntries $path @($updated[0],$updated[0]);throw 'accepted'}catch{Assert ($_.Exception.Message -like 'This app is already*') 'Duplicate IDs rejected'}
Assert ((Get-FileHash $path).Hash -eq $before) 'Rejected duplicate preserves the list'
[IO.File]::WriteAllText($path,'broken')
try{Read-DownloadList $path;throw 'accepted'}catch{Assert ($_.Exception.Message -like 'Could not read*') 'Corrupt file is reported'}
Assert ([IO.File]::ReadAllText($path) -eq 'broken') 'Corrupt file is not overwritten'
Write-Output "$script:checks download list checks passed"
