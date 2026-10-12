#requires -Version 5.1
param([string]$Destination=(Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$null=[IO.Directory]::CreateDirectory($Destination)
$zipPath=Join-Path $Destination 'ipa-desk-multi-0.3.0-beta.2-windows.zip'
$files=@('Start.cmd','IPA-Desk.ps1','Accounts.ps1','Engine.ps1','Metadata.ps1','Metadata.cs','Install-Tools.ps1','README.md','PRIVACY.md','THIRD_PARTY.md','LICENSE','CHANGELOG.md','RELEASE_NOTES.md','SECURITY.md','licenses/ipatool-MIT.txt','docs/BUILDING.md','docs/interface.png')
$stream=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew)
$zip=$null
try {
    $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create)
    foreach($name in $files){
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $PSScriptRoot $name),('IPA-Desk-Multi/'+$name.Replace('\','/'))) | Out-Null
    }
} finally {if($zip){$zip.Dispose()};$stream.Dispose()}
Write-Output $zipPath
Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
