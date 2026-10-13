#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Destination=[IO.Path]::GetFullPath($Destination)
$null=[IO.Directory]::CreateDirectory($Destination)
$work=Join-Path $PSScriptRoot ('.build/'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($work)
$version='1.2.0-test.2'
$package=Join-Path $work 'components'
if(Test-Path -LiteralPath $package){throw 'Use a fresh destination; existing packages are not overwritten.'}
$null=[IO.Directory]::CreateDirectory($package)
$files=[Collections.Generic.List[string]]::new()
$entries=[Collections.Generic.List[string]]::new()
foreach($line in [IO.File]::ReadAllLines((Join-Path $PSScriptRoot 'tools/SHA256SUMS.txt'))){
    if($line -notmatch '^([a-fA-F0-9]{64})\s+([a-zA-Z0-9_.-]+\.(?:exe|dll))$'){throw 'Invalid tool checksum entry'}
    $expected=$Matches[1];$name=$Matches[2]
    $path=Join-Path $PSScriptRoot ('tools/'+$name)
    if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point in tool input'}
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected){throw "Tool hash mismatch: $name"}
    $files.Add('tools/'+$name)
    $entries.Add('{"'+$name+'","'+$expected+'"},')
}
if($entries.Count -eq 0){throw 'No pinned components'}
foreach($name in @('tools/PACKAGES.json','tools/SHA256SUMS.txt','tools/THIRD-PARTY-NOTICES.txt','PRIVACY.md')){$files.Add($name)}
foreach($folder in @('tools/licenses','tools/sources','tools/provenance')){
    $folderPath=Join-Path $PSScriptRoot $folder
    if((Get-Item -LiteralPath $folderPath).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point in package'}
    foreach($item in Get-ChildItem -LiteralPath $folderPath -Recurse -Force | Sort-Object FullName){
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point in package'}
        if(-not $item.PSIsContainer){$files.Add($item.FullName.Substring($PSScriptRoot.Length+1).Replace('\','/'))}
    }
}
foreach($name in $files){
    $target=Join-Path $package $name
    $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    [IO.File]::Copy((Join-Path $PSScriptRoot $name),$target,$false)
}
[IO.File]::Copy((Join-Path $PSScriptRoot '../LICENSE'),(Join-Path $package 'LICENSE'),$false)
$payload=Join-Path $work 'components.zip'
$zip=[IO.Compression.ZipFile]::Open($payload,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach($file in Get-ChildItem -LiteralPath $package -Recurse -File | Sort-Object FullName){
        $relative=$file.FullName.Substring($package.Length+1).Replace('\','/')
        $entry=$zip.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal)
        $inputFile=[IO.File]::OpenRead($file.FullName);$outputFile=$entry.Open()
        try{$inputFile.CopyTo($outputFile)}finally{$outputFile.Dispose();$inputFile.Dispose()}
    }
}finally{$zip.Dispose()}
$payloadHash=(Get-FileHash -LiteralPath $payload).Hash
$generated=Join-Path $work 'PinnedTools.cs'
[IO.File]::WriteAllText($generated,('using System.Collections.Generic; namespace TapOk.Installer { internal static class PinnedTools { internal const string PayloadSha256 = "'+$payloadHash+'"; internal static readonly Dictionary<string,string> Hashes = new Dictionary<string,string> {'+($entries -join "`n")+'};}}'),[Text.UTF8Encoding]::new($false))
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$exe=Join-Path $Destination ('TapOk-IPA-Installer-Windows-'+$version+'.exe')
if(Test-Path -LiteralPath $exe){throw 'Use a fresh output directory.'}
$sources=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'native') -Filter '*.cs' | ForEach-Object FullName)+@((Join-Path $PSScriptRoot '../downloader/Metadata.cs'),$generated)
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 "/out:$exe" "/win32manifest:$PSScriptRoot\launcher\app.manifest" "/resource:$payload,TapOk.USB.Components.zip" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Security.dll /reference:System.Web.Extensions.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll @sources
if($LASTEXITCODE -ne 0){throw 'EXE compilation failed'}
$result=[ordered]@{Version=$version;Exe=$exe;SHA256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash;PayloadSHA256=$payloadHash;Format='Single native .NET EXE; offline USB components extracted only to a unique TEMP folder';Files=$files.ToArray()}
$result | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $Destination 'Build-result.json') -Encoding UTF8
[pscustomobject]$result | Select-Object Exe,SHA256,PayloadSHA256