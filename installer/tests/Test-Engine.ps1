#requires -Version 5.1
param(
    [string]$AppRoot = (Join-Path $PSScriptRoot '../../outputs/IPA-Install'),
    [string]$TestRoot = (Join-Path $PSScriptRoot ('run-' + [guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
# A sandbox can supply both Path and PATH; normalize this test process only.
$environment = [Environment]::GetEnvironmentVariables()
$pathNames = @($environment.Keys | Where-Object { $_ -ieq 'PATH' })
if ($pathNames.Count -gt 1) {
    $testPath = $environment[$pathNames[0]]
    foreach ($key in $pathNames) { [Environment]::SetEnvironmentVariable($key, $null, 'Process') }
    [Environment]::SetEnvironmentVariable('Path', $testPath, 'Process')
}
$AppRoot = [IO.Path]::GetFullPath($AppRoot)
$TestRoot = [IO.Path]::GetFullPath($TestRoot)
$null = [IO.Directory]::CreateDirectory($TestRoot)
$toolRoot = Join-Path $TestRoot 'fake tools with spaces'
$null = [IO.Directory]::CreateDirectory($toolRoot)
$fakeExe = Join-Path $toolRoot 'fake.exe'
Add-Type -Path (Join-Path $PSScriptRoot 'FakeDeviceTools.cs') -OutputAssembly $fakeExe -OutputType ConsoleApplication -ReferencedAssemblies 'System.Web.Extensions.dll'
foreach ($tool in @('idevice_id','idevicepair','ideviceinfo','ideviceinstaller','plistutil')) {
    [IO.File]::Copy($fakeExe, (Join-Path $toolRoot ($tool + '.exe')), $true)
}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$fixtureDir = Join-Path $TestRoot 'IPA с пробелами & знаком'
$null = [IO.Directory]::CreateDirectory($fixtureDir)
$goodIpa = Join-Path $fixtureDir 'Тестовое приложение & файл.ipa'
$badIpa = Join-Path $fixtureDir 'bad.ipa'
$nonZip = Join-Path $fixtureDir 'text.ipa'
$minimumIpa = Join-Path $fixtureDir 'requires16.10.ipa'
$microIpa = Join-Path $fixtureDir 'requires16.10.2.ipa'
$invalidMinimumIpa = Join-Path $fixtureDir 'invalid-minimum.ipa'
$anotherAccountIpa = Join-Path $fixtureDir 'same-app-other-content.ipa'
$plist = '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.example.fixture</string><key>CFBundleDisplayName</key><string>Тестовое приложение</string><key>CFBundleName</key><string>Fixture</string><key>CFBundleExecutable</key><string>Fixture</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0</string></dict></plist>'
function Write-Ipa([string]$Path, [string]$Entry, [string]$Content) {
    $file = [IO.File]::Create($Path)
    $zip = [IO.Compression.ZipArchive]::new($file, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $part = $zip.CreateEntry($Entry)
        $writer = [IO.StreamWriter]::new($part.Open(), [Text.UTF8Encoding]::new($false))
        try { $writer.Write($Content) } finally { $writer.Dispose() }
    } finally { $zip.Dispose(); $file.Dispose() }
}
Write-Ipa $goodIpa 'Payload/Fixture.app/Info.plist' $plist
Write-Ipa $minimumIpa 'Payload/Fixture.app/Info.plist' ($plist.Replace('</dict>', '<key>MinimumOSVersion</key><string>16.10</string></dict>'))
Write-Ipa $microIpa 'Payload/Fixture.app/Info.plist' ($plist.Replace('</dict>', '<key>MinimumOSVersion</key><string>16.10.2</string></dict>'))
Write-Ipa $invalidMinimumIpa 'Payload/Fixture.app/Info.plist' ($plist.Replace('</dict>', '<key>MinimumOSVersion</key><string>16.beta</string></dict>'))
Write-Ipa $anotherAccountIpa 'Payload/Fixture.app/Info.plist' ($plist.Replace('<string>1.0</string>', '<string>1.1</string>'))
Write-Ipa $badIpa 'not-an-app.txt' 'Invalid IPA fixture'
[IO.File]::WriteAllText($nonZip, 'Not a ZIP archive')
$sourceHash = (Get-FileHash -LiteralPath $goodIpa -Algorithm SHA256).Hash
$firstId = '1111111111111111111111111111111111111111'
$secondId = '00008110-001A2B3C4D5E001E'
$script:Checks = 0
function Assert($Condition, [string]$Description) {
    if (-not $Condition) { throw ('FAIL: ' + $Description) }
    $script:Checks++
    Write-Output ('PASS: ' + $Description)
}
function Invoke-Case([string]$Scenario, [string]$Action = 'install', [string]$IpaPath = $goodIpa, [string]$DeviceId = $firstId, [switch]$Cancel, [int]$Timeout = 8, [int]$PairingTimeout = 4, [ValidateSet('ru','en')][string]$Language = 'ru') {
    $env:IPA_INSTALL_TEST_SCENARIO = $Scenario
    $caseRoot = Join-Path $TestRoot ($Scenario + '-' + [guid]::NewGuid().ToString('N'))
    $null = [IO.Directory]::CreateDirectory($caseRoot)
    $callLog = Join-Path $caseRoot 'native-calls.jsonl'
    $env:IPA_INSTALL_TEST_LOG = $callLog
    $env:IPA_INSTALL_TEST_EXPECTED_SHA256 = if ([IO.File]::Exists($IpaPath)) { (Get-FileHash -LiteralPath $IpaPath -Algorithm SHA256).Hash } else { $sourceHash }
    $options = @{ AppRoot=$caseRoot; Action=$Action; IpaPath=$IpaPath; DeviceId=$DeviceId; ToolRoot=$toolRoot; NativeTimeoutSeconds=$Timeout; PairingTimeoutSeconds=$PairingTimeout; Language=$Language }
    $bus = [hashtable]::Synchronized(@{ Events=[Collections.Concurrent.ConcurrentQueue[object]]::new(); Cancel=$false })
    $events = [Collections.Generic.List[object]]::new()
    $runner = [PowerShell]::Create()
    $null = $runner.AddScript('param($Path,$Options,$Bus); . $Path; Invoke-InstallerWorkflow $Options $Bus').AddArgument((Join-Path $AppRoot 'Engine.ps1')).AddArgument($options).AddArgument($bus)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $handle = $runner.BeginInvoke()
    try {
        while (-not $handle.IsCompleted -or -not $bus.Events.IsEmpty) {
            $event = $null
            while ($bus.Events.TryDequeue([ref]$event)) { $events.Add($event) }
            if ($Cancel -and [IO.File]::Exists($callLog)) {
                try {
                    $nativeCalls = [IO.File]::ReadAllText($callLog)
                    if ($nativeCalls.Contains('"-i"') -or ($Scenario -eq 'pair-cancel' -and $nativeCalls.Contains('"pair"'))) { $bus.Cancel = $true }
                } catch [IO.IOException] { # The fake process can hold the log briefly while appending; poll again.
                }
            }
            if ($clock.Elapsed.TotalSeconds -gt 20) { $bus.Cancel = $true; throw ('Case timed out: ' + $Scenario) }
            Start-Sleep -Milliseconds 30
        }
        $null = $runner.EndInvoke($handle)
        if ($runner.HadErrors) { throw ($runner.Streams.Error | Out-String) }
    } finally { $bus.Cancel = $true; $runner.Dispose(); $clock.Stop() }
    $calls = @()
    if ([IO.File]::Exists($callLog)) { $calls = @(Get-Content -LiteralPath $callLog -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json }) }
    return [pscustomobject]@{ Events=$events.ToArray(); Calls=$calls; Elapsed=$clock.Elapsed.TotalSeconds; Root=$caseRoot }
}
function Assert-Failed($Case, [string]$Description) {
    Assert (@($Case.Events | Where-Object Kind -eq 'error').Count -eq 1 -and @($Case.Events | Where-Object Kind -eq 'done').Count -eq 0) $Description
}
function Install-Calls($Case) { return @($Case.Calls | Where-Object { $_.tool -eq 'ideviceinstaller' -and $_.arguments -contains '-i' }) }
function Pair-Calls($Case) { return @($Case.Calls | Where-Object { $_.tool -eq 'idevicepair' -and $_.arguments -contains 'pair' }) }
try {
    $english = Invoke-Case 'happy' -Language 'en'
    Assert (@($english.Events | Where-Object Kind -eq 'done').Count -eq 1) 'English language preserves successful installation'
    Assert (@($english.Events | Where-Object { $_.Kind -eq 'status' -and $_.Data -eq 'Installing…' }).Count -eq 1) 'Worker runspace uses the selected English language'
    $englishInvalid = Invoke-Case 'happy' -IpaPath $badIpa -Language 'en'
    Assert (@($englishInvalid.Events | Where-Object { $_.Kind -eq 'error' -and $_.Data -eq 'No valid app was found in the IPA file.' }).Count -eq 1) 'Worker translates IPA validation errors to English'
    $none = Invoke-Case 'none' 'devices'
    $empty = @($none.Events | Where-Object Kind -eq 'devices')
    Assert ($empty.Count -eq 1 -and @($empty[0].Data).Count -eq 0) 'No USB devices produces an empty device list'
    Assert (@($none.Events | Where-Object Kind -eq 'error').Count -eq 0) 'No phone is a normal discovery result'
    $multi = Invoke-Case 'multi' 'devices'
    $discovered = @($multi.Events | Where-Object Kind -eq 'devices')[0].Data
    Assert (@($discovered).Count -eq 2 -and $discovered[0].Id -eq $firstId -and $discovered[1].Id -eq $secondId) 'Discovery preserves two independent USB device IDs'
    Assert ($discovered[0].Name.StartsWith('Test iPhone') -and $discovered[1].Name.StartsWith('Second iPhone')) 'Device names correspond to queried device IDs'
    Assert ($discovered[0].ProductType -eq 'iPhone16,2' -and $discovered[0].ModelName -eq 'iPhone 15 Pro Max') 'Verified ProductType maps to correct marketing model'
    Assert ($discovered[1].ModelName -eq 'iPhone 13' -and $discovered[1].ProductVersion -eq '18.5') 'Model and iOS are read for the correct second device'
    Assert ($discovered[0].DisplayName.Contains('iOS 18.5') -and $discovered[0].DisplayName.Contains('111111') -and $discovered[1].DisplayName.Contains('5E001E')) 'Device display includes iOS and disambiguates multiple phones'
    $unknownModel = Invoke-Case 'model-unknown' 'devices'
    $unknownDevice = @($unknownModel.Events | Where-Object Kind -eq 'devices')[0].Data[0]
    Assert ($unknownDevice.ModelName -eq 'iPhone99,9' -and $unknownDevice.DisplayName.StartsWith('iPhone99,9')) 'Unknown model falls back to reported ProductType instead of guessing'
    $unknownIos = Invoke-Case 'ios-unknown' 'devices'
    $unknownDevice = @($unknownIos.Events | Where-Object Kind -eq 'devices')[0].Data[0]
    Assert ($unknownDevice.ProductVersion -eq '' -and $unknownDevice.DisplayName.Contains('неизвестна')) 'Missing iOS is explicitly unknown'
    Assert (@(Install-Calls $multi).Count -eq 0) 'Discovery never invokes installation'
    $unpairedDiscovery = Invoke-Case 'pair-new' 'devices'
    Assert (@($unpairedDiscovery.Calls | Where-Object tool -eq 'idevicepair').Count -eq 0) 'Device discovery does not invoke pairing or validation handshake'
    Assert (@($unpairedDiscovery.Calls | Where-Object { $_.tool -eq 'ideviceinfo' -and $_.arguments -notcontains '-s' }).Count -eq 0) 'Device name queries use simple mode without automatic pairing'
    $inspect = Invoke-Case 'happy' 'inspect' $minimumIpa
    $metadata = @($inspect.Events | Where-Object Kind -eq 'ipa')[0].Data
    Assert ($metadata.BundleId -eq 'com.example.fixture' -and $metadata.MinimumOSVersion -eq '16.10') 'IPA inspection returns required numeric iOS and bundle ID'
    Assert ($metadata.CredentialKey -eq ('sha256:' + (Get-FileHash -LiteralPath $minimumIpa -Algorithm SHA256).Hash.ToLowerInvariant())) 'Credential identity hashes exact IPA bytes'
    Assert ($inspect.Calls.Count -eq 0 -and @(Get-ChildItem -LiteralPath $inspect.Root -Directory -Force).Count -eq 0) 'XML IPA inspection neither copies payload nor invokes device tools'
    $noMinimum = Invoke-Case 'happy' 'inspect' $goodIpa
    $firstMetadata = @($noMinimum.Events | Where-Object Kind -eq 'ipa')[0].Data
    Assert ($firstMetadata.MinimumOSVersion -eq '') 'Absent minimum iOS stays unknown'
    $invalidMinimum = Invoke-Case 'happy' 'inspect' $invalidMinimumIpa
    Assert (@($invalidMinimum.Events | Where-Object Kind -eq 'ipa')[0].Data.MinimumOSVersion -eq '') 'Malformed minimum iOS stays unknown'
    $otherContent = Invoke-Case 'happy' 'inspect' $anotherAccountIpa
    $otherMetadata = @($otherContent.Events | Where-Object Kind -eq 'ipa')[0].Data
    Assert ($otherMetadata.BundleId -eq $firstMetadata.BundleId -and $otherMetadata.CredentialKey -ne $firstMetadata.CredentialKey) 'Different IPA contents do not share credentials despite equal bundle ID'
    $sameFileCopy = Join-Path $fixtureDir 'renamed identical.ipa'
    [IO.File]::Copy($minimumIpa, $sameFileCopy)
    $sameContent = Invoke-Case 'happy' 'inspect' $sameFileCopy
    Assert (@($sameContent.Events | Where-Object Kind -eq 'ipa')[0].Data.CredentialKey -eq $metadata.CredentialKey) 'Renaming identical IPA preserves credential identity'
    $low = Invoke-Case 'ios-low' 'install' $minimumIpa
    Assert-Failed $low 'iOS 16.9 is below required iOS 16.10'
    Assert (@(Install-Calls $low).Count -eq 0) 'Known insufficient iOS blocks sending IPA'
    Assert (@($low.Events | Where-Object Kind -eq 'deviceinfo')[0].Data.ProductVersion -eq '16.9') 'Installation refreshes and reports current iOS after pairing'
    $equal = Invoke-Case 'ios-ten' 'install' $minimumIpa
    Assert (@($equal.Events | Where-Object Kind -eq 'done').Count -eq 1) 'Equal numeric iOS version permits installation'
    $micro = Invoke-Case 'ios-micro-low' 'install' $microIpa
    Assert-Failed $micro 'Patch version is included in minimum iOS comparison'
    Assert (@(Install-Calls $micro).Count -eq 0) 'Insufficient patch version prevents installation'
    foreach ($scenario in @('ios-unknown','ios-invalid')) {
        $unknown = Invoke-Case $scenario 'install' $minimumIpa
        Assert (@($unknown.Events | Where-Object Kind -eq 'done').Count -eq 1 -and @($unknown.Events | Where-Object Kind -eq 'deviceinfo')[0].Data.ProductVersion -eq '') ($scenario + ' defers decision to iPhone without claiming known compatibility')
    }
    $happy = Invoke-Case 'happy'
    $done = @($happy.Events | Where-Object Kind -eq 'done')
    Assert ($done.Count -eq 1 -and $done[0].Data.DeviceId -eq $firstId) 'Successful installation reports completion for selected phone'
    Assert ($done[0].Data.CredentialKey -eq $firstMetadata.CredentialKey -and $done[0].Data.BundleId -eq $firstMetadata.BundleId) 'Completion identifies actual staged IPA for correct saved credentials'
    Assert (@($happy.Events | Where-Object Kind -eq 'error').Count -eq 0) 'Successful workflow has no error event'
    Assert (@($happy.Calls | Where-Object { $_.tool -eq 'ideviceinstaller' -and $_.arguments -contains '-l' }).Count -eq 1) 'Completion is verified against installed application list'
    $calls = @(Install-Calls $happy)
    Assert ($calls.Count -eq 1 -and $calls[0].arguments -contains $firstId) 'Install command targets the selected device explicitly'
    Assert (($calls[0].arguments -join '|').Contains('payload.ipa')) 'IPA from Unicode path is supplied as staged payload'
    Assert (@(Get-ChildItem -LiteralPath $happy.Root -Directory -Force).Count -eq 0) 'Temporary payload and extracted metadata are cleaned after success'
    $second = Invoke-Case 'selected-second' 'install' $goodIpa $secondId
    Assert (@($second.Events | Where-Object Kind -eq 'done').Count -eq 1 -and @(Install-Calls $second)[0].arguments -contains $secondId) 'With multiple phones, only selected second phone is installed'
    foreach ($scenario in @('removed','untrusted','locked')) {
        $case = Invoke-Case $scenario
        Assert-Failed $case ($scenario + ' prevents false success')
        Assert (@(Install-Calls $case).Count -eq 0) ($scenario + ' prevents sending IPA to a phone')
        Assert (@(Pair-Calls $case).Count -eq 0) ($scenario + ' does not trigger unnecessary pairing attempts')
    }
    foreach ($scenario in @('pair-new','pair-direct-pending','pair-pending')) {
        $case = Invoke-Case $scenario
        Assert (@($case.Events | Where-Object Kind -eq 'done').Count -eq 1) ($scenario + ' continues installation after trust confirmation')
        $expectedPairCalls = if ($scenario -eq 'pair-pending') { 2 } else { 1 }
        Assert (@(Pair-Calls $case).Count -eq $expectedPairCalls) ($scenario + ' retries pairing only while trust is pending')
    }
    foreach ($scenario in @('pair-denied','pair-validate-denied','pair-no-success')) {
        $case = Invoke-Case $scenario
        Assert-Failed $case ($scenario + ' stops before installation')
        $expectedPairCalls = if ($scenario -eq 'pair-validate-denied') { 0 } else { 1 }
        Assert (@(Pair-Calls $case).Count -eq $expectedPairCalls -and @(Install-Calls $case).Count -eq 0) ($scenario + ' does not repeat pairing or send IPA')
    }
    $trustTimeout = Invoke-Case 'pair-forever' -PairingTimeout 1
    Assert-Failed $trustTimeout 'Unconfirmed trust request ends after bounded wait'
    Assert ($trustTimeout.Elapsed -lt 6 -and @(Install-Calls $trustTimeout).Count -eq 0) 'Trust timeout prevents installation and returns promptly'
    $trustCancel = Invoke-Case 'pair-cancel' -Cancel
    Assert (@($trustCancel.Events | Where-Object Kind -eq 'cancelled').Count -eq 1 -and @(Install-Calls $trustCancel).Count -eq 0) 'Trust waiting can be cancelled before installation'
    Assert ($trustCancel.Elapsed -lt 6 -and @(Get-ChildItem -LiteralPath $trustCancel.Root -Directory -Force).Count -eq 0) 'Trust cancellation finishes promptly and cleans staging'
    foreach ($inputFile in @($badIpa,$nonZip,(Join-Path $fixtureDir 'missing.ipa'))) {
        $case = Invoke-Case 'happy' 'install' $inputFile
        Assert-Failed $case ('Invalid input rejected: ' + [IO.Path]::GetFileName($inputFile))
        Assert (@(Install-Calls $case).Count -eq 0) 'Invalid input never reaches native installer'
    }
    foreach ($scenario in @('exit0-error','no-complete','nonzero-complete','missing-installed')) {
        $case = Invoke-Case $scenario
        Assert-Failed $case ($scenario + ' cannot produce false installation success')
        Assert (@(Get-ChildItem -LiteralPath $case.Root -Directory -Force).Count -eq 0) ($scenario + ' cleans temporary staging')
    }
    $cancelled = Invoke-Case 'slow' -Cancel
    Assert (@($cancelled.Events | Where-Object Kind -eq 'cancelled').Count -eq 1 -and @($cancelled.Events | Where-Object Kind -eq 'done').Count -eq 0) 'Cancellation stops waiting and does not claim installation success'
    Assert ($cancelled.Elapsed -lt 8) 'Running native process cancellation finishes promptly'
    Assert (@(Get-ChildItem -LiteralPath $cancelled.Root -Directory -Force).Count -eq 0) 'Cancellation cleans temporary staging'
    $timeout = Invoke-Case 'slow' -Timeout 1
    Assert-Failed $timeout 'Native installation timeout returns failure'
    Assert ($timeout.Elapsed -lt 8) 'Native timeout is bounded'
    Assert ((Get-FileHash -LiteralPath $goodIpa -Algorithm SHA256).Hash -eq $sourceHash) 'Source IPA content is unchanged after all operations'
    Write-Output ("All $script:Checks checks passed. Only fake native tools were invoked. Artifacts: $TestRoot")
} finally {
    foreach ($variable in @('IPA_INSTALL_TEST_SCENARIO','IPA_INSTALL_TEST_LOG','IPA_INSTALL_TEST_EXPECTED_SHA256')) { [Environment]::SetEnvironmentVariable($variable, $null, 'Process') }
}
