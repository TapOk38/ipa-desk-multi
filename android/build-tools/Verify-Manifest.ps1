param([Parameter(Mandatory=$true)][string]$Apk, [Parameter(Mandatory=$true)][string]$Aapt2)
$ErrorActionPreference = 'Stop'
$tree = (& $Aapt2 dump xmltree $Apk --file AndroidManifest.xml) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Cannot read the packaged Android manifest.' }
$sdk = $tree.IndexOf('E: uses-sdk ')
$app = $tree.IndexOf('E: application ')
if ($sdk -lt 0 -or $app -lt 0 -or $sdk -gt $app) {
    throw 'The packaged uses-sdk must precede application to avoid legacy window compatibility defaults.'
}
if ($tree -notmatch 'minSdkVersion\([^)]*\)=26' -or $tree -notmatch 'targetSdkVersion\([^)]*\)=35') {
    throw 'Unexpected SDK versions in the packaged manifest.'
}
if ($tree -notmatch '(?s)E: activity .*?resizeableActivity\([^)]*\)=true') {
    throw 'The packaged activity must support resizable screens.'
}
Write-Output 'Packaged manifest verified: SDK order, SDK versions and resizable activity.'
