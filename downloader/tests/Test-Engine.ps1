param([string]$WorkRoot=[IO.Path]::GetTempPath())
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$test=Join-Path $WorkRoot ('test-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$null=[IO.Directory]::CreateDirectory($test)
$environment=[Environment]::GetEnvironmentVariables(); $names=@($environment.Keys | Where-Object {$_ -ieq 'PATH'})
if($names.Count -gt 1){$v=$environment[$names[0]];foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$null,'Process')};[Environment]::SetEnvironmentVariable('Path',$v,'Process')}
. (Join-Path $root 'Accounts.ps1')
Set-IpaLanguage 'ru'
$script:Count=0
function Assert($Condition,[string]$Message){if(-not $Condition){throw "FAIL: $Message"};$script:Count++;Write-Output "PASS: $Message"}
Assert ((Resolve-AppId 'https://apps.apple.com/ru/app/example/id6746845077?l=ru') -eq '6746845077') 'App Store URL resolves exactly'
foreach($q in @('0','-1','abc','https://apps.apple.com.evil.test/id12','https://other.test/id12','https://apps.apple.com/id12/extra')){
    $rejected=$false;try{Resolve-AppId $q | Out-Null}catch{$rejected=$true};Assert $rejected "Invalid app reference rejected: $q"
}
$cipher=Lock-Password 'pw test&"\'
Assert ((Unlock-Password $cipher) -ceq 'pw test&"\') 'Real Windows DPAPI roundtrip'
$saved=Join-Path $test 'accounts.json'
$a=[pscustomobject]@{Id=[guid]::NewGuid().ToString('N');Email='alpha@example.invalid';Password=$cipher}
Write-Accounts $saved @($a)
Assert (@(Read-Accounts $saved).Count -eq 1) 'Saved account reloads'
Assert (-not [IO.File]::ReadAllText($saved).Contains('pw test')) 'Account file contains no plaintext password'
Write-Accounts $saved @()
Assert (@(Read-Accounts $saved).Count -eq 0) 'Deleting last account persists empty list'
[IO.File]::WriteAllText($saved,'broken')
$rejected=$false;try{Read-Accounts $saved | Out-Null}catch{$rejected=$true}
Assert ($rejected -and [IO.File]::ReadAllText($saved) -eq 'broken') 'Corrupt store rejected without overwriting'
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'FakeCppTool.cs'))
$fake=Join-Path $test 'fake.exe'
Add-Type -TypeDefinition $source -OutputAssembly $fake -OutputType ConsoleApplication -ReferencedAssemblies 'System.Web.Extensions.dll','System.Core.dll','System.IO.Compression.dll','System.IO.Compression.FileSystem.dll'
$unicodeToolFolder=Join-Path $test 'Программа с кириллицей'
$null=[IO.Directory]::CreateDirectory($unicodeToolFolder)
Copy-Item -LiteralPath $fake -Destination $unicodeToolFolder
$fake=Join-Path $unicodeToolFolder 'fake.exe'
function Run-Case([string]$Scenario,[bool]$Cancel=$false,[string]$Email='test@example.invalid',[string]$FolderPrefix='', [string]$Description='', [string]$EnginePath=(Join-Path $root 'Engine.ps1'), [string]$Language='ru',[string[]]$AppIds=@(),[switch]$History,[switch]$CancelAfterFirst){
    $env:IPA_DESK_TEST_SCENARIO=$Scenario
    $folder=Join-Path $test ($FolderPrefix+[guid]::NewGuid().ToString('N'))
    $null=[IO.Directory]::CreateDirectory($folder);[IO.File]::WriteAllText((Join-Path $folder ('app-101_'+$Email+'.ipa')),'existing')
    $options=@{AppRoot=$root;DataRoot=(Join-Path $test 'sessions');Language=$Language;Email=$Email;Description=$Description;EncryptedPassword=$cipher;Password='';AppId='101';OutputFolder=$folder;FileName='';ToolPath=$fake}
    if($AppIds.Count){$options.Downloads=@(foreach($id in $AppIds){[pscustomobject]@{AppId=$id;OutputFolder=(Join-Path $folder $id)}})}
    if($History){$options.Mode='purchases'}
    $bus=[hashtable]::Synchronized(@{Events=[Collections.Concurrent.ConcurrentQueue[object]]::new();Cancel=$false;Answer=$null;AnswerReady=$false})
    $events=[Collections.Generic.List[object]]::new();$runner=[PowerShell]::Create()
    $null=$runner.AddScript('param($Path,$Options,$Bus); . $Path; function Resolve-CppTool { return $script:Options.ToolPath }; Invoke-Workflow $Options $Bus').AddArgument($EnginePath).AddArgument($options).AddArgument($bus)
    $watch=[Diagnostics.Stopwatch]::StartNew();$handle=$runner.BeginInvoke()
    try{
        do{
            $event=$null
            while($bus.Events.TryDequeue([ref]$event)){
                $events.Add($event)
                if($CancelAfterFirst -and $event.Kind -eq 'app-done'){$bus.Cancel=$true}
                if($event.Kind -eq 'code'){if($Cancel){$bus.Cancel=$true}else{$bus.Answer='123456';$bus.AnswerReady=$true}}
            }
            if($Scenario -in @('slow','download-slow','owned-cancel') -and $watch.Elapsed.TotalSeconds -gt 2){$bus.Cancel=$true}
            if($watch.Elapsed.TotalSeconds -gt 25){$bus.Cancel=$true;throw 'Timeout'}
            Start-Sleep -Milliseconds 20
        }while(-not $handle.IsCompleted -or -not $bus.Events.IsEmpty)
        $null=$runner.EndInvoke($handle);if($runner.HadErrors){throw $runner.Streams.Error[0]}
    }finally{$runner.Dispose()}
    [pscustomobject]@{Events=$events.ToArray();Folder=$folder;Options=$options;Seconds=$watch.Elapsed.TotalSeconds}
}
$env:IPA_DESK_TEST_AUDIT=Join-Path $test 'audit.jsonl'
$env:IPA_DESK_TEST_DOWNLOAD_AUDIT=Join-Path $test 'download-audit.jsonl'
$initialDirectory=[Environment]::CurrentDirectory
try{
    $unicode=Run-Case 'no-twofa' $false 'test@example.invalid' 'Русская папка [1]-' 'Работа Иркутск'
    $unicodeDone=@($unicode.Events | Where-Object Kind -eq done)
    if(-not $unicodeDone.Count){$unicode.Events | ConvertTo-Json -Depth 4 | Write-Output}
    Assert ($unicodeDone.Count -eq 1) 'v3 saves to Cyrillic directory with spaces and brackets'
    Assert ([IO.File]::Exists($unicodeDone[0].Data.Path) -and [IO.Path]::GetFileName($unicodeDone[0].Data.Path) -ceq 'app-101_test@example.invalid_Работа_Иркутск.ipa') 'Final Unicode description is preserved'
    Assert (@(Get-ChildItem -LiteralPath $unicode.Folder -Filter '*.tmp' -Force).Count -eq 0) 'Native temporary download is cleaned after success'
    $happy=Run-Case 'happy'
    $done=@($happy.Events | Where-Object Kind -eq done)
    if(-not $done.Count){$happy.Events | ConvertTo-Json -Depth 4 | Write-Output}
    Assert ($done.Count -eq 1) 'Acquire license and download by ID succeeds'
    Assert (@($happy.Events | Where-Object Kind -eq code).Count -eq 1) '2FA prompt is handled'
    Assert ([IO.File]::ReadAllText((Join-Path $happy.Folder 'app-101_test@example.invalid.ipa')) -eq 'existing') 'Existing IPA is preserved'
    Assert ([IO.Path]::GetFileName($done[0].Data.Path) -eq 'app-101_test@example.invalid (1).ipa') 'Repeated download uses a unique name'
    Assert (-not $happy.Options.Password -and -not $happy.Options.Passphrase) 'Worker clears decrypted credentials'
    foreach($scenario in @('login-fail','wrong-account','twofa-network','missing-file','bad-zip','download-fail','license')){
        $case=Run-Case $scenario
        Assert (@($case.Events | Where-Object Kind -eq error).Count -eq 1 -and @($case.Events | Where-Object Kind -eq done).Count -eq 0) "$scenario cannot report success"
        Assert (@(Get-ChildItem -LiteralPath $case.Folder -Filter '*.partial.ipa' -Force).Count -eq 0) "$scenario removes partial files"
        Assert (@(Get-ChildItem -LiteralPath $case.Folder -Filter '*.tmp' -Force).Count -eq 0) "$scenario removes native temporary files"
        $serialized=$case.Events | ConvertTo-Json -Depth 5
        Assert (-not $serialized.Contains('pw test') -and -not $serialized.Contains('123456')) "$scenario masks password and code"
    }
    $case=Run-Case 'happy' $true
    Assert (@($case.Events | Where-Object Kind -eq cancelled).Count -eq 1) 'Cancel while waiting for 2FA'
    $case=Run-Case 'slow'
    Assert (@($case.Events | Where-Object Kind -eq cancelled).Count -eq 1 -and $case.Seconds -lt 8) 'Cancel terminates a running native process'
    $case=Run-Case 'download-slow' $false 'test@example.invalid' 'Остановка загрузки-'
    Assert (@($case.Events | Where-Object Kind -eq cancelled).Count -eq 1 -and $case.Seconds -lt 8) 'Cancel terminates native download in Unicode directory'
    Assert (@(Get-ChildItem -LiteralPath $case.Folder -Filter '*.tmp' -Force).Count -eq 0) 'Cancel removes raw temporary download'
    foreach($email in @('alpha@example.invalid','bravo@example.invalid','alpha@example.invalid')){
        $case=Run-Case 'no-twofa' $false $email
        Assert (@($case.Events | Where-Object Kind -eq done).Count -eq 1) "Fresh login for $email"
    }
    $audit=@(Get-Content -LiteralPath $env:IPA_DESK_TEST_AUDIT -Encoding UTF8 | ForEach-Object {ConvertFrom-Json $_})
    Assert (@($audit.profile | Select-Object -Unique).Count -eq $audit.Count) 'Accounts never reuse a previous session profile'
    Assert (@($audit | Where-Object {Test-Path -LiteralPath $_.profile}).Count -eq 0) 'Temporary session profiles are removed'
    $downloads=@(Get-Content -LiteralPath $env:IPA_DESK_TEST_DOWNLOAD_AUDIT -Encoding UTF8 | ForEach-Object {ConvertFrom-Json $_})
    Assert (@($downloads | Where-Object {$_.output -match '[^\x00-\x7f]' -or [IO.Path]::IsPathRooted($_.output)}).Count -eq 0) 'v3 native downloads receive only relative ASCII filenames'
    Assert (@($downloads | Where-Object {$_.cwd -eq $unicode.Folder}).Count -eq 1) 'Unicode destination reaches actual child process through WorkingDirectory'
    Assert ([Environment]::CurrentDirectory -ceq $initialDirectory) 'Parent working directory is unchanged'
    $english=Run-Case 'happy' -Language 'en'
    Assert (@($english.Events | Where-Object Kind -eq done).Count -eq 1) 'English worker completes the 2FA and download workflow'
    Assert (@($english.Events | Where-Object { $_.Kind -eq 'code' -and $_.Data -like 'Enter the code for *' }).Count -eq 1) 'English 2FA prompt reaches the UI event queue'
    Assert (@($english.Events | Where-Object { $_.Kind -eq 'status' -and $_.Data -eq 'Downloading IPA…' }).Count -eq 1) 'English download status reaches the UI event queue'
    $englishError=Run-Case 'license' -Language 'en'
    Assert (@($englishError.Events | Where-Object { $_.Kind -eq 'error' -and $_.Data -like 'Download failed. Apple did not confirm a license*' }).Count -eq 1) 'English application error reaches the UI event queue'
    $beforeAudit=@(Get-Content -LiteralPath $env:IPA_DESK_TEST_AUDIT).Count
    $batch=Run-Case 'batch-mixed' -AppIds @('101','202','303')
    Assert (@($batch.Events | Where-Object Kind -eq app-done).Count -eq 2) 'Batch continues after an unavailable app and saves both other apps'
    Assert (@($batch.Events | Where-Object Kind -eq app-error).Count -eq 1) 'Batch reports failure against the correct app'
    Assert (@($batch.Events | Where-Object Kind -eq code).Count -eq 1) 'One 2FA exchange for the full account batch'
    Assert ((@(Get-Content -LiteralPath $env:IPA_DESK_TEST_AUDIT).Count-$beforeAudit) -eq 1) 'Batch uses one authenticated session'
    $summary=@($batch.Events | Where-Object Kind -eq batch-done)[0].Data
    Assert ($summary.Succeeded -eq 2 -and $summary.Failed -eq 1) 'Batch totals distinguish successful and failed downloads'
    $done=@($batch.Events | Where-Object Kind -eq app-done)
    Assert ($done[0].Data.AppId -eq '101' -and $done[1].Data.AppId -eq '303') 'Batch keeps app order and skips only the failed app'
    Assert ((Split-Path (Split-Path $done[1].Data.Path -Parent) -Leaf) -eq '303') 'Each app has its own destination folder'
    Assert (-not $batch.Options.Password -and -not $batch.Options.Passphrase) 'Batch clears credentials after all downloads'
    $batch=Run-Case 'batch-ok' -AppIds @('101')
    Assert (@($batch.Events | Where-Object Kind -eq app-done).Count -eq 1) 'A single-entry batch works'
    $batch=Run-Case 'batch-ok' -AppIds @('101','202','303') -CancelAfterFirst
    Assert (@($batch.Events | Where-Object Kind -eq cancelled).Count -eq 1 -and @($batch.Events | Where-Object Kind -eq batch-done).Count -eq 0) 'Cancellation stops a batch without reporting it complete'
    $batch=Run-Case 'login-fail' -AppIds @('101','202')
    Assert (@($batch.Events | Where-Object Kind -eq app-start).Count -eq 0 -and @($batch.Events | Where-Object Kind -eq error).Count -eq 1) 'Login failure starts no downloads'
    $history=Run-Case 'owned-pages' -History
    $owned=@($history.Events | Where-Object Kind -eq purchases)
    Assert ($owned.Count -eq 1 -and @($owned[0].Data).Count -eq 101) 'Purchase history merges years and deduplicates apps without a public store search'
    Assert (@($owned[0].Data | Where-Object Id -eq '909').Count -eq 0 -and $owned[0].Data[0].Name -eq 'App 1') 'Non-app purchases are excluded and latest app name is preserved'
    Assert (@($history.Events | Where-Object { $_.Kind -eq 'log' -and $_.Data -like 'Проверен * год.*' }).Count -eq ([DateTime]::Now.Year-2007)) 'Every year is queried, including empty years back to 2008'
    Assert (@($history.Events | Where-Object Kind -eq done).Count -eq 0) 'Reading purchase history does not download an app'
    $history=Run-Case 'owned-unknown' -History
    $owned=@($history.Events | Where-Object Kind -eq purchases)
    Assert ($owned.Count -eq 1 -and @($owned[0].Data).Count -eq 1 -and $owned[0].Data[0].Id -eq '404') 'Old delisted purchase remains visible across empty years without a public lookup'
    $history=Run-Case 'owned-empty' -History
    $owned=@($history.Events | Where-Object Kind -eq purchases)
    Assert ($owned.Count -eq 1 -and @($owned[0].Data).Count -eq 0) 'Empty purchase history is a valid response'
    foreach($scenario in @('owned-offline','owned-late-error','owned-malformed','owned-invalid-shape','wrong-account')){
        $history=Run-Case $scenario -History
        Assert (@($history.Events | Where-Object Kind -eq purchases).Count -eq 0 -and @($history.Events | Where-Object Kind -eq error).Count -eq 1) "$scenario never returns another account or partial history"
        Assert (($history.Events | ConvertTo-Json -Depth 5) -notmatch 'PRIVATE-INVOICE-DATA') "$scenario does not expose raw invoice data"
    }
    $history=Run-Case 'owned-cancel' -History
    Assert (@($history.Events | Where-Object Kind -eq cancelled).Count -eq 1 -and @($history.Events | Where-Object Kind -eq purchases).Count -eq 0 -and $history.Seconds -lt 8) 'Cancelling history terminates the request without returning a partial list'
    Write-Output "$script:Count checks passed; real DPAPI, simulated Apple responses."
}finally{$env:IPA_DESK_TEST_SCENARIO=$null;$env:IPA_DESK_TEST_AUDIT=$null;$env:IPA_DESK_TEST_DOWNLOAD_AUDIT=$null}
