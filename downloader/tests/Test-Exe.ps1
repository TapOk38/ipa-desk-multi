#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$ExePath,[Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference='Stop'
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$work=Join-Path ([IO.Path]::GetFullPath($WorkRoot)) ('exe-test-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$script:checks=0
function Assert($Value,[string]$Message){if(-not $Value){throw "FAIL: $Message"};$script:checks++;Write-Output "PASS: $Message"}
# Exercise Windows quoting, non-ASCII paths, spaces and apostrophes without using a shell.
$folder=Join-Path $work "Тестовая папка ' один EXE"
$null=[IO.Directory]::CreateDirectory($folder)
$exe=Join-Path $folder 'TapOk IPA Downloader.exe'
Copy-Item -LiteralPath $ExePath -Destination $exe
$testRoot=Join-Path $folder 'Профиль проверки'
$data=Join-Path $testRoot 'accounts'
$null=[IO.Directory]::CreateDirectory($data)
. (Join-Path $sourceRoot 'DownloadList.ps1')
Save-DownloadList (Join-Path $data 'download-list.json') "101`n202"
Set-IpaLanguage 'ru'
$accountsPath=Join-Path $data 'accounts.json'
Write-Accounts $accountsPath @([pscustomobject]@{Id='00000000000000000000000000000001';Email='test@example.invalid';Description='Тест';Password=(Lock-Password 'fixture-only')})
$accountHash=(Get-FileHash -LiteralPath $accountsPath -Algorithm SHA256).Hash
function Run-Smoke {
    $languagePath=Join-Path $data 'language.txt'
    $language=if(Test-Path -LiteralPath $languagePath){[IO.File]::ReadAllText($languagePath).Trim()}else{'en'}
    $process=Start-Process -FilePath $exe -ArgumentList @('--smoke-test',('"'+$testRoot+'"')) -WindowStyle Hidden -PassThru
    if(-not $process.WaitForExit(90000)){$process.Kill();throw 'Launcher smoke test timeout'}
    Assert ($process.ExitCode -eq 0) 'Single EXE opens and closes the actual WinForms window'
    Assert (Test-Path -LiteralPath (Join-Path $testRoot 'interface.png')) 'UI screenshot generated'
    $state=Get-Content -LiteralPath (Join-Path $testRoot 'interface.png.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($state.Language -eq $language -and $state.Download -ceq $(if($language -eq 'ru'){'Скачать IPA'}else{'Download IPA'})) 'Actual UI respects the saved language or defaults to English'
    Assert ($state.SwitchVerified -and $state.LanguageDisabledWhileBusy) 'Live switching updates controls and is disabled during work'
    Assert ($state.AppEditorVerified) 'App editor supports adding, editing, saving selections and deleting'
    Assert ($state.PurchasePickerVerified -and $state.AppList -eq "101`r`n202`r`n303") 'Purchase picker preserves filtered selections and merges with the saved list without duplicates'
    Assert ((Get-FileHash -LiteralPath $accountsPath -Algorithm SHA256).Hash -eq $accountHash) 'Existing account store is preserved'
}
Run-Smoke
Assert ([IO.File]::ReadAllText((Join-Path $testRoot 'smoke-result.txt')).Contains(('Output: '+(Join-Path $testRoot 'Downloads/TapOk IPA Downloader')))) 'Launcher uses the branded Downloads folder'
Save-IpaLanguage $data 'ru'
Run-Smoke
$runtime=@(Get-ChildItem -LiteralPath (Join-Path $testRoot 'app') -Directory)[0].FullName
Assert ((Get-ChildItem -LiteralPath $folder -File).Count -eq 1) 'Launch directory needs only the EXE'
$expected=@('IPA-Desk.ps1','DownloadList.ps1','AppListUI.ps1','licenses/ipatool-cpp-MIT.txt','Purchases.ps1','Accounts.ps1','Engine.ps1','Metadata.ps1','Metadata.cs','Install-Tools.ps1','Localization.ps1','PRIVACY.md','THIRD_PARTY.md','LICENSE','licenses/ipatool-MIT.txt')
foreach($name in $expected){
    Assert ((Get-FileHash -LiteralPath (Join-Path $runtime $name) -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath (Join-Path $sourceRoot $name) -Algorithm SHA256).Hash) "Embedded file matches source: $name"
}
Assert ((@(Get-ChildItem -LiteralPath $runtime -Recurse -File).Count) -eq ($expected.Count+1)) 'Payload contains only the allowed files and extraction lock'
$ui=Get-Content -LiteralPath (Join-Path $runtime 'IPA-Desk.ps1') -Raw
Assert ($ui.Contains("Join-Path (Join-Path `$script:OutputRoot `$id)")) 'Downloads use the requested output directory'
[IO.File]::WriteAllText((Join-Path $runtime 'IPA-Desk.ps1'),'throw "damaged cached script must not run"')
Run-Smoke
Assert ((Get-FileHash -LiteralPath (Join-Path $runtime 'IPA-Desk.ps1') -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath (Join-Path $sourceRoot 'IPA-Desk.ps1') -Algorithm SHA256).Hash) 'Modified cache is restored from embedded payload before execution'
Copy-Item -LiteralPath (Join-Path $testRoot 'interface.png') -Destination (Join-Path $testRoot 'interface-ru.png')
Save-IpaLanguage $data 'en'
Run-Smoke
Assert ([IO.File]::ReadAllText((Join-Path $data 'language.txt')).Trim() -eq 'en') 'Saved English language survives an EXE restart'
Copy-Item -LiteralPath (Join-Path $testRoot 'interface.png') -Destination (Join-Path $testRoot 'interface-en.png')
$bytes=[IO.File]::ReadAllBytes($exe);$pe=[BitConverter]::ToInt32($bytes,60)
Assert ([BitConverter]::ToUInt16($bytes,$pe+4) -eq 0x8664) 'Executable targets Windows x64'
Assert ([BitConverter]::ToUInt16($bytes,$pe+24+68) -eq 2) 'Windows GUI subsystem: no console window'
Write-Output ("EXE checks passed: "+$script:checks)
Write-Output ("Screenshot: "+(Join-Path $testRoot 'interface.png'))
