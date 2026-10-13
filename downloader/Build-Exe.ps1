#requires -Version 5.1
param([string]$Destination=(Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$Destination=[IO.Path]::GetFullPath($Destination)
$null=[IO.Directory]::CreateDirectory($Destination)
$version='0.6.1-test.1'
$exe=Join-Path $Destination ('TapOk-IPA-Downloader-'+$version+'.exe')
if(Test-Path -LiteralPath $exe){throw 'Choose an empty build destination.'}
$component=Join-Path $PSScriptRoot 'tools/cpp-1.1.6/ipatool-cpp.exe'
if(-not (Test-Path -LiteralPath $component)){throw 'Prepare the pinned component with Install-Tools.ps1 before building.'}
if((Get-FileHash -LiteralPath $component).Hash -ne 'F053593059A5ADA859F2D28F8707BEB8D53F02B7830A9895C5913653A23A0CE2'){throw 'Pinned component checksum mismatch'}
$work=Join-Path $PSScriptRoot ('.build/'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($work)
$payload=Join-Path $work 'IPATool.zip'
$files=[ordered]@{'ipatool-cpp.exe'=$component;'LICENSE.txt'=(Join-Path $PSScriptRoot 'LICENSE');'THIRD_PARTY.md'=(Join-Path $PSScriptRoot 'THIRD_PARTY.md');'ipatool-MIT.txt'=(Join-Path $PSScriptRoot 'licenses/ipatool-MIT.txt');'ipatool-cpp-MIT.txt'=(Join-Path $PSScriptRoot 'licenses/ipatool-cpp-MIT.txt')}
$zip=[IO.Compression.ZipFile]::Open($payload,[IO.Compression.ZipArchiveMode]::Create)
try{
    foreach($name in $files.Keys){
        if((Get-Item -LiteralPath $files[$name]).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked build input'}
        $entry=$zip.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime=[DateTimeOffset]::new(2026,1,1,0,0,0,[TimeSpan]::Zero)
        $inputFile=[IO.File]::OpenRead($files[$name]);$outputFile=$entry.Open()
        try{$inputFile.CopyTo($outputFile)}finally{$outputFile.Dispose();$inputFile.Dispose()}
    }
}finally{$zip.Dispose()}
$payloadHash=(Get-FileHash -LiteralPath $payload).Hash
$generated=Join-Path $work 'ComponentInfo.cs'
[IO.File]::WriteAllText($generated,('namespace TapOk.Downloader { internal static class ComponentInfo { internal const string ZipHash="'+$payloadHash+'"; }}'),[Text.UTF8Encoding]::new($false))
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$sources=@('native/Model.cs','native/Engine.cs','native/App.cs','native/Component.cs','Metadata.cs') | ForEach-Object {Join-Path $PSScriptRoot $_}
$sources+=,$generated
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 "/out:$exe" "/win32manifest:$PSScriptRoot\launcher\app.manifest" "/resource:$payload,TapOk.IPATool.zip" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Core.dll /reference:System.Security.dll /reference:System.Web.Extensions.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll /reference:System.Xml.dll $sources
if($LASTEXITCODE -ne 0){throw 'Native .NET compilation failed'}
$manifest=[ordered]@{Version=$version;Exe=[IO.Path]::GetFileName($exe);SHA256=(Get-FileHash -LiteralPath $exe).Hash;ComponentSHA256=(Get-FileHash -LiteralPath $component).Hash;PayloadSHA256=$payloadHash;Runtime='Single .NET EXE with offline TEMP-only component preparation; no PowerShell';Sources=@($sources | ForEach-Object {[IO.Path]::GetFileName($_)})}
$manifest | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $Destination 'Build-result.json') -Encoding UTF8
Get-Item -LiteralPath $exe | Select-Object Name,Length