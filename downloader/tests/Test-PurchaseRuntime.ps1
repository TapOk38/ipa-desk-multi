#requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../Engine.ps1')
Set-IpaLanguage 'en'
$script:checks=0
function Assert($value,$message){if(-not $value){throw "FAIL: $message"};$script:checks++;Write-Output "PASS: $message"}
$script:Options=@{AppRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));Passphrase='fixture'}
$script:SessionEnvironment=@{USERPROFILE='isolated-profile';XDG_STATE_HOME='isolated-state';LOCALAPPDATA='empty-cache'}
$script:Bus=@{Cancel=$false;Events=[Collections.Concurrent.ConcurrentQueue[object]]::new()}
$script:NativeWorkDirectory=$script:Options.AppRoot
$script:Secrets=[Collections.Generic.List[string]]::new()
function Receive-PinnedTool {throw 'Unexpected network request'}
$cpp=Ensure-IpaTool $script:Options.AppRoot
Assert ([IO.File]::Exists($cpp)) 'Previously prepared pinned C++ tool resolves without any network download'
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
$script:Options.ComponentRoot=Join-Path $script:Options.AppRoot 'fixture-components'
function Ensure-IpaTool($AppRoot,$LocalArchive,[scriptblock]$Cancelled){
    if(& $Cancelled){throw [OperationCanceledException]::new('fixture cancellation')}
    return (Join-Path $AppRoot 'tools/cpp-1.1.6/ipatool-cpp.exe')
}
$first=Resolve-CppTool
$script:Options.AppRoot=Join-Path $script:Options.AppRoot 'different-app-version'
$second=Resolve-CppTool
Assert ($first -eq $second -and $first.StartsWith($script:Options.ComponentRoot)) 'Component cache persists when the application version directory changes'
$script:Bus.Cancel=$true;$cancelled=$false
try{Resolve-CppTool | Out-Null}catch [OperationCanceledException]{$cancelled=$true}
Assert $cancelled 'Component preparation still forwards cancellation'
Write-Output "$script:checks purchase runtime checks passed"
