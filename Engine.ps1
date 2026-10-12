#requires -Version 5.1
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Accounts.ps1')
. (Join-Path $PSScriptRoot 'Metadata.ps1')
. (Join-Path $PSScriptRoot 'Install-Tools.ps1')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Security

function Protect-SessionKey([byte[]]$Key, [byte[]]$Entropy) {
    return ,([Security.Cryptography.ProtectedData]::Protect($Key, $Entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser))
}
function Unprotect-SessionKey([byte[]]$Key, [byte[]]$Entropy) {
    return ,([Security.Cryptography.ProtectedData]::Unprotect($Key, $Entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser))
}
function Initialize-LocalSession {
    $dataRoot = if ($script:Options.ContainsKey('DataRoot')) { [IO.Path]::GetFullPath($script:Options.DataRoot) } else { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'IPA-Desk' }
    # Isolate credentials, cookies, profile and key for each normalized Apple ID.
    # Never import the legacy shared state: it may contain another account's cookies.
    $email = $script:Options.Email.Trim().ToLowerInvariant()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $accountId = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($email))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
    $dataRoot = Join-Path (Join-Path $dataRoot 'accounts') $accountId
    $null = [IO.Directory]::CreateDirectory($dataRoot)
    $keyPath = Join-Path $dataRoot 'session-key.dpapi'
    $entropy = [Text.Encoding]::UTF8.GetBytes('IPA-Desk/session-key/v1')
    $key = $null
    try {
        if (-not [IO.File]::Exists($keyPath)) {
            $key = New-Object byte[] 32
            $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
            try { $rng.GetBytes($key) } finally { $rng.Dispose() }
            $encrypted = Protect-SessionKey $key $entropy
            $file = $null
            try {
                # CreateNew prevents concurrent launches from replacing the existing key.
                $file = [IO.File]::Open($keyPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                $file.Write($encrypted, 0, $encrypted.Length)
            } catch [IO.IOException] {
                if (-not [IO.File]::Exists($keyPath)) { throw }
            } finally { if ($file) { $file.Dispose() } }
            [Array]::Clear($key, 0, $key.Length)
        }
        $key = Unprotect-SessionKey ([IO.File]::ReadAllBytes($keyPath)) $entropy
        if ($key.Length -ne 32) { throw (Get-IpaText 'Некорректный ключ сессии.') }
        $script:Options.Passphrase = [Convert]::ToBase64String($key)
        $script:Secrets.Add($script:Options.Passphrase)
    } catch {
        throw (Get-IpaText 'Не удалось открыть локальную сессию средствами Windows. Запустите приложение под тем же пользователем Windows, под которым оно использовалось ранее. Подробности восстановления — в README.md.')
    } finally { if ($key) { [Array]::Clear($key, 0, $key.Length) } }
    # Each workflow gets fresh credentials and cookies; concurrent runs stay independent.
    $script:SessionRunParent = Join-Path $dataRoot 'runs'
    $script:SessionRunRoot = Join-Path $script:SessionRunParent ([guid]::NewGuid().ToString('N'))
    $profile = Join-Path $script:SessionRunRoot 'profile'
    $null = [IO.Directory]::CreateDirectory($profile)
    $drive = [IO.Path]::GetPathRoot($profile)
    $script:SessionEnvironment = @{
        USERPROFILE = $profile
        HOMEDRIVE = $drive.TrimEnd('\')
        HOMEPATH = $profile.Substring($drive.Length - 1)
        XDG_STATE_HOME = (Join-Path $script:SessionRunRoot 'state')
        XDG_DATA_HOME = (Join-Path $script:SessionRunRoot 'state')
        LOCALAPPDATA = $script:RuntimeRoot
    }
}
function Remove-LocalSession {
    if (-not $script:SessionRunRoot -or -not [IO.Directory]::Exists($script:SessionRunRoot)) { return }
    try {
        $root = [IO.Path]::GetFullPath($script:SessionRunRoot)
        $parent = [IO.Path]::GetFullPath($script:SessionRunParent)
        if ([IO.Path]::GetDirectoryName($root) -ne $parent -or [IO.Path]::GetFileName($root) -notmatch '^[a-f0-9]{32}$') {
            throw (Get-IpaText 'Недопустимый путь временной сессии.')
        }
        # Do not follow directory links during recursive cleanup.
        $ancestor = Get-Item -LiteralPath $root -Force
        while ($ancestor) {
            if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw (Get-IpaText 'Путь сессии содержит ссылку.') }
            $ancestor = $ancestor.Parent
        }
        $pending = [Collections.Generic.Stack[string]]::new()
        $pending.Push($root)
        while ($pending.Count) {
            foreach ($item in @(Get-ChildItem -LiteralPath $pending.Pop() -Force)) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw (Get-IpaText 'Сессия содержит ссылку.') }
                if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            }
        }
        Remove-Item -LiteralPath $root -Recurse -Force
    } catch {
        Send-Event 'log' (Get-IpaText 'Не удалось удалить временные данные входа.')
    }
}

function Send-Event([string]$Kind, $Data) {
    if ($Data -is [string]) { $Data = Protect-Text $Data }
    $script:Bus.Events.Enqueue([pscustomobject]@{ Kind = $Kind; Data = $Data })
}
function Test-Cancel {
    if ($script:Bus.Cancel) { throw [OperationCanceledException]::new((Get-IpaText 'Операция отменена.')) }
}
function Request-Answer([string]$Kind, $Data) {
    $script:Bus.Answer = $null
    $script:Bus.AnswerReady = $false
    Send-Event $Kind $Data
    while (-not $script:Bus.AnswerReady) { Test-Cancel; Start-Sleep -Milliseconds 100 }
    Test-Cancel
    return $script:Bus.Answer
}
function Protect-Text([string]$Text) {
    $Text = [regex]::Replace($Text, '(?i)(https?|socks5h?)://[^\s/]*@', (Get-IpaText '$1://[скрыто]@'))
    foreach ($secret in $script:Secrets) {
        if (-not [string]::IsNullOrEmpty($secret)) {
            $Text = $Text.Replace($secret, (Get-IpaText '[скрыто]'))
            $escaped = ConvertTo-Json -InputObject $secret -Compress
            if ($escaped.Length -gt 2) { $Text = $Text.Replace($escaped.Substring(1, $escaped.Length - 2), (Get-IpaText '[скрыто]')) }
        }
    }
    return $Text
}
# Windows CommandLineToArgvW quoting. No cmd.exe, Invoke-Expression, or shell interpolation.
function ConvertTo-NativeArgument([AllowEmptyString()][string]$Value) {
    '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}
function Invoke-Native([string]$Executable, [string[]]$Arguments, [int]$TimeoutSeconds = 600, [hashtable]$ProcessEnvironment = @{}, [string]$WorkingDirectory = '') {
    Test-Cancel
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    # Windows accepts a Unicode working directory; C++ receives ASCII filenames.
    if ($WorkingDirectory) { $start.WorkingDirectory = $WorkingDirectory }
    $start.Arguments = ($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.RedirectStandardInput = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    if ($ProcessEnvironment.Count) {
        $environment = $start.get_EnvironmentVariables()
        foreach ($name in $ProcessEnvironment.Keys) { $environment[$name] = $ProcessEnvironment[$name] }
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $started = $false
    try {
        if (-not $process.Start()) { throw (Get-IpaText 'Не удалось запустить IPATool.') }
        $started = $true
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $watch = [Diagnostics.Stopwatch]::StartNew()
        while (-not $process.WaitForExit(100)) {
            Test-Cancel
            if ($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds) { throw (Get-IpaText 'Превышено время ожидания. Проверьте интернет и повторите запуск.') }
        }
        Test-Cancel
        $output = $stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Text = $output }
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}
function Read-Records([string]$Text) {
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line.Trim().StartsWith('{')) {
            try { ConvertFrom-Json -InputObject $line -ErrorAction Stop } catch { }
        }
    }
}
function Get-Field($Record, [string]$Name) {
    if ($null -ne $Record -and $Record.PSObject.Properties[$Name]) { return $Record.$Name }
    return $null
}
function Get-ErrorText($Result) {
    if ($Result.Text -match '(?i)Cannot convert character sequence|Illegal byte sequence') { return (Get-IpaText 'Загрузчик не смог обработать символы в пути. Переместите папку программы в путь с латинскими буквами и повторите загрузку.') }
    if ($Result.Text -match '(?i)you must purchase this app first') { return (Get-IpaText 'Apple не подтвердила лицензию на это приложение. Проверьте его в App Store под выбранным Apple ID.') }
    if ($Result.Text -match '(?i)session expired|password token expired') { return (Get-IpaText 'Сессия Apple истекла. Повторите запуск для этой учётки.') }
    $errors = @(Read-Records $Result.Text | ForEach-Object { Get-Field $_ 'error' } | Where-Object { $_ })
    $message = if ($errors.Count) { $errors[-1] } else { (($Result.Text -split '\r?\n' | Where-Object { $_ -notmatch '^PROGRESS:\d+\s*$' }) -join "`n").Trim() }
    if (-not $message) { $message = (Get-IpaText 'IPATool не подтвердил успешное выполнение.') }
    $message = Protect-Text $message
    if ($message.Length -gt 1600) { $message = $message.Substring(0, 1600) }
    return $message
}
function Get-ChildEnvironment {
    $childEnvironment = @{}
    foreach ($name in $script:SessionEnvironment.Keys) { $childEnvironment[$name] = $script:SessionEnvironment[$name] }
    # This edition always connects directly using HTTP/1.1; settings affect only IPATool.
    $childEnvironment['HTTP_PROXY'] = ''
    $childEnvironment['HTTPS_PROXY'] = ''
    $childEnvironment['ALL_PROXY'] = ''
    $childEnvironment['NO_PROXY'] = '*'
    $childEnvironment['GODEBUG'] = 'http2client=0'
    $childEnvironment['IPATOOL_AUTH_MODE'] = 'cpp'
    $childEnvironment['IPATOOL_NATIVE_AUTH_DIAGNOSTIC'] = ''
    return $childEnvironment
}
function Invoke-Cpp([string[]]$Arguments, [int]$TimeoutSeconds = 600) {
    # C++ does not implement the Go --non-interactive switch. Redirected stdin
    # already selects its noninteractive behavior; unknown flags can eat commands.
    Invoke-Native $script:CppExe (@('--format', 'json', '--keychain-passphrase', $script:Options.Passphrase) + $Arguments) $TimeoutSeconds (Get-ChildEnvironment) $script:NativeWorkDirectory
}
function Get-SuccessRecord($Result) {
    if ($Result.ExitCode -ne 0) { return $null }
    @(Read-Records $Result.Text | Where-Object { (Get-Field $_ 'success') -eq $true }) | Select-Object -Last 1
}
function Test-AuthCodeRequired($Result) {
    if ($Result.Text -match '(?im)^\s*(?:Error: )?two-factor auth code required\.') { return $true }
    foreach ($record in @(Read-Records $Result.Text)) {
        foreach ($field in @('message', 'error')) {
            $text = [string](Get-Field $record $field)
            if ($text -match '(?i)\b(?:2fa|auth(?:entication)?|verification|security)[ -]+code\s+(?:is\s+)?required\b|\b(?:invalid|incorrect|expired)\s+(?:2fa|auth(?:entication)?|verification|security)\s+code\b|\b(?:2fa|auth(?:entication)?|verification|security)\s+code\s+(?:is\s+)?(?:invalid|incorrect|expired)\b') { return $true }
        }
    }
    return $false
}
function Resolve-CppTool {
    $candidate=Join-Path $script:Options.AppRoot 'tools\cpp-1.0.9\ipatool-cpp.exe'
    if(-not [IO.File]::Exists($candidate)){Send-Event 'status' (Get-IpaText 'Загрузка компонента IPATool с GitHub…')}
    return Ensure-IpaTool -AppRoot $script:Options.AppRoot -Cancelled { $script:Bus.Cancel }
}
function Connect-Apple {
    if (-not $script:Options.Password) {
        $script:Options.Password = [string](Request-Answer 'password' (Get-IpaText 'Введите пароль Apple ID для входа.'))
        if (-not $script:Options.Password) { throw (Get-IpaText 'Пароль Apple ID не введён.') }
        $script:Secrets.Add($script:Options.Password)
    }
    if ($script:Options.Password.StartsWith('-')) { throw (Get-IpaText 'Эта версия IPATool не принимает пароль, начинающийся с дефиса. Вход остановлен до отправки данных.') }
    $code = ''
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        Send-Event 'status' ((Get-IpaText 'Вход в Apple ID: ') + $script:Options.Email + '…')
        $arguments = @('auth', 'login', '--email', $script:Options.Email, '--password', $script:Options.Password)
        if ($code) { $arguments += @('--auth-code', $code) }
        $login = Invoke-Cpp $arguments 900
        $success = Get-SuccessRecord $login
        if ($success -and (Get-Field $success 'email') -eq $script:Options.Email) {
            Send-Event 'log' (Get-IpaText 'Вход выполнен.')
            return
        }
        if ($success) { throw (Get-IpaText 'Apple подтвердил другой Apple ID. Работа остановлена; список и загрузка для этого аккаунта не выполнялись.') }
        if (Test-AuthCodeRequired $login) {
            if ($attempt -ge 3) { break }
            Send-Event 'log' ((Get-IpaText 'Требуется код подтверждения для ') + $script:Options.Email + '.')
            $code = [string](Request-Answer 'code' ((Get-IpaText 'Введите код для ') + $script:Options.Email + (Get-IpaText '. Проверьте доверенное устройство именно этого Apple ID.')))
            if ($code -notmatch '^\d{6}$') { throw (Get-IpaText 'Нужен шестизначный код Apple.') }
            $script:Secrets.Add($code)
            continue
        }
        throw ((Get-IpaText 'Вход не выполнен. ') + (Get-ErrorText $login))
    }
    throw (Get-IpaText 'Не удалось подтвердить код 2FA. Получите новый код и повторите запуск.')
}
function Get-SafeFileStem([string]$Name) {
    $stem = [regex]::Replace($Name, '[\x00-\x1f<>:"/\\|?*]', '_').Trim().TrimEnd('.')
    if (-not $stem) { $stem = 'application' }
    if ($stem.Length -gt 80) { $stem = $stem.Substring(0, 80).TrimEnd('.') }
    if ($stem -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { $stem = '_' + $stem }
    return $stem
}
function Test-IpaArchive([string]$Path) {
    if (-not [IO.File]::Exists($Path) -or ([IO.FileInfo]$Path).Length -eq 0) { throw (Get-IpaText 'IPATool не создал IPA-файл.') }
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $valid = @($zip.Entries | Where-Object { $_.FullName -match '^Payload/[^/]+\.app/Info\.plist$' })
        if (-not $valid.Count) { throw (Get-IpaText 'В архиве отсутствует Payload/*.app/Info.plist. Результат не похож на IPA.') }
    } finally { $zip.Dispose() }
}
function Invoke-Workflow($Options, $Bus) {
    if ($Options.ContainsKey('Language')) { Set-IpaLanguage $Options.Language }
    $script:Options = $Options
    $script:Bus = $Bus
    $script:Secrets = [Collections.Generic.List[string]]::new()
    $script:Secrets.Add([string]$Options.Password)
    $script:SessionRunRoot = $null
    $script:SessionRunParent = $null
    $script:RuntimeRoot = Join-Path $Options.DataRoot 'runtime'
    $script:NativeWorkDirectory = ''
    $partial = $null
    try {
        Test-Cancel
        $Options.AppId = Resolve-AppId $Options.AppId
        if ($Options.ContainsKey('EncryptedPassword')) { $Options.Password = Unlock-Password $Options.EncryptedPassword }
        $script:Secrets.Add([string]$Options.Password)
        if ($Options.Email -notmatch '^\S+@\S+\.\S+$') { throw (Get-IpaText 'Введите Apple ID в виде адреса электронной почты.') }
        $destination = [IO.Path]::GetFullPath($Options.OutputFolder)
        $null = [IO.Directory]::CreateDirectory($destination)
        $script:NativeWorkDirectory = $destination
        $probe = Join-Path $destination ([guid]::NewGuid().ToString('N') + '.write-test')
        [IO.File]::WriteAllText($probe, '')
        [IO.File]::Delete($probe)
        Send-Event 'status' (Get-IpaText 'Подготовка IPATool…')
        $script:CppExe = Resolve-CppTool
        Initialize-LocalSession
        Connect-Apple
        $app = [pscustomobject]@{ Name = ('app-' + $Options.AppId); Id = $Options.AppId }
        $partial = Join-Path $destination ('.ipa-desk-' + [guid]::NewGuid().ToString('N') + '.partial.ipa')
        # The unique ASCII basename avoids narrow-path encoding failures in C++.
        # WorkingDirectory is per process; do not change the GUI's global directory.
        $arguments = @('download', '--output', [IO.Path]::GetFileName($partial))
        if ($app.Id -notmatch '^[1-9]\d{0,17}$') { throw (Get-IpaText 'У выбранного приложения нет корректного App Store ID.') }
        $arguments += @('--app-id', $app.Id, '--purchase')
        Send-Event 'status' (Get-IpaText 'Загрузка IPA…')
        $result = Invoke-Cpp $arguments 7200
        if (-not (Get-SuccessRecord $result)) { throw ((Get-IpaText 'Загрузка не выполнена. ') + (Get-ErrorText $result)) }
        Test-Cancel
        Send-Event 'status' (Get-IpaText 'Проверка IPA…')
        Test-IpaArchive $partial
        $hash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
        Test-Cancel
        $description = if ($Options.ContainsKey('Description')) { $Options.Description } else { '' }
        $stem = Get-IpaFileStem $partial $app.Id $Options.Email $description $destination
        $final = Join-Path $destination ($stem + '.ipa')
        $counter = 1
        while ([IO.File]::Exists($final)) { $final = Join-Path $destination ("$stem ($counter).ipa"); $counter++ }
        [IO.File]::Move($partial, $final)
        $size = ([IO.FileInfo]$final).Length
        Send-Event 'done' ([pscustomobject]@{ Path = $final; Bytes = $size; Sha256 = $hash })
    } catch {
        if ($Bus.Cancel -or $_.Exception -is [OperationCanceledException]) {
            Send-Event 'cancelled' (Get-IpaText 'Операция отменена.')
        } else {
            Send-Event 'error' (Protect-Text $_.Exception.Message)
        }
    } finally {
        if ($partial) {
            # Also remove the raw .tmp file left by an interrupted C++ download.
            # Both names belong to this operation's unique generated basename.
            foreach ($pendingFile in @($partial, ($partial + '.tmp'))) {
                if ([IO.File]::Exists($pendingFile)) {
                    try { [IO.File]::Delete($pendingFile) } catch { Send-Event 'log' (Get-IpaText 'Не удалось удалить незавершённую загрузку.') }
                }
            }
        }
        Remove-LocalSession
        $Options.Password = ''
        $Options.Passphrase = ''
        $Bus.Answer = $null
        $script:Secrets.Clear()
    }
}
