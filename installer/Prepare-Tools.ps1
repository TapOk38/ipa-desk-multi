#requires -Version 5.1
param()
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$toolRoot=Join-Path $PSScriptRoot 'tools'
$spec=Get-Content -LiteralPath (Join-Path $toolRoot 'PACKAGES.json') -Raw | ConvertFrom-Json
$cache=Join-Path $PSScriptRoot '.downloads'
$null=[IO.Directory]::CreateDirectory($cache)
$null=[IO.Directory]::CreateDirectory((Join-Path $toolRoot 'sources'))
function Receive-Pinned([string]$Url,[string]$Hash,[string]$Path){
    $uri=[Uri]$Url
    if($uri.Scheme -ne 'https' -or $uri.Host -ne 'mirror.msys2.org' -or $Hash -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid pinned package'}
    if([IO.File]::Exists($Path) -and (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Hash){return}
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Path
    if((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Hash){throw "Package checksum mismatch: $Url"}
}
$tar=Join-Path $env:SystemRoot 'System32/tar.exe'
foreach($property in $spec.packages.PSObject.Properties){
    $package=$property.Value
    $archive=Join-Path $cache ([IO.Path]::GetFileName(([Uri]$package.binary_url).AbsolutePath))
    Receive-Pinned $package.binary_url $package.binary_sha256 $archive
    $unpack=Join-Path $cache $property.Name
    $null=[IO.Directory]::CreateDirectory($unpack)
    foreach($binary in $spec.binaries.PSObject.Properties | Where-Object {$_.Value.package -eq $property.Name}){
        $name=$binary.Name
        if($name -notmatch '^[a-zA-Z0-9_.-]+\.(exe|dll)$'){throw 'Invalid binary filename'}
        & $tar -xf $archive -C $unpack ('mingw64/bin/'+$name)
        if($LASTEXITCODE -ne 0){throw "Package extraction failed: $name"}
        $file=Join-Path $unpack ('mingw64/bin/'+$name)
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $binary.Value.sha256){throw "Binary checksum mismatch: $name"}
        Copy-Item -LiteralPath $file -Destination (Join-Path $toolRoot $name)
    }
    if($package.source_archive){
        if($package.source_archive -notmatch '^sources/[a-zA-Z0-9_.+-]+\.src\.tar\.zst$'){throw 'Invalid source filename'}
        Receive-Pinned $package.source_url $package.source_sha256 (Join-Path $toolRoot $package.source_archive)
    }
}
Write-Output 'Pinned USB tools and corresponding sources are ready.'
