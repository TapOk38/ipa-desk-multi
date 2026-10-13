#requires -Version 5.1
param([string]$Destination=(Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Destination=[IO.Path]::GetFullPath($Destination)
$null=[IO.Directory]::CreateDirectory($Destination)
$version='0.6.0-test.1'
$exe=Join-Path $Destination ('TapOk-IPA-Downloader-'+$version+'.exe')
if(Test-Path -LiteralPath $exe){throw 'Choose an empty build destination.'}
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$sources=@('native/Model.cs','native/Engine.cs','native/App.cs','Metadata.cs') | ForEach-Object {Join-Path $PSScriptRoot $_}
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 "/out:$exe" "/win32manifest:$PSScriptRoot\launcher\app.manifest" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Core.dll /reference:System.Security.dll /reference:System.Web.Extensions.dll /reference:System.Net.Http.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll /reference:System.Xml.dll $sources
if($LASTEXITCODE -ne 0){throw 'Native .NET compilation failed'}
$manifest=[ordered]@{Version=$version;Exe=[IO.Path]::GetFileName($exe);SHA256=(Get-FileHash -LiteralPath $exe).Hash;Runtime='Compiled .NET Framework; no PowerShell or embedded scripts';Sources=@($sources | ForEach-Object {[IO.Path]::GetFileName($_)})}
$manifest | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $Destination 'Build-result.json') -Encoding UTF8
Write-Output $exe
Get-FileHash -LiteralPath $exe