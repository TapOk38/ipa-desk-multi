Add-Type -AssemblyName System.Security
function Get-AccountDescription($Account) {
    if ($Account.PSObject.Properties['Description']) { return [string]$Account.Description }
    return ''
}
function Resolve-AppId([string]$Value) {
    $value = $Value.Trim()
    if ($value -match '^[1-9][0-9]{0,17}$') { return $value }
    $uri = $null
    if ([Uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -eq 'https' -and $uri.Host -eq 'apps.apple.com' -and $uri.AbsolutePath -match '/id([1-9][0-9]{0,17})/?$') { return $Matches[1] }
    throw 'Введите App Store ID или ссылку https://apps.apple.com/…/id123456789.'
}
function Lock-Password([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try { return [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect($bytes, [Text.Encoding]::UTF8.GetBytes('IPA-Desk-Multi/accounts/v1'), [Security.Cryptography.DataProtectionScope]::CurrentUser)) }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}
function Unlock-Password([string]$Value) {
    $bytes = $null
    try {
        $bytes = [Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($Value), [Text.Encoding]::UTF8.GetBytes('IPA-Desk-Multi/accounts/v1'), [Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [Text.Encoding]::UTF8.GetString($bytes)
    } catch { throw 'Не удалось открыть пароль. Измените учётку и сохраните пароль заново под текущим пользователем Windows.' }
    finally { if ($bytes) { [Array]::Clear($bytes, 0, $bytes.Length) } }
}
function Read-Accounts([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return }
    try {
        $data = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($data.Version -ne 1) { throw 'version' }
        $seen = @{}; $ids = @{}
        foreach ($a in @($data.Accounts)) {
            if ($a.Id -notmatch '^[a-f0-9]{32}$' -or $a.Email -notmatch '^\S+@\S+\.\S+$' -or -not $a.Password) { throw 'invalid' }
            if ($seen.ContainsKey($a.Email.ToLowerInvariant()) -or $ids.ContainsKey($a.Id)) { throw 'duplicate' }
            $seen[$a.Email.ToLowerInvariant()] = $true; $ids[$a.Id] = $true
        }
        return $data.Accounts
    } catch { throw 'Не удалось прочитать сохранённые учётки. Файл accounts.json не изменён.' }
}
function Write-Accounts([string]$Path, [object[]]$Accounts) {
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $data = @{ Version = 1; Accounts = @($Accounts | ForEach-Object { @{ Id=$_.Id; Email=$_.Email; Password=$_.Password; Description=(Get-AccountDescription $_) } }) }
        [IO.File]::WriteAllText($temp, ($data | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp, $Path, [NullString]::Value) } else { [IO.File]::Move($temp, $Path) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}
