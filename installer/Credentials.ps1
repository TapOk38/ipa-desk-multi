#requires -Version 5.1
. (Join-Path $PSScriptRoot 'Localization.ps1')
Add-Type -AssemblyName System.Security

function Get-InstallerCredentialStorePath([string]$StorePath) {
    if ([string]::IsNullOrWhiteSpace($StorePath)) {
        $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrWhiteSpace($localData)) { throw 'Storage unavailable' }
        $StorePath = Join-Path $localData 'IPA-Install/accounts.dat'
    }
    $resolved = [IO.Path]::GetFullPath($StorePath)
    if ([string]::IsNullOrWhiteSpace([IO.Path]::GetFileName($resolved))) { throw 'Invalid storage path' }
    return $resolved
}

function Protect-InstallerCredentialBytes([byte[]]$Bytes) {
    $entropy = [Text.Encoding]::UTF8.GetBytes('IPA-Install account storage v1')
    return ,([Security.Cryptography.ProtectedData]::Protect($Bytes, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser))
}

function Unprotect-InstallerCredentialBytes([byte[]]$Bytes) {
    $entropy = [Text.Encoding]::UTF8.GetBytes('IPA-Install account storage v1')
    return ,([Security.Cryptography.ProtectedData]::Unprotect($Bytes, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser))
}

function Invoke-InstallerCredentialStoreLocked([string]$Path, [scriptblock]$Operation) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $digest = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Path.ToUpperInvariant()))).Replace('-', '') }
    finally { $sha.Dispose() }
    $mutex = [Threading.Mutex]::new($false, ('Local\IPAInstall.Credentials.' + $digest))
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(5000) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'Storage busy' }
        & $Operation
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Read-InstallerCredentialStore([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return [pscustomobject]@{ Version = 1; Entries = @() } }
    $length = [IO.FileInfo]::new($Path).Length
    if ($length -lt 9 -or $length -gt 16777216) { throw 'Invalid storage' }
    $storedBytes = [IO.File]::ReadAllBytes($Path)
    if ([Text.Encoding]::ASCII.GetString($storedBytes, 0, 8) -cne 'IPAINS01') { throw 'Invalid storage' }
    $encrypted = New-Object byte[] ($storedBytes.Length - 8)
    [Array]::Copy($storedBytes, 8, $encrypted, 0, $encrypted.Length)
    $plain = $null
    try {
        $plain = Unprotect-InstallerCredentialBytes $encrypted
        $json = [Text.UTF8Encoding]::new($false, $true).GetString($plain)
        $database = ConvertFrom-Json -InputObject $json -ErrorAction Stop
    } finally { if ($null -ne $plain) { [Array]::Clear($plain, 0, $plain.Length) } }
    if ($null -eq $database -or $database.Version -ne 1 -or $null -eq $database.Entries -or $database.Entries -isnot [Array] -or $database.Entries.Count -gt 4096) { throw 'Invalid storage' }
    $seenKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $database.Entries) {
        if ($null -eq $entry -or $entry.Key -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.Key) -or $entry.Key.Length -gt 4096 -or
            $entry.AppleId -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.AppleId) -or
            $entry.Password -isnot [string] -or [string]::IsNullOrEmpty($entry.Password) -or -not $seenKeys.Add($entry.Key)) { throw 'Invalid storage' }
    }
    return $database
}

function Write-InstallerCredentialStore([string]$Path, $Database) {
    $plain = $null
    try {
        $json = ConvertTo-Json -InputObject $Database -Depth 5 -Compress -ErrorAction Stop
        $plain = [Text.Encoding]::UTF8.GetBytes($json)
        if ($plain.Length -gt 8388608) { throw 'Storage too large' }
        $encrypted = Protect-InstallerCredentialBytes $plain
    } finally { if ($null -ne $plain) { [Array]::Clear($plain, 0, $plain.Length) } }
    $folder = [IO.Path]::GetDirectoryName($Path)
    $null = [IO.Directory]::CreateDirectory($folder)
    $temporary = Join-Path $folder ('.accounts-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $stream = $null
    try {
        $stream = [IO.FileStream]::new($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $header = [Text.Encoding]::ASCII.GetBytes('IPAINS01')
        $stream.Write($header, 0, $header.Length)
        $stream.Write($encrypted, 0, $encrypted.Length)
        $stream.Flush($true)
        $stream.Dispose()
        $stream = $null
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally {
        if ($stream) { $stream.Dispose() }
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Get-InstallerCredential {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Key, [string]$StorePath)
    try {
        if ([string]::IsNullOrWhiteSpace($Key) -or $Key.Length -gt 4096) { throw 'Invalid key' }
        $storeFile = Get-InstallerCredentialStorePath $StorePath
        Invoke-InstallerCredentialStoreLocked $storeFile {
            $database = Read-InstallerCredentialStore $storeFile
            foreach ($entry in $database.Entries) {
                if ([string]::Equals($entry.Key, $Key, [StringComparison]::Ordinal)) {
                    return [pscustomobject]@{ AppleId = $entry.AppleId; Password = $entry.Password }
                }
            }
            return $null
        }
    } catch { throw [InvalidOperationException]::new((Get-InstallerText 'Не удалось прочитать сохранённые учётные данные.')) }
}

function Set-InstallerCredential {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Key,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$AppleId,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Password,
        [string]$StorePath
    )
    try {
        if ([string]::IsNullOrWhiteSpace($Key) -or $Key.Length -gt 4096 -or [string]::IsNullOrWhiteSpace($AppleId) -or [string]::IsNullOrEmpty($Password)) { throw 'Invalid credential' }
        $storeFile = Get-InstallerCredentialStorePath $StorePath
        Invoke-InstallerCredentialStoreLocked $storeFile {
            $database = Read-InstallerCredentialStore $storeFile
            $entries = @($database.Entries | Where-Object { -not [string]::Equals($_.Key, $Key, [StringComparison]::Ordinal) })
            if ($entries.Count -ge 4096) { throw 'Storage full' }
            $entries += [pscustomobject]@{ Key = $Key; AppleId = $AppleId.Trim(); Password = $Password }
            Write-InstallerCredentialStore $storeFile ([pscustomobject]@{ Version = 1; Entries = $entries })
        }
    } catch { throw [InvalidOperationException]::new((Get-InstallerText 'Не удалось сохранить учётные данные.')) }
}

function Remove-InstallerCredential {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Key, [string]$StorePath)
    try {
        if ([string]::IsNullOrWhiteSpace($Key) -or $Key.Length -gt 4096) { throw 'Invalid key' }
        $storeFile = Get-InstallerCredentialStorePath $StorePath
        Invoke-InstallerCredentialStoreLocked $storeFile {
            $database = Read-InstallerCredentialStore $storeFile
            $entries = @($database.Entries | Where-Object { -not [string]::Equals($_.Key, $Key, [StringComparison]::Ordinal) })
            if ($entries.Count -ne $database.Entries.Count) { Write-InstallerCredentialStore $storeFile ([pscustomobject]@{ Version = 1; Entries = $entries }) }
        }
    } catch { throw [InvalidOperationException]::new((Get-InstallerText 'Не удалось удалить учётные данные.')) }
}
