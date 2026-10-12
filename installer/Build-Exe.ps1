#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$Destination=[IO.Path]::GetFullPath($Destination)
$null=[IO.Directory]::CreateDirectory($Destination)
$work=Join-Path $PSScriptRoot ('.build/'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($work)
$files=[Collections.Generic.List[string]]::new()
foreach($name in @('IPA-Install.ps1','Engine.ps1','Credentials.ps1','AccountWindows.ps1','Localization.ps1','PRIVACY.md','PRIVACY.en.md')){$files.Add($name)}
# Include only pinned executables and DLLs, plus their notices and corresponding sources.
foreach($line in [IO.File]::ReadAllLines((Join-Path $PSScriptRoot 'tools/SHA256SUMS.txt'))){
    if($line -notmatch '^([a-fA-F0-9]{64})\s+([a-zA-Z0-9_.-]+\.(?:exe|dll))$'){throw 'Invalid tool checksum entry'}
    $expected=$Matches[1];$name='tools/'+$Matches[2]
    if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash -ne $expected){throw "Tool hash mismatch: $name"}
    $files.Add($name)
}
foreach($name in @('tools/PACKAGES.json','tools/SHA256SUMS.txt','tools/THIRD-PARTY-NOTICES.txt')){$files.Add($name)}
foreach($folder in @('tools/licenses','tools/sources','tools/provenance')){
    foreach($file in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $folder) -Recurse -File | Sort-Object FullName){
        if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point in package'}
        $files.Add($file.FullName.Substring($PSScriptRoot.Length+1).Replace('\','/'))
    }
}
$archive=Join-Path $work 'payload.zip'
$zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach($name in $files){
        $entry=$zip.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime=[DateTimeOffset]::new(2026,1,1,0,0,0,[TimeSpan]::Zero)
        $inputFile=[IO.File]::OpenRead((Join-Path $PSScriptRoot $name));$outputFile=$entry.Open()
        try{$inputFile.CopyTo($outputFile)}finally{$outputFile.Dispose();$inputFile.Dispose()}
    }
}finally{$zip.Dispose()}
$hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
$generated=Join-Path $work 'PayloadInfo.cs'
[IO.File]::WriteAllText($generated,('internal static class PayloadInfo { internal const string Sha256 = "'+$hash+'"; }'),[Text.UTF8Encoding]::new($false))
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$exe=Join-Path $Destination 'IPA-Install.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 "/out:$exe" "/win32manifest:$PSScriptRoot\launcher\app.manifest" "/resource:$archive,IPA.Payload.zip" /reference:System.Windows.Forms.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll (Join-Path $PSScriptRoot 'launcher/Launcher.cs') $generated
if($LASTEXITCODE -ne 0){throw 'EXE compilation failed'}
[ordered]@{Exe=$exe;SHA256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash;PayloadSHA256=$hash;Files=$files.ToArray()} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $work 'Build-result.json') -Encoding UTF8
Get-Item -LiteralPath $exe | Select-Object FullName,Length
