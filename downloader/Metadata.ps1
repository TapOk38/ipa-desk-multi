Add-Type -AssemblyName System.IO.Compression.FileSystem
. (Join-Path $PSScriptRoot 'Localization.ps1')
if (-not ('IpaDeskMetadata' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'Metadata.cs') -ReferencedAssemblies 'System.dll','System.Core.dll','System.Xml.dll' }
function Get-IpaMetadata([string]$Path) {
    $zip=[IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry=@($zip.Entries | Where-Object {$_.FullName -cmatch '^Payload/[^/]+\.app/Info\.plist$'})
        if($entry.Count -ne 1 -or $entry[0].Length -gt 16777216){return @{}}
        $stream=$entry[0].Open();$memory=[IO.MemoryStream]::new()
        try {
            $buffer=New-Object byte[] 8192
            while(($n=$stream.Read($buffer,0,$buffer.Length)) -gt 0){
                if($memory.Length+$n -gt 16777216){return @{}}
                $memory.Write($buffer,0,$n)
            }
            try{return [IpaDeskMetadata]::Read($memory.ToArray())}catch{return @{}}
        } finally {$memory.Dispose();$stream.Dispose()}
    } finally {$zip.Dispose()}
}
function Get-FilePart([string]$Value) {
    return ([regex]::Replace($Value.Trim(),'[\x00-\x1f\s<>:"/\\|?*]+','_')).Trim('.','_',' ')
}
function Get-IpaFileStem([string]$Path,[string]$AppId,[string]$Email,[string]$Description,[string]$Destination) {
    $metadata=Get-IpaMetadata $Path
    $name=[string]$metadata['CFBundleName']
    if(-not $name){$name=[string]$metadata['CFBundleDisplayName']}
    if(-not $name){$name='app-'+$AppId}
    $name=Get-FilePart $name
    if(-not $name){$name='app-'+$AppId}
    $version=Get-FilePart ([string]$metadata['CFBundleShortVersionString'])
    $ios=Get-FilePart ([string]$metadata['MinimumOSVersion'])
    $emailPart=Get-FilePart $Email
    $descriptionPart=Get-FilePart $Description
    $middle=if($version){'_'+$version}else{''}
    if($ios){$middle+='_iOS_'+$ios+'+'}
    $middle+='_'+$emailPart
    # Leave space for extension and duplicate suffix on Windows PowerShell 5.1.
    $budget=[Math]::Min(220,245-$Destination.Length)
    while(($name.Length+$middle.Length+$(if($descriptionPart){1+$descriptionPart.Length}else{0})) -gt $budget){
        if($descriptionPart.Length -gt 12 -and $descriptionPart.Length -ge $name.Length){$descriptionPart=$descriptionPart.Substring(0,$descriptionPart.Length-1)}
        elseif($name.Length -gt 12){$name=$name.Substring(0,$name.Length-1)}
        elseif($descriptionPart.Length -gt 12){$descriptionPart=$descriptionPart.Substring(0,$descriptionPart.Length-1)}
        else{throw (Get-IpaText 'Слишком длинный путь. Переместите папку программы ближе к корню диска.')}
    }
    $stem=$name+$middle
    if($descriptionPart){$stem+='_'+$descriptionPart}
    if($stem -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){$stem='_'+$stem}
    return $stem
}
