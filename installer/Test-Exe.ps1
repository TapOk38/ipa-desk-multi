#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$ExePath,[Parameter(Mandatory=$true)][string]$TestRoot)
$ErrorActionPreference='Stop'
$TestRoot=[IO.Path]::GetFullPath($TestRoot)
$folder=Join-Path $TestRoot 'Тест [1]'
$null=[IO.Directory]::CreateDirectory($folder)
$exe=Join-Path $folder 'IPA Install.exe'
Copy-Item -LiteralPath $ExePath -Destination $exe
$profile=Join-Path $TestRoot 'profile'
$script:checks=0
function Assert($value,[string]$message){if(-not $value){throw "FAIL: $message"};$script:checks++;Write-Output "PASS: $message"}
function Smoke {
    $p=Start-Process -FilePath $exe -ArgumentList @('--smoke-test',('"'+$profile+'"')) -WindowStyle Hidden -PassThru
    if(-not $p.WaitForExit(90000)){$p.Kill();throw 'Smoke timeout'}
    Assert ($p.ExitCode -eq 0) 'Single EXE opens the installer UI from a Unicode path'
    Assert (Test-Path -LiteralPath (Join-Path $profile 'interface.png')) 'Window rendered successfully'
}
Smoke
$runtime=@(Get-ChildItem -LiteralPath (Join-Path $profile 'app') -Directory)[0].FullName
Assert ((@(Get-ChildItem -LiteralPath $folder -File).Count) -eq 1) 'No adjacent scripts or DLLs are required'
foreach($name in @('IPA-Install.ps1','Engine.ps1','Credentials.ps1','AccountWindows.ps1','Localization.ps1')){
    Assert ((Get-FileHash -LiteralPath (Join-Path $runtime $name)).Hash -eq (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash) "Embedded script matches source: $name"
}
foreach($line in [IO.File]::ReadAllLines((Join-Path $runtime 'tools/SHA256SUMS.txt'))){
    if($line -notmatch '^([a-fA-F0-9]{64})\s+(.+)$'){throw 'Invalid checksum line'}
    Assert ((Get-FileHash -LiteralPath (Join-Path $runtime ('tools/'+$Matches[2]))).Hash -eq $Matches[1]) 'Bundled USB component hash matches'
}
foreach($tool in @('idevice_id','ideviceinfo','ideviceinstaller','idevicepair','plistutil')){
    $start=[Diagnostics.ProcessStartInfo]::new((Join-Path $runtime ('tools/'+$tool+'.exe')),'--help')
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $p=[Diagnostics.Process]::Start($start)
    $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
    if(-not $p.WaitForExit(15000)){$p.Kill();throw 'Tool help timeout'}
    $null=$stdout.GetAwaiter().GetResult();$null=$stderr.GetAwaiter().GetResult()
    Assert ($p.ExitCode -eq 0) "USB tool and DLLs load: $tool"
    $p.Dispose()
}
$sensitive=@(Get-ChildItem -LiteralPath $runtime -Recurse -File | Where-Object {$_.Extension -in @('.ipa','.log','.jsonl') -or $_.Name -in @('accounts.dat','accounts.json')})
Assert ($sensitive.Count -eq 0) 'No IPA, account files or journals in the payload'
Assert (Test-Path -LiteralPath (Join-Path $runtime 'tools/licenses/ideviceinstaller/COPYING')) 'Dependency licence included'
Assert (Test-Path -LiteralPath (Join-Path $runtime 'tools/sources')) 'Corresponding dependency sources included'
[IO.File]::WriteAllText((Join-Path $runtime 'Engine.ps1'),'throw "Corrupted cache must not execute"')
Smoke
Assert ((Get-FileHash -LiteralPath (Join-Path $runtime 'Engine.ps1')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'Engine.ps1')).Hash) 'Corrupted cache repaired before execution'
$bytes=[IO.File]::ReadAllBytes($exe);$pe=[BitConverter]::ToInt32($bytes,60)
Assert ([BitConverter]::ToUInt16($bytes,$pe+24+68) -eq 2) 'GUI executable without a console'
Write-Output "$script:checks EXE checks passed"
Write-Output (Join-Path $profile 'interface.png')
