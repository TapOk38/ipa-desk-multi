#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$ExePath,[Parameter(Mandatory=$true)][string]$TestRoot)
$ErrorActionPreference='Stop'
$ExePath=[IO.Path]::GetFullPath($ExePath)
$package=[IO.Path]::GetDirectoryName($ExePath)
$TestRoot=[IO.Path]::GetFullPath($TestRoot)
$null=[IO.Directory]::CreateDirectory($TestRoot)
$script:checks=0
function Assert($value,[string]$message){if(-not $value){throw "FAIL: $message"};$script:checks++;Write-Output "PASS: $message"}
$assembly=[Reflection.Assembly]::LoadFile($ExePath)
Assert (($assembly.GetManifestResourceNames() -join ',') -eq 'TapOk.USB.Components.zip') 'Only declared USB archive embedded'
$bundle=$assembly.GetType('TapOk.Installer.RuntimeBundle').GetMethod('Open').Invoke($null,@())
$package=$bundle.Root
try {
Assert (@($assembly.GetReferencedAssemblies() | Where-Object {$_.Name -match 'PowerShell|Automation'}).Count -eq 0) 'No PowerShell runtime'
$flags=[Reflection.BindingFlags]'NonPublic,Static'
$compiledHashes=$assembly.GetType('TapOk.Installer.PinnedTools').GetField('Hashes',$flags).GetValue($null)
$toolRoot=Join-Path $package 'tools'
$pinCount=0
foreach($line in [IO.File]::ReadAllLines((Join-Path $toolRoot 'SHA256SUMS.txt'))){
    if($line -notmatch '^([a-fA-F0-9]{64})\s+([a-zA-Z0-9_.-]+\.(?:exe|dll))$'){throw 'Invalid component manifest'}
    $expected=$Matches[1];$name=$Matches[2];$pinCount++
    Assert ((Get-FileHash -LiteralPath (Join-Path $toolRoot $name)).Hash -eq $expected) "Component matches pinned hash: $name"
    Assert ($compiledHashes[$name] -eq $expected) "Compiled manifest matches: $name"
}
Assert ($pinCount -eq $compiledHashes.Count) 'All compiled component hashes accounted for'
foreach($tool in @('idevice_id','ideviceinfo','ideviceinstaller','idevicepair','plistutil')){
    # Help only: no device enumeration, pairing, installation or account use.
    $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $toolRoot ($tool+'.exe')),'--help')
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.EnvironmentVariables['PATH']=$toolRoot+';'+[Environment]::GetFolderPath([Environment+SpecialFolder]::System)
    $p=[Diagnostics.Process]::Start($start)
    try{
        $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit(15000)){$p.Kill();throw 'Tool help timeout'}
        $null=$stdout.GetAwaiter().GetResult();$null=$stderr.GetAwaiter().GetResult()
        Assert ($p.ExitCode -eq 0) "USB executable and libraries load: $tool --help"
    }finally{$p.Dispose()}
}
$files=@(Get-ChildItem -LiteralPath $package -Recurse -File)
$sensitive=@($files | Where-Object {$_.Extension -in @('.ipa','.log','.jsonl','.ps1','.pfx','.key') -or $_.Name -in @('accounts.dat','accounts.json')})
Assert ($sensitive.Count -eq 0) 'No accounts, IPA, logs, scripts or signing keys in package'
Assert (Test-Path -LiteralPath (Join-Path $toolRoot 'licenses/ideviceinstaller/COPYING')) 'Dependency license included'
Assert (@(Get-ChildItem -LiteralPath (Join-Path $toolRoot 'sources') -File).Count -gt 0) 'Corresponding dependency sources included'
$bytes=[IO.File]::ReadAllBytes($ExePath);$pe=[BitConverter]::ToInt32($bytes,60)
Assert ([BitConverter]::ToUInt16($bytes,$pe+24+68) -eq 2) 'GUI executable without a console'
[IO.File]::WriteAllText((Join-Path $TestRoot 'package-result.txt'),"$script:checks package checks passed; --help only, no USB or account operations.")
Write-Output "$script:checks package checks passed"} finally {$bundle.Dispose()}
Assert (-not (Test-Path -LiteralPath $package)) 'Temporary bundle removed after normal disposal'