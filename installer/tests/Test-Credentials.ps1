#requires -Version 5.1
param(
    [string]$ModulePath = (Join-Path $PSScriptRoot '../../outputs/IPA-Install/Credentials.ps1'),
    [string]$TestRoot = (Join-Path $PSScriptRoot ('credentials-' + [guid]::NewGuid().ToString('N'))),
    [switch]$MockProtection
)
$ErrorActionPreference = 'Stop'
$ModulePath = [IO.Path]::GetFullPath($ModulePath)
$TestRoot = [IO.Path]::GetFullPath($TestRoot)
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd('\') + '\'
if (-not $TestRoot.StartsWith($workspace, [StringComparison]::OrdinalIgnoreCase)) { throw 'TestRoot must be inside the workspace.' }
$null = [IO.Directory]::CreateDirectory($TestRoot)
$store = Join-Path $TestRoot 'data/accounts.dat'
$shim = Join-Path $PSScriptRoot 'CredentialProtection-TestDouble.ps1'
. $ModulePath
$script:Checks = 0
function Assert($Condition, [string]$Description) {
    if (-not $Condition) { throw ('FAIL: ' + $Description) }
    $script:Checks++
    Write-Output ('PASS: ' + $Description)
}
function Capture-Failure([scriptblock]$Action) {
    try { & $Action | Out-Null } catch { return $_.Exception.Message }
    throw 'Expected operation to fail'
}
$realDpapiWorks = $false
try {
    $probe = Protect-InstallerCredentialBytes ([Text.Encoding]::UTF8.GetBytes('fixture'))
    $decoded = Unprotect-InstallerCredentialBytes $probe
    $realDpapiWorks = [Text.Encoding]::UTF8.GetString($decoded) -ceq 'fixture'
} catch { }
if (-not $realDpapiWorks) {
    $realStore = Join-Path $TestRoot 'real-dpapi/accounts.dat'
    $failure = Capture-Failure { Set-InstallerCredential -Key 'real-probe' -AppleId 'probe@example.invalid' -Password 'probe secret' -StorePath $realStore }
    Assert ($failure -eq 'Не удалось сохранить учётные данные.') 'Unavailable real DPAPI gives a short error without fallback'
    Assert (-not [IO.File]::Exists($realStore)) 'Unavailable real DPAPI creates no unprotected credential store'
    if (-not $MockProtection) { throw 'DPAPI is unavailable in this sandbox. Use -MockProtection only to test storage behavior.' }
}
$testKey = New-Object byte[] 32
if ($MockProtection) {
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($testKey) } finally { $rng.Dispose() }
    . $shim -TestKey $testKey
}
$keyA = 'sha256:fixture-a'
$keyB = 'sha256:fixture-b'
$appleA = 'first.account@example.invalid'
$passwordA = ' A! пароль & "quote" tail\ '
$appleB = 'second.account@example.invalid'
$passwordB = 'B-pass! 123'
Assert ($null -eq (Get-InstallerCredential -Key $keyA -StorePath $store)) 'Missing store returns no credential'
Assert (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($store))) 'Reading missing store does not create storage files'
$setOutput = @(Set-InstallerCredential -Key $keyA -AppleId ('  ' + $appleA + ' ') -Password $passwordA -StorePath $store)
Assert ($setOutput.Count -eq 0 -and [IO.File]::Exists($store)) 'Saving creates encrypted store without output'
$credential = Get-InstallerCredential -Key $keyA -StorePath $store
Assert ($credential.AppleId -ceq $appleA -and $credential.Password -ceq $passwordA) 'Saved login is trimmed and password including Unicode and whitespace is preserved'
Assert (@($credential.PSObject.Properties).Count -eq 2) 'Lookup returns only AppleId and Password'
Assert ($null -eq (Get-InstallerCredential -Key 'missing-key' -StorePath $store)) 'Missing IPA key returns no credential'
Assert ($null -eq (Get-InstallerCredential -Key $keyA.ToUpperInvariant() -StorePath $store)) 'IPA identity comparison is ordinal and case-sensitive'
Set-InstallerCredential -Key $keyB -AppleId $appleB -Password $passwordB -StorePath $store
$firstRead = Get-InstallerCredential -Key $keyA -StorePath $store
$secondRead = Get-InstallerCredential -Key $keyB -StorePath $store
Assert ($firstRead.Password -ceq $passwordA -and $secondRead.Password -ceq $passwordB) 'Different IPA identities keep separate credentials'
$runner = [PowerShell]::Create()
try {
    $null = $runner.AddScript('param($Module,$Shim,$UseMock,$TestKey,$Key,$Store); . $Module; if ($UseMock) { . $Shim -TestKey $TestKey }; Get-InstallerCredential -Key $Key -StorePath $Store').AddArgument($ModulePath).AddArgument($shim).AddArgument([bool]$MockProtection).AddArgument($testKey).AddArgument($keyA).AddArgument($store)
    $reopened = @($runner.Invoke())
    Assert (-not $runner.HadErrors -and $reopened.Count -eq 1 -and $reopened[0].Password -ceq $passwordA) 'Credentials can be read by a fresh module instance'
} finally { $runner.Dispose() }
$editedPassword = 'Changed ! password'
Set-InstallerCredential -Key $keyA -AppleId $appleA -Password $editedPassword -StorePath $store
Assert ((Get-InstallerCredential -Key $keyA -StorePath $store).Password -ceq $editedPassword) 'Editing replaces credentials for the same IPA'
Assert ((Get-InstallerCredential -Key $keyB -StorePath $store).Password -ceq $passwordB) 'Editing one IPA preserves the other record'
$fileText = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($store))
Assert (-not $fileText.Contains($appleA) -and -not $fileText.Contains($appleB) -and -not $fileText.Contains($passwordA) -and -not $fileText.Contains($passwordB) -and -not $fileText.Contains($editedPassword) -and -not $fileText.Contains($keyA)) 'Store contains no plaintext login, password or IPA identity'
Assert (@(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($store)) -File -Force).Count -eq 1) 'Atomic replacement leaves no backup or temporary files'
$beforeInvalid = (Get-FileHash -LiteralPath $store -Algorithm SHA256).Hash
$originalAttributes = [IO.File]::GetAttributes($store)
try {
    [IO.File]::SetAttributes($store, $originalAttributes -bor [IO.FileAttributes]::ReadOnly)
    $writeFailure = Capture-Failure { Set-InstallerCredential -Key $keyA -AppleId $appleA -Password 'should not be saved' -StorePath $store }
    Assert ($writeFailure -eq 'Не удалось сохранить учётные данные.' -and (Get-FileHash -LiteralPath $store -Algorithm SHA256).Hash -eq $beforeInvalid) 'Failed atomic replacement preserves existing encrypted store'
    Assert (@(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($store)) -File -Force).Count -eq 1) 'Failed write removes its encrypted temporary file'
} finally { [IO.File]::SetAttributes($store, $originalAttributes) }
$emptyError = Capture-Failure { Set-InstallerCredential -Key $keyA -AppleId $appleA -Password '' -StorePath $store }
Assert ($emptyError -eq 'Не удалось сохранить учётные данные.' -and (Get-FileHash -LiteralPath $store -Algorithm SHA256).Hash -eq $beforeInvalid) 'Invalid update leaves existing store intact and reveals no account details'
$corrupt = Join-Path $TestRoot 'corrupt.dat'
[IO.File]::WriteAllText($corrupt, 'not a credential store')
$corruptHash = (Get-FileHash -LiteralPath $corrupt -Algorithm SHA256).Hash
$readError = Capture-Failure { Get-InstallerCredential -Key $keyA -StorePath $corrupt }
$saveError = Capture-Failure { Set-InstallerCredential -Key $keyA -AppleId $appleA -Password $passwordA -StorePath $corrupt }
Assert ($readError -eq 'Не удалось прочитать сохранённые учётные данные.' -and $saveError -eq 'Не удалось сохранить учётные данные.') 'Corrupt storage errors are short and contain no credentials'
Assert ((Get-FileHash -LiteralPath $corrupt -Algorithm SHA256).Hash -eq $corruptHash) 'Corrupt storage is not overwritten by an update'
$originalUnprotect = ${function:Unprotect-InstallerCredentialBytes}
try {
    function Unprotect-InstallerCredentialBytes([byte[]]$Bytes) { throw [Security.Cryptography.CryptographicException]::new('Cannot decrypt for this Windows user') }
    $wrongUserRead = Capture-Failure { Get-InstallerCredential -Key $keyA -StorePath $store }
    $wrongUserWrite = Capture-Failure { Set-InstallerCredential -Key $keyA -AppleId $appleA -Password $passwordA -StorePath $store }
    Assert ($wrongUserRead -eq 'Не удалось прочитать сохранённые учётные данные.' -and $wrongUserWrite -eq 'Не удалось сохранить учётные данные.') 'Protection failure does not expose native exception or credentials'
    Assert ((Get-FileHash -LiteralPath $store -Algorithm SHA256).Hash -eq $beforeInvalid) 'Undecryptable storage is preserved'
} finally { ${function:Unprotect-InstallerCredentialBytes} = $originalUnprotect }
Remove-InstallerCredential -Key $keyA -StorePath $store
Assert ($null -eq (Get-InstallerCredential -Key $keyA -StorePath $store) -and (Get-InstallerCredential -Key $keyB -StorePath $store).Password -ceq $passwordB) 'Removal deletes only the selected IPA record'
Remove-InstallerCredential -Key $keyB -StorePath $store
Assert ($null -eq (Get-InstallerCredential -Key $keyB -StorePath $store)) 'Removing the final credential leaves readable empty storage'
Remove-InstallerCredential -Key 'missing-key' -StorePath (Join-Path $TestRoot 'never-created/accounts.dat')
Assert (-not [IO.Directory]::Exists((Join-Path $TestRoot 'never-created'))) 'Removing missing credentials creates no storage files'
$parallelRunners = @()
$parallelHandles = @()
$parallelStore = Join-Path $TestRoot 'concurrent/accounts.dat'
try {
    foreach ($parallelKey in @('parallel-a','parallel-b')) {
        $parallelRunner = [PowerShell]::Create()
        $null = $parallelRunner.AddScript('param($Module,$Shim,$UseMock,$TestKey,$Key,$Store); . $Module; if ($UseMock) { . $Shim -TestKey $TestKey }; Set-InstallerCredential -Key $Key -AppleId "parallel@example.invalid" -Password "test fixture" -StorePath $Store').AddArgument($ModulePath).AddArgument($shim).AddArgument([bool]$MockProtection).AddArgument($testKey).AddArgument($parallelKey).AddArgument($parallelStore)
        $parallelRunners += $parallelRunner
        $parallelHandles += $parallelRunner.BeginInvoke()
    }
    for ($i = 0; $i -lt $parallelRunners.Count; $i++) {
        $null = $parallelRunners[$i].EndInvoke($parallelHandles[$i])
        Assert (-not $parallelRunners[$i].HadErrors) 'Concurrent credential writer completes without error'
    }
    Assert ($null -ne (Get-InstallerCredential -Key 'parallel-a' -StorePath $parallelStore) -and $null -ne (Get-InstallerCredential -Key 'parallel-b' -StorePath $parallelStore)) 'Concurrent writes retain both IPA records'
} finally { foreach ($parallelRunner in $parallelRunners) { $parallelRunner.Dispose() } }
if ($MockProtection) { Write-Output 'NOTE: Storage tests used an explicit AES test double. They do not validate real Windows DPAPI or other-user DPAPI behavior.' }
Write-Output ("All $script:Checks credential checks passed. Test artifacts: $TestRoot")
