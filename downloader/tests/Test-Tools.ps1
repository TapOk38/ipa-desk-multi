#requires -Version 5.1
param([string]$OfficialArchive='', [string]$WorkRoot=[IO.Path]::GetTempPath())
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\Install-Tools.ps1')
Set-IpaLanguage 'ru'
$root=Join-Path $WorkRoot ('ipa-tools-test-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($root)
$script:checks=0
function Assert($Value,[string]$Message){if(-not $Value){throw "FAIL: $Message"};$script:checks++;Write-Output "PASS: $Message"}
$official=Get-IpaToolSpec
if($OfficialArchive){
    $actual=Ensure-IpaTool -AppRoot (Join-Path $root 'official') -LocalArchive $OfficialArchive
    Assert ((Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash -eq $official.ExeSha256) 'Previously downloaded official ZIP extracts to pinned EXE'
    Assert ((Ensure-IpaTool -AppRoot (Join-Path $root 'official')) -eq $actual) 'Pinned installed EXE is reused without network'
}

# All remaining tests are self-contained and offline; fixture bytes are never run.
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$fixture=Join-Path $root 'fixture.zip'; $bytes=[Text.Encoding]::UTF8.GetBytes('inert test fixture, not an executable')
$zip=[IO.Compression.ZipFile]::Open($fixture,[IO.Compression.ZipArchiveMode]::Create)
try {$entry=$zip.CreateEntry('ipatool-cpp-windows-amd64.exe');$out=$entry.Open();try{$out.Write($bytes,0,$bytes.Length)}finally{$out.Dispose()}}finally{$zip.Dispose()}
$hash=[Security.Cryptography.SHA256]::Create()
try {$exeHash=[BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-','')} finally {$hash.Dispose()}
$script:fixtureSpec=@{Version='1.0.9';Url='https://example.invalid/not-used';Entry='ipatool-cpp-windows-amd64.exe';ArchiveSha256=(Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash;ExeSha256=$exeHash}
function Get-IpaToolSpec {return $script:fixtureSpec}
function Receive-PinnedTool {throw 'Unexpected network request in offline test'}
$target=Join-Path $root 'fixture-target'
$exe=Ensure-IpaTool -AppRoot $target -LocalArchive $fixture
Assert ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -eq $exeHash) 'Archive and extracted file hashes are checked'
Assert (@(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($exe)) -Directory -Force).Count -eq 0) 'Temporary extraction directory is removed'
Assert ((Ensure-IpaTool -AppRoot $target) -eq $exe) 'Cached valid component makes no network request'
[IO.File]::WriteAllText($exe,'tampered')
$failed=$false;try{Ensure-IpaTool -AppRoot $target | Out-Null}catch{$failed=$true}
Assert ($failed -and [IO.File]::ReadAllText($exe) -eq 'tampered') 'Wrong cached binary is refused, not silently overwritten'
$bad=Join-Path $root 'bad.zip';[IO.File]::WriteAllText($bad,'bad archive')
$failed=$false;try{Ensure-IpaTool -AppRoot (Join-Path $root 'bad-target') -LocalArchive $bad | Out-Null}catch{$failed=$true}
Assert $failed 'Bad archive fails before extraction'
Assert (@(Get-ChildItem -LiteralPath (Join-Path $root 'bad-target') -Recurse -Filter '*.exe').Count -eq 0) 'Bad archive installs no executable'
$failed=$false;try{Ensure-IpaTool -AppRoot (Join-Path $root 'cancelled') -Cancelled {$true} | Out-Null}catch [OperationCanceledException]{$failed=$true}
Assert ($failed -and -not (Test-Path -LiteralPath (Join-Path $root 'cancelled'))) 'Cancellation happens before preparation'
$failed=$false;try{Ensure-IpaTool -AppRoot (Join-Path $root 'network-fail') | Out-Null}catch{$failed=$true}
Assert $failed 'Download failure is returned without success'
Assert (@(Get-ChildItem -LiteralPath (Join-Path $root 'network-fail') -Recurse -Directory | Where-Object Name -like '.install-*').Count -eq 0) 'Failed download leaves no working directory'
Write-Output "$script:checks tool preparation checks passed. No Apple requests."
