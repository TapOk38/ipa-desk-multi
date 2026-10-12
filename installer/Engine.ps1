#requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

# Product identifiers checked against libirecovery's device table, 2026-09-25:
# https://github.com/libimobiledevice/libirecovery/blob/master/src/libirecovery.c
# Unknown identifiers are shown verbatim; never infer a marketing model number.
$script:InstallerModels = @{
    'iPhone1,1'='iPhone 2G'; 'iPhone1,2'='iPhone 3G'; 'iPhone2,1'='iPhone 3Gs'
    'iPhone3,1'='iPhone 4 (GSM)'; 'iPhone3,2'='iPhone 4 (GSM) R2 2012'; 'iPhone3,3'='iPhone 4 (CDMA)'; 'iPhone4,1'='iPhone 4s'
    'iPhone5,1'='iPhone 5 (GSM)'; 'iPhone5,2'='iPhone 5 (Global)'; 'iPhone5,3'='iPhone 5c (GSM)'; 'iPhone5,4'='iPhone 5c (Global)'
    'iPhone6,1'='iPhone 5s (GSM)'; 'iPhone6,2'='iPhone 5s (Global)'; 'iPhone7,1'='iPhone 6 Plus'; 'iPhone7,2'='iPhone 6'
    'iPhone8,1'='iPhone 6s'; 'iPhone8,2'='iPhone 6s Plus'; 'iPhone8,4'='iPhone SE (1st gen)'
    'iPhone9,1'='iPhone 7 (Global)'; 'iPhone9,2'='iPhone 7 Plus (Global)'; 'iPhone9,3'='iPhone 7 (GSM)'; 'iPhone9,4'='iPhone 7 Plus (GSM)'
    'iPhone10,1'='iPhone 8 (Global)'; 'iPhone10,2'='iPhone 8 Plus (Global)'; 'iPhone10,3'='iPhone X (Global)'
    'iPhone10,4'='iPhone 8 (GSM)'; 'iPhone10,5'='iPhone 8 Plus (GSM)'; 'iPhone10,6'='iPhone X (GSM)'
    'iPhone11,2'='iPhone XS'; 'iPhone11,4'='iPhone XS Max (China)'; 'iPhone11,6'='iPhone XS Max'; 'iPhone11,8'='iPhone XR'
    'iPhone12,1'='iPhone 11'; 'iPhone12,3'='iPhone 11 Pro'; 'iPhone12,5'='iPhone 11 Pro Max'; 'iPhone12,8'='iPhone SE (2nd gen)'
    'iPhone13,1'='iPhone 12 mini'; 'iPhone13,2'='iPhone 12'; 'iPhone13,3'='iPhone 12 Pro'; 'iPhone13,4'='iPhone 12 Pro Max'
    'iPhone14,2'='iPhone 13 Pro'; 'iPhone14,3'='iPhone 13 Pro Max'; 'iPhone14,4'='iPhone 13 mini'; 'iPhone14,5'='iPhone 13'; 'iPhone14,6'='iPhone SE (3rd gen)'
    'iPhone14,7'='iPhone 14'; 'iPhone14,8'='iPhone 14 Plus'; 'iPhone15,2'='iPhone 14 Pro'; 'iPhone15,3'='iPhone 14 Pro Max'
    'iPhone15,4'='iPhone 15'; 'iPhone15,5'='iPhone 15 Plus'; 'iPhone16,1'='iPhone 15 Pro'; 'iPhone16,2'='iPhone 15 Pro Max'
    'iPhone17,1'='iPhone 16 Pro'; 'iPhone17,2'='iPhone 16 Pro Max'; 'iPhone17,3'='iPhone 16'; 'iPhone17,4'='iPhone 16 Plus'; 'iPhone17,5'='iPhone 16e'
    'iPhone18,1'='iPhone 17 Pro'; 'iPhone18,2'='iPhone 17 Pro Max'; 'iPhone18,3'='iPhone 17'; 'iPhone18,4'='iPhone Air'; 'iPhone18,5'='iPhone 17e'
    'iPhone19,2'='iPhone 18 Pro'; 'iPhone19,3'='iPhone 18 Pro Max (US)'; 'iPhone19,7'='iPhone 18 Pro Max (Global)'
}

function Send-InstallerEvent([string]$Kind, $Data) {
    $script:InstallerBus.Events.Enqueue([pscustomobject]@{ Kind = $Kind; Data = $Data })
}
function Test-InstallerCancel {
    if ($script:InstallerBus.Cancel) { throw [OperationCanceledException]::new('Операция отменена.') }
}
function ConvertTo-InstallerArgument([AllowEmptyString()][string]$Value) {
    '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}
function Invoke-InstallerNative([string]$Tool, [string[]]$Arguments, [int]$TimeoutSeconds = 30, [string]$WorkingDirectory = '') {
    Test-InstallerCancel
    $exe = Join-Path $script:InstallerToolRoot ($Tool + '.exe')
    if (-not [IO.File]::Exists($exe)) { throw 'Не найдены компоненты установки. Закройте программу и запустите IPA-Install.exe повторно.' }
    if ($script:InstallerOptions.ContainsKey('NativeTimeoutSeconds')) {
        $TimeoutSeconds = [Math]::Min($TimeoutSeconds, [Math]::Max(1, [int]$script:InstallerOptions.NativeTimeoutSeconds))
    }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $exe
    $start.Arguments = ($Arguments | ForEach-Object { ConvertTo-InstallerArgument $_ }) -join ' '
    $start.WorkingDirectory = if ($WorkingDirectory) { $WorkingDirectory } else { $script:InstallerToolRoot }
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $started = $false
    try {
        try { $started = $process.Start() } catch { throw 'Не удалось запустить файлы установки. Распакуйте архив программы полностью.' }
        if (-not $started) { throw 'Не удалось запустить файлы установки.' }
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while (-not $process.WaitForExit(100)) {
            Test-InstallerCancel
            if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                if ($script:InstallerStarted) { throw 'Время ожидания истекло. Проверьте установку на iPhone.' }
                throw 'iPhone не отвечает. Разблокируйте его и проверьте USB-подключение.'
            }
        }
        Test-InstallerCancel
        $out = $stdout.GetAwaiter().GetResult()
        $err = $stderr.GetAwaiter().GetResult()
        $result = [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $out; Stderr = $err; Text = $out + "`n" + $err }
        if ($process.ExitCode -eq -1073741515 -or $process.ExitCode -eq -1073741701) {
            throw 'Не удалось загрузить компоненты установки. Распакуйте архив программы полностью.'
        }
        return $result
    } finally {
        if ($started) {
            try { if (-not $process.HasExited) { $process.Kill(); $null = $process.WaitForExit(3000) } } catch { }
        }
        $process.Dispose()
    }
}
function Test-InstallerDeviceId([string]$Id) { return $Id -match '^(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{8}-[a-fA-F0-9]{16})$' }
function Get-InstallerUsbIds {
    $result = Invoke-InstallerNative 'idevice_id' @('-l') 20
    if ($result.ExitCode -ne 0 -or $result.Text -match '(?im)^\s*ERROR\b') {
        throw 'Не удалось обнаружить iPhone. Проверьте USB-кабель и наличие Apple Devices на компьютере.'
    }
    foreach ($line in ($result.Stdout -split '[\r\n]+')) {
        $id = $line.Trim()
        if (-not $id) { continue }
        if (-not (Test-InstallerDeviceId $id)) { throw 'Не удалось прочитать список iPhone. Проверьте USB-подключение.' }
        $id
    }
}
function ConvertTo-InstallerVersionParts([string]$Value) {
    if ($Value -notmatch '^\d+(?:\.\d+){0,3}$') { return $null }
    $parts = New-Object int[] 4
    $values = $Value.Split('.')
    for ($i = 0; $i -lt $values.Count; $i++) {
        $number = 0
        if (-not [int]::TryParse($values[$i], [ref]$number)) { return $null }
        $parts[$i] = $number
    }
    return ,$parts
}
function Compare-InstallerIOSVersion([string]$Current, [string]$Minimum) {
    $left = ConvertTo-InstallerVersionParts $Current
    $right = ConvertTo-InstallerVersionParts $Minimum
    if ($null -eq $left -or $null -eq $right) { return $null }
    for ($i = 0; $i -lt 4; $i++) {
        if ($left[$i] -lt $right[$i]) { return -1 }
        if ($left[$i] -gt $right[$i]) { return 1 }
    }
    return 0
}
function Get-InstallerDeviceValue([string]$DeviceId, [string]$Key) {
    $result = Invoke-InstallerNative 'ideviceinfo' @('-s', '-u', $DeviceId, '-k', $Key) 20
    if ($result.ExitCode -eq 0 -and $result.Stdout.Trim() -and $result.Text -notmatch '(?im)^\s*ERROR\b') {
        $value = ($result.Stdout.Trim() -split '[\r\n]')[0] -replace '[\x00-\x1f\x7f]', ''
        if ($value.Length -gt 100) { $value = $value.Substring(0, 100) }
        return $value
    }
    return ''
}
function Get-InstallerDeviceInfo([string]$DeviceId, [switch]$Disambiguate) {
    $name = Get-InstallerDeviceValue $DeviceId 'DeviceName'
    $productType = Get-InstallerDeviceValue $DeviceId 'ProductType'
    $version = Get-InstallerDeviceValue $DeviceId 'ProductVersion'
    if ($productType -notmatch '^[A-Za-z]+\d+,\d+$') { $productType = '' }
    if ($null -eq (ConvertTo-InstallerVersionParts $version)) { $version = '' }
    if (-not $name) { $name = 'iPhone' }
    $model = if ($productType -and $script:InstallerModels.ContainsKey($productType)) { $script:InstallerModels[$productType] } elseif ($productType) { $productType } else { 'iPhone' }
    $display = $model + ' • ' + $(if ($version) { 'iOS ' + $version } else { 'iOS неизвестна' })
    if ($Disambiguate) { $display += ' (' + $DeviceId.Substring($DeviceId.Length - 6) + ')' }
    return [pscustomobject]@{ Id=$DeviceId; Name=$name; ProductType=$productType; ModelName=$model; ProductVersion=$version; DisplayName=$display }
}
function Get-InstallerDevices {
    $ids = @(Get-InstallerUsbIds | Select-Object -Unique)
    $devices = @()
    foreach ($id in $ids) {
        Test-InstallerCancel
        $devices += Get-InstallerDeviceInfo $id -Disambiguate:($ids.Count -gt 1)
    }
    return ,$devices
}
function Get-InstallerPairState($Result, [string]$DeviceId) {
    $id = [regex]::Escape($DeviceId)
    if ($Result.ExitCode -eq 0) {
        if ($Result.Text -match ('(?im)^SUCCESS:\s*(?:Validated pairing with|Paired with) device ' + $id + '\s*$')) { return 'ready' }
        return 'failed'
    }
    # These are the exact messages from the bundled libimobiledevice 1.3.0.
    # Never retry a denial or mistake an unrelated pairing error for a pending dialog.
    if ($Result.Text -match ('(?im)^ERROR: Device ' + $id + ' said that the user denied the trust dialog\.\s*$')) { return 'denied' }
    if ($Result.Text -match ('(?im)^ERROR: Could not validate with device ' + $id + ' because a passcode is set\. Please enter the passcode on the device and retry\.\s*$')) { return 'locked' }
    if ($Result.Text -match ('(?im)^ERROR: Please accept the trust dialog on the screen of device ' + $id + ', then attempt to pair again\.\s*$')) { return 'pending' }
    if ($Result.Text -match ('(?im)^ERROR: Device ' + $id + ' is not paired with this host\s*$')) { return 'missing' }
    if ($Result.Text -match '(?i)No device found|Could not connect to lockdownd') { return 'disconnected' }
    return 'failed'
}
function Throw-InstallerPairError([string]$State) {
    switch ($State) {
        'denied' { throw 'На iPhone отклонено доверие компьютеру. Подключите его заново и нажмите «Доверять».' }
        'locked' { throw 'Разблокируйте iPhone и повторите установку.' }
        'disconnected' { throw 'Не удалось подключиться к iPhone. Проверьте USB-кабель и повторите установку.' }
        default { throw 'Не удалось подтвердить доверие iPhone. Разблокируйте его и повторите установку.' }
    }
}
function Confirm-InstallerPairing([string]$DeviceId) {
    $result = Invoke-InstallerNative 'idevicepair' @('-u', $DeviceId, 'validate') 30
    $state = Get-InstallerPairState $result $DeviceId
    if ($state -eq 'ready') { return }
    if ($state -ne 'missing' -and $state -ne 'pending') { Throw-InstallerPairError $state }
    Send-InstallerEvent 'status' 'Разблокируйте iPhone и нажмите «Доверять».'
    $limit = 120
    if ($script:InstallerOptions.ContainsKey('PairingTimeoutSeconds')) { $limit = [Math]::Max(1, [int]$script:InstallerOptions.PairingTimeoutSeconds) }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        Test-InstallerCancel
        $remaining = $limit - $watch.Elapsed.TotalSeconds
        if ($remaining -le 0) { throw 'Доверие не подтверждено. Нажмите «Доверять» на iPhone и повторите установку.' }
        $timeout = [Math]::Max(1, [Math]::Min(30, [int][Math]::Ceiling($remaining)))
        $result = Invoke-InstallerNative 'idevicepair' @('-u', $DeviceId, 'pair') $timeout
        $state = Get-InstallerPairState $result $DeviceId
        if ($state -eq 'ready') { return }
        if ($state -ne 'pending') { Throw-InstallerPairError $state }
        # Wait in short cancellable slices before repeating only a pending dialog.
        for ($i = 0; $i -lt 10 -and $watch.Elapsed.TotalSeconds -lt $limit; $i++) {
            Test-InstallerCancel
            Start-Sleep -Milliseconds 100
        }
    }
}
function Read-InstallerXml([string]$Text) {
    $settings = [Xml.XmlReaderSettings]::new()
    # Apple plists contain a public DTD. Ignore it and never resolve external resources.
    $settings.DtdProcessing = [Xml.DtdProcessing]::Ignore
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 16777216
    $settings.MaxCharactersFromEntities = 1024
    $reader = $null
    $input = [IO.StringReader]::new($Text)
    try {
        $reader = [Xml.XmlReader]::Create($input, $settings)
        $doc = [Xml.XmlDocument]::new()
        $doc.XmlResolver = $null
        $doc.Load($reader)
        return ,$doc
    } finally { if ($reader) { $reader.Dispose() }; $input.Dispose() }
}
function Get-InstallerPlistString($Dictionary, [string]$Key) {
    if ($null -eq $Dictionary) { return '' }
    foreach ($node in $Dictionary.ChildNodes) {
        if ($node.NodeType -eq [Xml.XmlNodeType]::Element -and $node.Name -eq 'key' -and $node.InnerText -ceq $Key) {
            $value = $node.NextSibling
            while ($value -and $value.NodeType -ne [Xml.XmlNodeType]::Element) { $value = $value.NextSibling }
            if ($value -and $value.Name -eq 'string') { return $value.InnerText }
            return ''
        }
    }
    return ''
}
function New-InstallerWorkspace {
    $script:InstallerTempRoot = Join-Path $script:InstallerAppRoot ('.work-' + [guid]::NewGuid().ToString('N'))
    try { $null = [IO.Directory]::CreateDirectory($script:InstallerTempRoot) } catch { throw 'Не удалось создать временные файлы. Переместите программу в доступную для записи папку.' }
}
function Copy-InstallerIpa([string]$Source) {
    $sourceStream = $null
    $destination = $null
    try {
        $sourceStream = [IO.File]::Open($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $destination = [IO.File]::Open((Join-Path $script:InstallerTempRoot 'payload.ipa'), [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $buffer = New-Object byte[] 1048576
        while (($count = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            Test-InstallerCancel
            $destination.Write($buffer, 0, $count)
        }
    } catch [OperationCanceledException] { throw } catch { throw 'Не удалось подготовить IPA. Проверьте доступ к файлу и свободное место на диске.' }
    finally { if ($destination) { $destination.Dispose() }; if ($sourceStream) { $sourceStream.Dispose() } }
}
function Get-InstallerStreamHash([IO.Stream]$Stream) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $Stream.Position = 0
        $buffer = New-Object byte[] 1048576
        while (($count = $Stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            Test-InstallerCancel
            $null = $hash.TransformBlock($buffer, 0, $count, $buffer, 0)
        }
        $null = $hash.TransformFinalBlock([byte[]]@(), 0, 0)
        return 'sha256:' + [BitConverter]::ToString($hash.Hash).Replace('-', '').ToLowerInvariant()
    } finally { $hash.Dispose() }
}
function Read-InstallerIpa([string]$IpaPath, [switch]$Stage) {
    if ([string]::IsNullOrWhiteSpace($IpaPath) -or -not [IO.File]::Exists($IpaPath)) { throw 'Выберите существующий файл IPA.' }
    if ([IO.Path]::GetExtension($IpaPath) -ine '.ipa') { throw 'Выберите файл с расширением .ipa.' }
    $readPath = $IpaPath
    if ($Stage) {
        if (-not $script:InstallerTempRoot) { New-InstallerWorkspace }
        Copy-InstallerIpa $IpaPath
        $readPath = Join-Path $script:InstallerTempRoot 'payload.ipa'
    }
    $fileStream = $null
    $archive = $null
    $entryStream = $null
    $memory = $null
    try {
        # Metadata and credential identity use the same open file. A replacement of
        # the source between preview and installation is detected by the staged hash.
        $fileStream = [IO.File]::Open($readPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $archive = [IO.Compression.ZipArchive]::new($fileStream, [IO.Compression.ZipArchiveMode]::Read, $true)
        $entries = @($archive.Entries | Where-Object { $_.FullName -cmatch '^Payload/[^/\\]+\.app/Info\.plist$' })
        if ($entries.Count -ne 1 -or $entries[0].Length -le 0 -or $entries[0].Length -gt 10485760) { throw 'bad IPA' }
        $entryStream = $entries[0].Open()
        $memory = [IO.MemoryStream]::new()
        $buffer = New-Object byte[] 65536
        while (($count = $entryStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            Test-InstallerCancel
            if ($memory.Length + $count -gt 10485760) { throw 'bad IPA' }
            $memory.Write($buffer, 0, $count)
        }
        $bytes = $memory.ToArray()
        $entryStream.Dispose()
        $entryStream = $null
        $archive.Dispose()
        $archive = $null
        $credentialKey = Get-InstallerStreamHash $fileStream
    } catch [OperationCanceledException] { throw } catch { throw 'В файле IPA не найдено корректное приложение.' }
    finally { if ($memory) { $memory.Dispose() }; if ($entryStream) { $entryStream.Dispose() }; if ($archive) { $archive.Dispose() }; if ($fileStream) { $fileStream.Dispose() } }
    Test-InstallerCancel
    try {
        if ($bytes.Length -ge 8 -and [Text.Encoding]::ASCII.GetString($bytes, 0, 8) -eq 'bplist00') {
            if (-not $script:InstallerTempRoot) { New-InstallerWorkspace }
            [IO.File]::WriteAllBytes((Join-Path $script:InstallerTempRoot 'Info.plist'), $bytes)
            $convert = Invoke-InstallerNative 'plistutil' @('-i', 'Info.plist', '-o', 'Info.xml', '-f', 'xml') 30 $script:InstallerTempRoot
            $xmlFile = Join-Path $script:InstallerTempRoot 'Info.xml'
            if ($convert.ExitCode -ne 0 -or -not [IO.File]::Exists($xmlFile)) { throw 'bad plist' }
            if ([IO.FileInfo]::new($xmlFile).Length -gt 16777216) { throw 'bad plist' }
            $xmlText = [IO.File]::ReadAllText($xmlFile)
        } else {
            $reader = [IO.StreamReader]::new([IO.MemoryStream]::new($bytes), [Text.Encoding]::UTF8, $true)
            try { $xmlText = $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        $doc = Read-InstallerXml $xmlText
        $dict = $doc.SelectSingleNode('/plist/dict')
        $bundleId = Get-InstallerPlistString $dict 'CFBundleIdentifier'
        if ([string]::IsNullOrWhiteSpace($bundleId) -or $bundleId.Length -gt 255 -or $bundleId -notmatch '^[A-Za-z0-9][A-Za-z0-9.\-]*$') { throw 'bad bundle identifier' }
        $name = Get-InstallerPlistString $dict 'CFBundleDisplayName'
        if (-not $name) { $name = Get-InstallerPlistString $dict 'CFBundleName' }
        if (-not $name) { $name = [IO.Path]::GetFileNameWithoutExtension($IpaPath) }
        $name = $name -replace '[\x00-\x1f\x7f]', ''
        if ($name.Length -gt 100) { $name = $name.Substring(0, 100) }
        $minimum = Get-InstallerPlistString $dict 'MinimumOSVersion'
        if ($null -eq (ConvertTo-InstallerVersionParts $minimum)) { $minimum = '' }
        return [pscustomobject]@{ BundleId=$bundleId; Name=$name; MinimumOSVersion=$minimum; CredentialKey=$credentialKey }
    } catch [OperationCanceledException] { throw } catch { throw 'Не удалось прочитать сведения о приложении в IPA.' }
}
function Get-InstallerFailure([string]$Text) {
    if ($Text -match '(?i)ApplicationVerificationFailed|BundleVerificationFailed|A valid provisioning profile|provisioning profile|0xe8008015|0xe8008016|0xe8008018|0xe800801c|0xe8008029|0xe8008001') { return 'iPhone отклонил подпись или разрешение на установку этого IPA.' }
    if ($Text -match '(?i)DeviceOSVersionTooLow|MinimumOSVersion|not supported.*version|requires.*iOS') { return 'Для этого IPA требуется другая версия iOS.' }
    if ($Text -match '(?i)DeviceFamilyNotSupported|Architecture.*Unsupported|IncompatibleArchitecture') { return 'Это приложение несовместимо с выбранным iPhone.' }
    if ($Text -match '(?i)NoSpace|not enough.*space|disk.*full|InsufficientStorage') { return 'На iPhone недостаточно свободного места.' }
    if ($Text -match '(?i)DeviceLocked|PasswordProtected|passcode|lockdownd|pairing|trust') { return 'Разблокируйте iPhone, нажмите «Доверять» и повторите установку.' }
    if ($Text -match '(?i)Device removed|No device found|connection|AFC.*error|could not connect') { return 'Соединение с iPhone прервано. Проверьте USB-кабель и результат установки на телефоне.' }
    $match = [regex]::Match($Text, 'Got error\s+"([A-Za-z0-9_\-]{1,80})"')
    if ($match.Success) { return 'iPhone отклонил установку: ' + $match.Groups[1].Value + '.' }
    return 'Установка не подтверждена. Проверьте сообщение на iPhone и совместимость IPA.'
}
function Test-InstallerInstalled([string]$DeviceId, [string]$BundleId) {
    $result = Invoke-InstallerNative 'ideviceinstaller' @('-u', $DeviceId, '-l', '-o', 'xml') 120
    if ($result.ExitCode -ne 0) { return $false }
    try {
        $doc = Read-InstallerXml $result.Stdout
        foreach ($dict in $doc.SelectNodes('/plist/array/dict')) {
            if ((Get-InstallerPlistString $dict 'CFBundleIdentifier') -ceq $BundleId) { return $true }
        }
    } catch { return $false }
    return $false
}
function Remove-InstallerWorkspace {
    if (-not $script:InstallerTempRoot -or -not [IO.Directory]::Exists($script:InstallerTempRoot)) { return }
    # Only these flat temporary files can be created; never recursively delete.
    $resolved = [IO.Path]::GetFullPath($script:InstallerTempRoot)
    if ([IO.Path]::GetDirectoryName($resolved) -ne $script:InstallerAppRoot -or [IO.Path]::GetFileName($resolved) -notmatch '^\.work-[a-f0-9]{32}$') { return }
    try {
        $dir = Get-Item -LiteralPath $resolved -Force
        if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { return }
        foreach ($fileName in @('payload.ipa', 'Info.plist', 'Info.xml')) {
            $file = Join-Path $resolved $fileName
            if ([IO.File]::Exists($file)) { [IO.File]::Delete($file) }
        }
        [IO.Directory]::Delete($resolved, $false)
    } catch { Send-InstallerEvent 'status' ('Не удалось удалить временную копию IPA: ' + $script:InstallerTempRoot) }
}
function Invoke-InstallerWorkflow([hashtable]$Options, $Bus) {
    $script:InstallerOptions = $Options
    $script:InstallerBus = $Bus
    $script:InstallerTempRoot = $null
    $script:InstallerStarted = $false
    try {
        $script:InstallerAppRoot = [IO.Path]::GetFullPath($Options.AppRoot).TrimEnd('\', '/')
        $script:InstallerToolRoot = if ($Options.ContainsKey('ToolRoot')) { [IO.Path]::GetFullPath($Options.ToolRoot) } else { Join-Path $script:InstallerAppRoot 'tools' }
        Test-InstallerCancel
        if ($Options.Action -eq 'devices') {
            $devices = Get-InstallerDevices
            Send-InstallerEvent 'devices' $devices
            return
        }
        if ($Options.Action -eq 'inspect') {
            $app = Read-InstallerIpa ([string]$Options.IpaPath)
            Send-InstallerEvent 'ipa' $app
            return
        }
        if ($Options.Action -ne 'install') { throw 'Неизвестное действие.' }
        $deviceId = [string]$Options.DeviceId
        if (-not (Test-InstallerDeviceId $deviceId)) { throw 'Подключите iPhone по USB и нажмите «Обновить».' }
        Send-InstallerEvent 'status' 'Проверка IPA…'
        $app = Read-InstallerIpa ([string]$Options.IpaPath) -Stage
        $attached = @(Get-InstallerUsbIds)
        if ($attached -notcontains $deviceId) { throw 'iPhone отключён. Проверьте USB-кабель и нажмите «Обновить».' }
        Confirm-InstallerPairing $deviceId
        $device = Get-InstallerDeviceInfo $deviceId -Disambiguate:($attached.Count -gt 1)
        Send-InstallerEvent 'deviceinfo' $device
        $comparison = Compare-InstallerIOSVersion $device.ProductVersion $app.MinimumOSVersion
        if ($null -ne $comparison -and $comparison -lt 0) {
            throw ('Для приложения нужна iOS ' + $app.MinimumOSVersion + ' или новее. На iPhone установлена iOS ' + $device.ProductVersion + '.')
        }
        Test-InstallerCancel
        Send-InstallerEvent 'status' 'Установка…'
        $script:InstallerStarted = $true
        # The relative ASCII name avoids ANSI argv limitations of native Windows tools.
        # ProcessStartInfo sets the working directory through the Unicode Windows API.
        $result = Invoke-InstallerNative 'ideviceinstaller' @('-u', $deviceId, '-i', 'payload.ipa') 1800 $script:InstallerTempRoot
        if ($result.ExitCode -ne 0 -or $result.Text -match '(?im)^\s*ERROR\b' -or $result.Stdout -notmatch '(?m)(?:^|[\r\n])Install:\s*Complete(?:\s*\(100%\))?\s*(?:[\r\n]|$)') {
            throw (Get-InstallerFailure $result.Text)
        }
        if (-not (Test-InstallerInstalled $deviceId $app.BundleId)) { throw 'iPhone сообщил об установке, но приложение не найдено в списке. Проверьте результат на телефоне.' }
        Send-InstallerEvent 'done' ([pscustomobject]@{ Name=$app.Name; DeviceId=$deviceId; BundleId=$app.BundleId; MinimumOSVersion=$app.MinimumOSVersion; CredentialKey=$app.CredentialKey })
    } catch [OperationCanceledException] {
        $message = if ($script:InstallerStarted) { 'Ожидание остановлено. Проверьте установку на iPhone.' } else { 'Операция отменена.' }
        Send-InstallerEvent 'cancelled' $message
    } catch {
        Send-InstallerEvent 'error' $_.Exception.Message
    } finally { Remove-InstallerWorkspace }
}
