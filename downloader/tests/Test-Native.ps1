#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$ExePath,[Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$work=Join-Path ([IO.Path]::GetFullPath($WorkRoot)) ('native-test-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($work)
$exe=Join-Path $work ([IO.Path]::GetFileName($ExePath))
Copy-Item -LiteralPath $ExePath -Destination $exe
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$test=Join-Path $work 'NativeTests.exe'
& $compiler /nologo /target:exe /platform:x64 /codepage:65001 ('/out:'+$test) ('/reference:'+$exe) /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll (Join-Path $PSScriptRoot 'NativeTests.cs')
if($LASTEXITCODE -ne 0){throw 'Native test compilation failed'}
& $compiler /nologo /target:exe /platform:x64 ('/out:'+(Join-Path $work 'ToolFixture.exe')) /reference:System.Web.Extensions.dll (Join-Path $PSScriptRoot 'ToolFixture.cs')
if($LASTEXITCODE -ne 0){throw 'Fixture compilation failed'}
. (Join-Path $root 'Accounts.ps1')
$fixture=Join-Path $work 'fixtures'
$null=[IO.Directory]::CreateDirectory($fixture)
Write-Accounts (Join-Path $fixture 'legacy-accounts.json') @([pscustomobject]@{Id='00000000000000000000000000000001';Email='test@example.invalid';Description='Тест';Password=(Lock-Password 'fixture-only')})
& $test $fixture | Tee-Object -FilePath (Join-Path $work 'test-results.txt')
if($LASTEXITCODE -ne 0){throw 'Native regression tests failed'}
$saved=@(Read-Accounts (Join-Path $fixture 'native-accounts.json'))
if((Unlock-Password $saved[0].Password) -ne 'fixture-secret-1'){throw 'Legacy reader cannot read new account data'}
# An isolated downloaded-file simulation. No production profile, Apple traffic,
# removing zone markers, security configuration changes or embedded script execution.
$uiFolder=Join-Path $work "Папка ' с пробелом"
$null=[IO.Directory]::CreateDirectory($uiFolder)
$uiExe=Join-Path $uiFolder 'TapOk IPA Downloader.exe'
Copy-Item -LiteralPath $exe -Destination $uiExe
Set-Content -LiteralPath $uiExe -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3"
$uiRoot=Join-Path $uiFolder 'profile'
$accounts=Join-Path $uiRoot 'accounts'
$null=[IO.Directory]::CreateDirectory($accounts)
Copy-Item -LiteralPath (Join-Path $fixture 'legacy-accounts.json') -Destination (Join-Path $accounts 'accounts.json')
[IO.File]::WriteAllText((Join-Path $accounts 'download-list.json'),'{"Version":2,"Apps":[{"Id":"101","Name":"Example app","Selected":true}]}')
$before=(Get-FileHash -LiteralPath (Join-Path $accounts 'accounts.json')).Hash
foreach($language in @('en','ru')){
    [IO.File]::WriteAllText((Join-Path $accounts 'language.txt'),$language)
    $si=[Diagnostics.ProcessStartInfo]::new();$si.FileName=$uiExe;$si.UseShellExecute=$false;$si.CreateNoWindow=$true
    $si.Arguments='--smoke-test "'+$uiRoot+'"'
    $process=[Diagnostics.Process]::Start($si)
    if(-not $process.WaitForExit(30000)){$process.Kill();throw 'Native GUI startup timed out'}
    if($process.ExitCode -ne 0){throw ('Native GUI check failed: '+[IO.File]::ReadAllText((Join-Path $uiRoot 'error.txt')))}
    $componentPath=[IO.File]::ReadAllText((Join-Path $uiRoot 'component-path.txt'))
    if([IO.Path]::GetDirectoryName($componentPath) -ne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)){throw 'Component was extracted outside TEMP'}
    if(Test-Path -LiteralPath $componentPath){throw 'Component directory was not cleaned after UI exit'}
    if(Test-Path -LiteralPath (Join-Path $uiRoot 'components')){throw 'Legacy component cache unexpectedly created'}
    $state=Get-Content -LiteralPath (Join-Path $uiRoot 'interface.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($state.Language -ne $language -or -not $state.SwitchVerified -or $state.AccountCount -ne 1 -or $state.AppCount -ne 1){throw 'Native GUI state mismatch'}
    if($state.Output -ne [IO.Path]::GetFullPath((Join-Path $uiRoot 'Downloads/TapOk IPA Downloader'))){throw 'Output path regression'}
    if((Get-FileHash -LiteralPath (Join-Path $accounts 'accounts.json')).Hash -ne $before){throw 'GUI changed account store'}
    Copy-Item -LiteralPath (Join-Path $uiRoot 'interface.png') -Destination (Join-Path $work ('interface-'+$language+'.png'))
    Write-Output ('PASS: standalone Internet-marked EXE, '+$language+' GUI, language switching and unchanged fixture accounts')
}
if((Get-Content -LiteralPath $uiExe -Stream Zone.Identifier -Raw) -notmatch 'ZoneId=3'){throw 'Internet marker was removed'}
Write-Output 'PASS: Internet marker preserved; no PowerShell policy change needed'
Write-Output ('Test reports: '+$work)
