#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$ReportRoot)
$ErrorActionPreference='Stop'
$null=[IO.Directory]::CreateDirectory($ReportRoot)
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$started=Get-Date
$report=[ordered]@{Started=$started.ToString('o');AppExecuted=$false;Scans=@();Error=$null}
try {
    $service=Get-Service WinDefend
    if($service.Status -ne 'Running'){Start-Service WinDefend}
    Update-MpSignature
    $status=Get-MpComputerStatus
    if(-not $status.AntivirusEnabled){throw 'Defender Antivirus is not enabled on this runner'}
    $report.Defender=$status | Select-Object AntivirusEnabled,RealTimeProtectionEnabled,AMProductVersion,AMEngineVersion,AntivirusSignatureVersion,AntivirusSignatureLastUpdated
    $scanner=Get-ChildItem "$env:ProgramData/Microsoft/Windows Defender/Platform" -Directory | Sort-Object Name -Descending | Select-Object -First 1
    $scanner=Join-Path $scanner.FullName 'MpCmdRun.exe'
    function Scan-Target($Name,$Path){
        $scanStart=Get-Date
        $before=if([IO.File]::Exists($Path)){(Get-FileHash -LiteralPath $Path).Hash}else{$null}
        # This diagnostic mode scans archives and ignores runner file exclusions.
        # It does not change Defender settings or execute any scanned file.
        $scanLog=Join-Path $ReportRoot ($Name+'.txt')
        & $scanner -Scan -ScanType 3 -File $Path -DisableRemediation 2>&1 | Out-File $scanLog -Encoding utf8
        $exitCode=$LASTEXITCODE
        $scanText=[IO.File]::ReadAllText($scanLog)
        $completed=($scanText -match 'found no threats' -and $scanText -notmatch '(?i)skipped')
        $detections=@(Get-MpThreatDetection | Where-Object InitialDetectionTime -ge $scanStart | Select-Object ThreatID,ActionSuccess,InitialDetectionTime,Resources)
        $report.Scans+=@{Name=$Name;ExitCode=$exitCode;SHA256=$before;Detections=$detections;ScanCompleted=$completed;Output=$scanText}
        if($exitCode -ne 0 -or $detections.Count -or -not $completed){throw "Defender did not clear $Name. See scan report."}
    }
    Scan-Target 'source' $root
    . (Join-Path $root 'Install-Tools.ps1')
    $tool=Ensure-IpaTool -AppRoot $root
    Scan-Target 'ipatool-cpp' $tool
    $build=Join-Path $env:RUNNER_TEMP 'review-build'
    & (Join-Path $root 'Build-Exe.ps1') -Destination $build | Out-File (Join-Path $ReportRoot 'build.txt') -Encoding utf8
    $exe=@(Get-ChildItem -LiteralPath $build -Filter '*.exe')
    if($exe.Count -ne 1){throw 'Expected one built executable'}
    Scan-Target 'application-exe' $exe[0].FullName
} catch {
    $report.Error=$_.Exception.Message
    Write-Warning $report.Error
} finally {
    try {
        $report.Events=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational';Id=1116,1117;StartTime=$started} -ErrorAction SilentlyContinue | Select-Object TimeCreated,Id,Message)
    } catch { $report.EventReadError=$_.Exception.Message }
    $report | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $ReportRoot 'result.json') -Encoding utf8
}
if($report.Error){throw $report.Error}
