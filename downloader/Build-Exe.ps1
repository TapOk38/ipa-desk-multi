#requires -Version 5.1
param([string]$Destination=(Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$Destination=[IO.Path]::GetFullPath($Destination)
$null=[IO.Directory]::CreateDirectory($Destination)
$work=Join-Path $Destination ('build-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($work)
$archive=Join-Path $work 'payload.zip'
# Explicit allowlist: no accounts, sessions, downloads, external binaries or test fixtures.
$files=@('IPA-Desk.ps1','Accounts.ps1','Engine.ps1','Metadata.ps1','Metadata.cs','Install-Tools.ps1','Localization.ps1','PRIVACY.md','THIRD_PARTY.md','LICENSE','licenses/ipatool-MIT.txt')
$zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach($name in $files){
        $source=Join-Path $PSScriptRoot $name
        if(-not [IO.File]::Exists($source)){throw "Missing package file: $name"}
        $entry=$zip.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime=[DateTimeOffset]::new(2026,1,1,0,0,0,[TimeSpan]::Zero)
        $inputFile=[IO.File]::OpenRead($source); $outputFile=$entry.Open()
        try {$inputFile.CopyTo($outputFile)} finally {$outputFile.Dispose(); $inputFile.Dispose()}
    }
} finally {$zip.Dispose()}
$hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
$generated=Join-Path $work 'PayloadInfo.cs'
[IO.File]::WriteAllText($generated,('internal static class PayloadInfo { internal const string Sha256 = "'+$hash+'"; }'),[Text.UTF8Encoding]::new($false))
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$exe=Join-Path $Destination 'IPA-Desk-Multi-0.4.0-beta.2.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 "/out:$exe" "/win32manifest:$PSScriptRoot\launcher\app.manifest" "/resource:$archive,IPA.Payload.zip" /reference:System.Windows.Forms.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll (Join-Path $PSScriptRoot 'launcher\Launcher.cs') $generated
if($LASTEXITCODE -ne 0){throw 'EXE compilation failed'}
$manifest=[ordered]@{Version='0.4.0-beta.2';Exe=[IO.Path]::GetFileName($exe);SHA256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash;PayloadSHA256=$hash;Files=$files}
$manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $Destination 'Build-result.json') -Encoding UTF8
Write-Output $exe
Get-FileHash -LiteralPath $exe -Algorithm SHA256
