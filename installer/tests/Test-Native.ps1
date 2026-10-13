#requires -Version 5.1
param([string]$ExePath,[string]$WorkRoot=(Join-Path $env:TEMP 'TapOk-Installer-tests'))
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetFullPath($WorkRoot)) ('native-installer-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($root)
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not $ExePath){
    # Offline CI uses an empty, hashed ZIP; only smoke mode opens this test UI.
    $ExePath=Join-Path $root 'TapOk-IPA-Installer-Windows.exe'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $payload=Join-Path $root 'empty-components.zip'
    $emptyZip=[IO.Compression.ZipFile]::Open($payload,[IO.Compression.ZipArchiveMode]::Create)
    $emptyZip.Dispose()
    $payloadHash=(Get-FileHash -LiteralPath $payload).Hash
    $manifest=Join-Path $root 'PinnedTools.cs'
    [IO.File]::WriteAllText($manifest,'using System.Collections.Generic; namespace TapOk.Installer { internal static class PinnedTools { internal const string PayloadSha256="'+$payloadHash+'"; internal static readonly Dictionary<string,string> Hashes=new Dictionary<string,string>(); }}')
    $sources=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '../native') -Filter '*.cs' | ForEach-Object FullName)+@((Join-Path $PSScriptRoot '../../downloader/Metadata.cs'),$manifest)
    & $compiler /nologo /target:winexe /platform:x64 /codepage:65001 "/out:$ExePath" "/resource:$payload,TapOk.USB.Components.zip" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Security.dll /reference:System.Web.Extensions.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll @sources
    if($LASTEXITCODE -ne 0){throw 'Test UI compilation failed'}
} else {
    $ExePath=[IO.Path]::GetFullPath($ExePath)
    $copy=Join-Path $root ([IO.Path]::GetFileName($ExePath))
    [IO.File]::Copy($ExePath,$copy,$false)
    $ExePath=$copy
}
$fakeRoot=Join-Path $root 'fake tools with spaces'
$null=[IO.Directory]::CreateDirectory($fakeRoot)
$fake=Join-Path $root 'fake.exe'
& $compiler /nologo /target:exe /codepage:65001 "/out:$fake" /reference:System.Web.Extensions.dll (Join-Path $PSScriptRoot 'FakeDeviceTools.cs')
if($LASTEXITCODE -ne 0){throw 'Fixture compilation failed'}
foreach($name in @('idevice_id','ideviceinfo','idevicepair','ideviceinstaller','plistutil')){[IO.File]::Copy($fake,(Join-Path $fakeRoot ($name+'.exe')),$false)}
$tests=Join-Path $root 'NativeTests.exe'
& $compiler /nologo /target:exe /codepage:65001 "/out:$tests" "/reference:$ExePath" /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll (Join-Path $PSScriptRoot 'NativeTests.cs')
if($LASTEXITCODE -ne 0){throw 'Test compilation failed'}
$cases=Join-Path $root 'cases'
$null=[IO.Directory]::CreateDirectory($cases)
# Synthetic credentials only: test compatibility with the legacy DPAPI format.
. (Join-Path $PSScriptRoot '../Credentials.ps1')
Set-InstallerCredential -Key 'icloud:default' -AppleId 'legacy@example.invalid' -Password 'legacy fixture password' -StorePath (Join-Path $cases 'legacy.dat')
Set-InstallerCredential -Key 'legacy-key' -AppleId 'old@example.invalid' -Password 'old fixture password' -StorePath (Join-Path $cases 'legacy.dat')
& $tests $cases $fakeRoot
if($LASTEXITCODE -ne 0){throw 'Native workflow tests failed'}
$entry=Get-InstallerCredential -Key 'icloud:default' -StorePath (Join-Path $cases 'legacy.dat')
if($entry.AppleId -ne 'native@example.invalid' -or $entry.Password -ne 'native fixture password'){throw 'Native-to-legacy credential compatibility failed'}
Write-Output 'PASS: native credential output is readable by the old version'
$assembly=[Reflection.Assembly]::LoadFile($ExePath)
if(($assembly.GetManifestResourceNames() -join ',') -ne 'TapOk.USB.Components.zip'){throw 'Unexpected embedded resources'}
if(@($assembly.GetReferencedAssemblies() | Where-Object {$_.Name -match 'Automation|PowerShell'}).Count -gt 0){throw 'Unexpected PowerShell reference'}
# Preserve an Internet zone marker during both GUI runs. Never unblock or change Defender settings.
[IO.File]::WriteAllText(($ExePath+':Zone.Identifier'),"[ZoneTransfer]`r`nZoneId=3`r`n")
foreach($language in @('en','ru')){
    $profile=Join-Path $root ('smoke-'+$language)
    $null=[IO.Directory]::CreateDirectory($profile)
    if($language -eq 'ru'){[IO.File]::WriteAllText((Join-Path $profile 'language.txt'),'ru')}
    $start=[Diagnostics.ProcessStartInfo]::new($ExePath,('--smoke-test "'+$profile+'"'))
    $start.UseShellExecute=$false
    $process=[Diagnostics.Process]::Start($start)
    try{if(-not $process.WaitForExit(30000)){$process.Kill();throw 'GUI smoke test timed out'};if($process.ExitCode -ne 0){throw 'GUI smoke test failed'}}finally{$process.Dispose()}
    $report=Join-Path $profile ('smoke-'+$language+'.txt')
    if(-not (Test-Path -LiteralPath $report)){throw 'Missing GUI result'}
    if(Test-Path -LiteralPath (Join-Path $profile 'accounts.dat')){throw 'Smoke mode unexpectedly wrote credentials'}
    $runtime=[IO.File]::ReadAllText((Join-Path $profile 'runtime-path.txt'))
    if(-not $runtime.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Runtime escaped TEMP'}
    if(Test-Path -LiteralPath $runtime){throw 'Runtime not removed after normal exit'}
    Write-Output "PASS: $language GUI, Internet marker, TEMP-only extraction, cleanup, no USB calls"
}
if(-not ([IO.File]::ReadAllText($ExePath+':Zone.Identifier').Contains('ZoneId=3'))){throw 'Internet marker changed'}
Write-Output "Results: $root"