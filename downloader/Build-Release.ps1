#requires -Version 5.1
param([string]$Destination=(Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$null=[IO.Directory]::CreateDirectory($Destination)
$zipPath=Join-Path $Destination 'ipa-desk-multi-0.4.0-beta.1-windows.zip'
$files=@('Start.cmd','IPA-Desk.ps1','Accounts.ps1','Engine.ps1','Metadata.ps1','Metadata.cs','Install-Tools.ps1','Localization.ps1','README.md','PRIVACY.md','THIRD_PARTY.md','LICENSE','BUILDING.md','licenses/ipatool-MIT.txt','docs/interface.png')
$stream=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew)
$zip=$null
try {
    $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create)
    foreach($name in $files){
        if($name -in @('README.md','BUILDING.md')){
            $content=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $name))
            $content=$content.Replace('(../','(https://github.com/TapOk38/ipa-desk-multi/blob/main/')
            if($name -eq 'README.md'){
                $content=$content.Replace('Run the EXE.','Run `Start.cmd`.').Replace('**Downloads → IPA Desk Multi**','`Downloads` next to `Start.cmd`')
            }
            $entry=$zip.CreateEntry('IPA-Desk-Multi/'+$name)
            $writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false))
            try {$writer.Write($content)} finally {$writer.Dispose()}
            continue
        }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $PSScriptRoot $name),('IPA-Desk-Multi/'+$name.Replace('\','/'))) | Out-Null
    }
} finally {if($zip){$zip.Dispose()};$stream.Dispose()}
Write-Output $zipPath
Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
