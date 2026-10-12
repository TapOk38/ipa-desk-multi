param([Parameter(Mandatory = $true)][byte[]]$TestKey)
# Explicit test-only substitute for an unavailable sandbox DPAPI user profile.
# Product Credentials.ps1 never loads this file or falls back to this cipher.
$script:CredentialTestKey = $TestKey
function Protect-InstallerCredentialBytes([byte[]]$Bytes) {
    $aes = [Security.Cryptography.Aes]::Create()
    $encryptor = $null
    try {
        $aes.Key = $script:CredentialTestKey
        $aes.GenerateIV()
        $encryptor = $aes.CreateEncryptor()
        $cipher = $encryptor.TransformFinalBlock($Bytes, 0, $Bytes.Length)
        $result = New-Object byte[] (16 + $cipher.Length)
        [Array]::Copy($aes.IV, 0, $result, 0, 16)
        [Array]::Copy($cipher, 0, $result, 16, $cipher.Length)
        return ,$result
    } finally { if ($encryptor) { $encryptor.Dispose() }; $aes.Dispose() }
}
function Unprotect-InstallerCredentialBytes([byte[]]$Bytes) {
    $aes = [Security.Cryptography.Aes]::Create()
    $decryptor = $null
    try {
        $aes.Key = $script:CredentialTestKey
        $iv = New-Object byte[] 16
        [Array]::Copy($Bytes, 0, $iv, 0, 16)
        $aes.IV = $iv
        $decryptor = $aes.CreateDecryptor()
        return ,($decryptor.TransformFinalBlock($Bytes, 16, $Bytes.Length - 16))
    } finally { if ($decryptor) { $decryptor.Dispose() }; $aes.Dispose() }
}
