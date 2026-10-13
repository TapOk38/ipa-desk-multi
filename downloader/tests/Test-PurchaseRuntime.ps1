#requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../Engine.ps1')
Set-IpaLanguage 'en'
$script:checks=0
function Assert($value,$message){if(-not $value){throw "FAIL: $message"};$script:checks++;Write-Output "PASS: $message"}
$script:Options=@{AppRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));Passphrase='fixture'}
$script:SessionEnvironment=@{USERPROFILE='isolated-profile';XDG_STATE_HOME='isolated-state';LOCALAPPDATA='empty-cache'}
$script:Bus=@{Cancel=$false}
$script:NativeWorkDirectory=$script:Options.AppRoot
$script:Secrets=[Collections.Generic.List[string]]::new()
function Receive-PinnedTool {throw 'Unexpected network request'}
$cpp=Ensure-IpaTool $script:Options.AppRoot
Assert ([IO.File]::Exists($cpp)) 'Bundled pinned C++ tool resolves without any network download'
$script:CppExe=$cpp
Assert ((Get-IpaToolSpec).Version -eq '1.1.6') 'History uses the pinned commerce-capable C++ version'
$envForChild=Get-ChildEnvironment
Assert ($envForChild.LOCALAPPDATA -eq 'empty-cache') 'History does not need the separate Go runtime cache'
Assert ($envForChild.USERPROFILE -eq 'isolated-profile' -and $envForChild.XDG_STATE_HOME -eq 'isolated-state') 'Runtime cache does not replace the isolated credential profile'
$watch=[Diagnostics.Stopwatch]::StartNew(); $timedOut=$false
try{Invoke-Native (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') @('-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 15') 1 | Out-Null}
catch [TimeoutException]{$timedOut=$true}
Assert ($timedOut -and $watch.Elapsed.TotalSeconds -lt 6) 'Native timeout terminates a stalled child process'
function Invoke-Native($Executable,$Arguments,$TimeoutSeconds,$ProcessEnvironment,$WorkingDirectory){
    $script:CapturedTimeout=$TimeoutSeconds
    $script:CapturedExecutable=$Executable
    $script:CapturedArguments=$Arguments
    throw [TimeoutException]::new('fixture timeout')
}
$message=''
try{Invoke-PurchaseTool @('list-purchases')}catch{$message=$_.Exception.Message}
Assert ($script:CapturedTimeout -eq 90 -and $message -like 'Purchase history: no response within 90 seconds*') 'History request has a 90-second limit and a specific user-facing error'
Assert ($script:CapturedExecutable -eq $cpp -and $script:CapturedArguments -contains 'list-purchases' -and $script:CapturedArguments -notcontains '--non-interactive') 'History uses the same C++ session and supported flags'
Write-Output "$script:checks purchase runtime checks passed"
