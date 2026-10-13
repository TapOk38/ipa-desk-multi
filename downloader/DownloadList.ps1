#requires -Version 5.1
. (Join-Path $PSScriptRoot 'Accounts.ps1')

function Resolve-DownloadList([string]$Text) {
    $seen = @{}
    $lineNumber = 0
    foreach ($line in ($Text -split '\r?\n')) {
        $lineNumber++
        if (-not $line.Trim()) { continue }
        try { $id = Resolve-AppId $line }
        catch { throw ((Get-IpaText 'Строка {0}: {1}') -f $lineNumber, $_.Exception.Message) }
        if (-not $seen.ContainsKey($id)) { $seen[$id] = $true; $id }
    }
}
function Read-DownloadList([string]$Path) {
    return (@(Read-DownloadEntries $Path | ForEach-Object Id) -join "`r`n")
}
function Read-DownloadEntries([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return }
    try {
        $data = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        if ($data.Version -notin @(1,2) -or $null -eq $data.Apps) { throw 'format' }
        $entries = if ($data.Version -eq 1) { @(foreach($id in $data.Apps){[pscustomobject]@{Id=$id;Name='';Selected=$true}}) } else { @($data.Apps) }
        ConvertTo-DownloadEntries $entries
    } catch { throw (Get-IpaText 'Не удалось прочитать список приложений. Исходный файл не изменён.') }
}
function Save-DownloadList([string]$Path, [string]$Text) {
    $ids = @(Resolve-DownloadList $Text)
    Write-DownloadEntries $Path @(foreach($id in $ids){[pscustomobject]@{Id=$id;Name='';Selected=$true}})
}
function ConvertTo-DownloadEntries([object[]]$Entries) {
    $seen=@{}
    foreach($entry in $Entries){
        if($null -eq $entry -or -not $entry.PSObject.Properties['Id']){throw (Get-IpaText 'Некорректный список приложений.')}
        $id=Resolve-AppId ([string]$entry.Id)
        if($seen.ContainsKey($id)){throw (Get-IpaText 'Это приложение уже добавлено.')}
        $seen[$id]=$true
        $name=if($entry.PSObject.Properties['Name']){([string]$entry.Name).Trim()}else{''}
        if($name.Length -gt 200){throw (Get-IpaText 'Название должно содержать не более 200 символов.')}
        $selected=$true
        if($entry.PSObject.Properties['Selected']){
            if($entry.Selected -isnot [bool]){throw (Get-IpaText 'Некорректный список приложений.')}
            $selected=$entry.Selected
        }
        [pscustomobject]@{Id=$id;Name=$name;Selected=$selected}
    }
}
function Write-DownloadEntries([string]$Path, [object[]]$Entries) {
    $apps=@(ConvertTo-DownloadEntries $Entries)
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $json = @{ Version = 2; Apps = $apps } | ConvertTo-Json -Depth 3
        [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
