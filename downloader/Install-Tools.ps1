#requires -Version 5.1
param([string]$ArchivePath)
. (Join-Path $PSScriptRoot 'Localization.ps1')
# Fixed release and hashes, never execute downloaded PowerShell or select 'latest'.
function Get-IpaToolSpec {
    return @{
        Version='1.0.9'
        Url='https://github.com/Sorvigolova/ipatool/releases/download/1.0.9/windows_amd64_ipatool-cpp.zip'
        ArchiveSha256='264BE72D4B70E8A5540647277690FB47FCF1D7D6178ACF84629E93C0E564A331'
        Entry='ipatool-cpp-windows-amd64.exe'
        ExeSha256='394E8953D317F39645F03A1BFE039D0DC0FFC04291EB9D0F535BD1BBCA4F4581'
    }
}
function Test-ToolCancellation([scriptblock]$Check) {
    if ($Check -and (& $Check)) { throw [OperationCanceledException]::new((Get-IpaText 'Подготовка компонента отменена.')) }
}
function Receive-PinnedTool([string]$Url,[string]$Destination,[scriptblock]$Cancelled) {
    Add-Type -AssemblyName System.Net.Http
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $client=[Net.Http.HttpClient]::new(); $client.Timeout=[TimeSpan]::FromMinutes(5)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('IPA-Desk-Multi/0.4.0-beta.2')
    $cts=[Threading.CancellationTokenSource]::new(); $response=$null; $inputStream=$null; $outputStream=$null
    try {
        $request=$client.GetAsync($Url,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$cts.Token)
        while(-not $request.IsCompleted){Test-ToolCancellation $Cancelled; Start-Sleep -Milliseconds 100}
        $response=$request.GetAwaiter().GetResult(); $null=$response.EnsureSuccessStatusCode()
        if($response.Content.Headers.ContentLength -gt 40MB){throw (Get-IpaText 'Слишком большой архив компонента.')}
        $inputStream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $outputStream=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=New-Object byte[] 65536; $total=0L; $watch=[Diagnostics.Stopwatch]::StartNew()
        while($true){
            Test-ToolCancellation $Cancelled
            $read=$inputStream.ReadAsync($buffer,0,$buffer.Length,$cts.Token)
            while(-not $read.IsCompleted){
                Test-ToolCancellation $Cancelled
                if($watch.Elapsed.TotalMinutes -gt 5){throw (Get-IpaText 'Превышено время загрузки компонента.')}
                Start-Sleep -Milliseconds 100
            }
            $count=$read.GetAwaiter().GetResult(); if($count -eq 0){break}
            $total+=$count; if($total -gt 40MB){throw (Get-IpaText 'Слишком большой архив компонента.')}
            $outputStream.Write($buffer,0,$count)
        }
    } finally {
        $cts.Cancel()
        if($outputStream){$outputStream.Dispose()}; if($inputStream){$inputStream.Dispose()}
        if($response){$response.Dispose()}; $client.Dispose(); $cts.Dispose()
    }
}
function Ensure-IpaTool([string]$AppRoot,[string]$LocalArchive='',[scriptblock]$Cancelled) {
    $ErrorActionPreference='Stop'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Test-ToolCancellation $Cancelled
    $spec=Get-IpaToolSpec
    $folder=Join-Path $AppRoot ('tools\cpp-'+$spec.Version)
    $exe=Join-Path $folder 'ipatool-cpp.exe'
    if([IO.File]::Exists($exe)){
        if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $spec.ExeSha256){throw (Get-IpaText 'Компонент IPATool повреждён или имеет другую версию. Удалите только tools\cpp-1.0.9 и повторите запуск.')}
        return $exe
    }
    $null=[IO.Directory]::CreateDirectory($folder)
    $lock=$null; $work=$null; $archive=$null; $unpacked=$null
    try {
        $lock=[IO.File]::Open((Join-Path $folder '.install.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        # Recheck after obtaining the lock; another process may have finished.
        if([IO.File]::Exists($exe)){
            if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $spec.ExeSha256){throw (Get-IpaText 'Неверная контрольная сумма IPATool.')}
            return $exe
        }
        $work=Join-Path $folder ('.install-'+[guid]::NewGuid().ToString('N'))
        $null=[IO.Directory]::CreateDirectory($work)
        $archive=Join-Path $work 'download.zip'; $unpacked=Join-Path $work 'tool.exe'
        if($LocalArchive){[IO.File]::Copy([IO.Path]::GetFullPath($LocalArchive),$archive,$false)}
        else {Receive-PinnedTool $spec.Url $archive $Cancelled}
        Test-ToolCancellation $Cancelled
        if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $spec.ArchiveSha256){throw (Get-IpaText 'Контрольная сумма архива IPATool не совпала. Компонент не установлен.')}
        $zip=[IO.Compression.ZipFile]::OpenRead($archive)
        try {
            $entries=@($zip.Entries | Where-Object {$_.FullName -ceq $spec.Entry})
            if($entries.Count -ne 1 -or $entries[0].Length -gt 80MB){throw (Get-IpaText 'Неверное содержимое архива IPATool.')}
            # Extract one exact member to our own filename, never arbitrary ZIP paths.
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0],$unpacked,$false)
        } finally {$zip.Dispose()}
        if((Get-FileHash -LiteralPath $unpacked -Algorithm SHA256).Hash -ne $spec.ExeSha256){throw (Get-IpaText 'Контрольная сумма IPATool не совпала. Компонент не установлен.')}
        Test-ToolCancellation $Cancelled
        [IO.File]::Move($unpacked,$exe)
        return $exe
    } finally {
        try {
            foreach($file in @($archive,$unpacked)){if($file -and [IO.File]::Exists($file)){[IO.File]::Delete($file)}}
            if($work -and [IO.Directory]::Exists($work)){[IO.Directory]::Delete($work,$false)}
        } finally {if($lock){$lock.Dispose()}}
    }
}
if($MyInvocation.InvocationName -ne '.'){
    Ensure-IpaTool -AppRoot $PSScriptRoot -LocalArchive $ArchivePath
}
