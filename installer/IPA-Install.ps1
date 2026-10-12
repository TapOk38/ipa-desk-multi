#requires -Version 5.1
[CmdletBinding()]
param([string]$SmokeTestPath, [ValidateSet('ru','en')][string]$Language)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Localization.ps1')
if ($Language) { Set-InstallerLanguage $Language }
elseif (-not $SmokeTestPath) { Set-InstallerLanguage (Get-InstallerSavedLanguage) }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw (Get-InstallerText 'Запустите IPA-Install.exe.') }
$script:AppRoot = $PSScriptRoot
. (Join-Path $script:AppRoot 'Engine.ps1')
. (Join-Path $script:AppRoot 'Credentials.ps1')
. (Join-Path $script:AppRoot 'AccountWindows.ps1')
$script:Job = $null
$script:DeviceId = ''
$script:DeviceName = ''
$script:PhoneInfo = $null
$script:CredentialOptions = @{}
$script:CredentialKey = 'icloud:default'
$script:PendingAccountDisplay = $false
$script:Closing = $false
$script:TerminalEvent = $false
$script:Bus = [hashtable]::Synchronized(@{ Events = [Collections.Concurrent.ConcurrentQueue[object]]::new(); Cancel = $false })

$form = [Windows.Forms.Form]::new()
$form.Text = (Get-InstallerText 'Установка IPA')
$form.ClientSize = [Drawing.Size]::new(820, 560)
$form.MinimumSize = [Drawing.Size]::new(796, 530)
$form.StartPosition = 'CenterScreen'
$form.AutoScaleMode = 'Dpi'
$form.Font = [Drawing.Font]::new('Segoe UI', 10)
$form.BackColor = [Drawing.Color]::FromArgb(245, 247, 251)
$root = [Windows.Forms.TableLayoutPanel]::new()
$root.Dock = 'Fill'; $root.Padding = [Windows.Forms.Padding]::new(24)
$root.ColumnCount = 1; $root.RowCount = 5
foreach ($height in @(56, 108, 52, 38)) { $null = $root.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', $height)) }
$null = $root.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent', 100))
$form.Controls.Add($root)
$header = [Windows.Forms.Panel]::new(); $header.Dock = 'Fill'
$title = [Windows.Forms.Label]::new(); $title.Text = (Get-InstallerText 'Установка IPA'); $title.AutoSize = $true
$title.Font = [Drawing.Font]::new('Segoe UI', 23, [Drawing.FontStyle]::Bold)
$title.ForeColor = [Drawing.Color]::FromArgb(24, 38, 68)
$header.Controls.Add($title); $root.Controls.Add($header, 0, 0)
$languageSelect = [Windows.Forms.ComboBox]::new(); $languageSelect.DropDownStyle = 'DropDownList'
$languageSelect.Size = [Drawing.Size]::new(115, 28); $languageSelect.Anchor = 'Top,Right'
$languageSelect.Location = [Drawing.Point]::new(650, 10); $languageSelect.AccessibleName = 'Language / Язык'
$null = $languageSelect.Items.AddRange([object[]]@('Русский', 'English'))
$header.Controls.Add($languageSelect)
$header.Add_Resize({ $languageSelect.Left = [Math]::Max(0, $header.ClientSize.Width - $languageSelect.Width) })

$fields = [Windows.Forms.TableLayoutPanel]::new()
$fields.Dock = 'Fill'; $fields.BackColor = [Drawing.Color]::White; $fields.Padding = [Windows.Forms.Padding]::new(16)
$fields.ColumnCount = 3; $fields.RowCount = 2
$null = $fields.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute', 100))
$null = $fields.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100))
$null = $fields.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute', 116))
foreach ($height in @(34, 34)) { $null = $fields.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', $height)) }
$root.Controls.Add($fields, 0, 1)
$ipaLabel = [Windows.Forms.Label]::new(); $ipaLabel.Text = (Get-InstallerText 'IPA-файл'); $ipaLabel.Dock = 'Fill'; $ipaLabel.TextAlign = 'MiddleLeft'
$ipaPath = [Windows.Forms.TextBox]::new(); $ipaPath.ReadOnly = $true; $ipaPath.Dock = 'Fill'; $ipaPath.Margin = [Windows.Forms.Padding]::new(3, 4, 3, 3)
$ipaPath.BackColor = [Drawing.Color]::White; $ipaPath.AllowDrop = $true
$browse = [Windows.Forms.Button]::new(); $browse.Text = (Get-InstallerText 'Выбрать…'); $browse.Dock = 'Fill'
$deviceLabel = [Windows.Forms.Label]::new(); $deviceLabel.Text = 'iPhone'; $deviceLabel.Dock = 'Fill'; $deviceLabel.TextAlign = 'MiddleLeft'
$phoneDisplay = [Windows.Forms.TextBox]::new(); $phoneDisplay.Dock = 'Fill'; $phoneDisplay.ReadOnly = $true; $phoneDisplay.BackColor = [Drawing.Color]::White; $phoneDisplay.Margin = [Windows.Forms.Padding]::new(3, 4, 3, 3)
$refresh = [Windows.Forms.Button]::new(); $refresh.Text = (Get-InstallerText 'Обновить'); $refresh.Dock = 'Fill'
$fields.Controls.Add($ipaLabel, 0, 0); $fields.Controls.Add($ipaPath, 1, 0); $fields.Controls.Add($browse, 2, 0)
$fields.Controls.Add($deviceLabel, 0, 1); $fields.Controls.Add($phoneDisplay, 1, 1); $fields.Controls.Add($refresh, 2, 1)

$actions = [Windows.Forms.FlowLayoutPanel]::new(); $actions.Dock = 'Fill'; $actions.Padding = [Windows.Forms.Padding]::new(0, 6, 0, 0)
function New-Action([string]$Text, [int]$Width) {
    $button = [Windows.Forms.Button]::new(); $button.Text = $Text; $button.Size = [Drawing.Size]::new($Width, 34)
    $button.FlatStyle = 'Flat'; $button.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(207, 215, 227)
    $actions.Controls.Add($button); return $button
}
$start = New-Action (Get-InstallerText 'Установить') 150; $start.Enabled = $false; $start.BackColor = [Drawing.Color]::FromArgb(41, 94, 220); $start.ForeColor = [Drawing.Color]::White
$stop = New-Action (Get-InstallerText 'Отмена') 110; $stop.Enabled = $false
$editAccount = New-Action (Get-InstallerText 'Учётные данные iCloud') 250
$root.Controls.Add($actions, 0, 2)
$statusPanel = [Windows.Forms.TableLayoutPanel]::new(); $statusPanel.Dock = 'Fill'; $statusPanel.ColumnCount = 2
$null = $statusPanel.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100)); $null = $statusPanel.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute', 100))
$status = [Windows.Forms.Label]::new(); $status.Text = (Get-InstallerText 'Подключите iPhone по USB'); $status.Dock = 'Fill'; $status.TextAlign = 'MiddleLeft'; $status.AutoEllipsis = $true
$progress = [Windows.Forms.ProgressBar]::new(); $progress.Dock = 'Fill'; $progress.Margin = [Windows.Forms.Padding]::new(3, 4, 3, 4)
$statusPanel.Controls.Add($status, 0, 0); $statusPanel.Controls.Add($progress, 1, 0); $root.Controls.Add($statusPanel, 0, 3)
$log = [Windows.Forms.TextBox]::new(); $log.Multiline = $true; $log.ScrollBars = 'Vertical'; $log.Dock = 'Fill'; $log.ReadOnly = $true
$log.BackColor = [Drawing.Color]::FromArgb(20, 29, 47); $log.ForeColor = [Drawing.Color]::FromArgb(222, 232, 247)
$log.BorderStyle = 'None'; $log.Font = [Drawing.Font]::new('Consolas', 10)
$root.Controls.Add($log, 0, 4)
function Add-Log([string]$Text) {
    $log.AppendText(('[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $Text + "`r`n"))
    $log.SelectionStart = $log.TextLength; $log.ScrollToCaret()
}
function Update-StartState {
    $start.Enabled = (-not $script:Job -and $script:DeviceId -and [IO.File]::Exists($ipaPath.Text))
    $editAccount.Enabled = (-not $script:Job)
    $languageSelect.Enabled = (-not $script:Job)
}
function Update-InstallerLanguage {
    $form.Text = Get-InstallerText 'Установка IPA'
    $title.Text = Get-InstallerText 'Установка IPA'
    $ipaLabel.Text = Get-InstallerText 'IPA-файл'
    $browse.Text = Get-InstallerText 'Выбрать…'
    $refresh.Text = Get-InstallerText 'Обновить'
    $start.Text = Get-InstallerText 'Установить'
    $stop.Text = Get-InstallerText 'Отмена'
    $editAccount.Text = Get-InstallerText 'Учётные данные iCloud'
    $status.Text = Convert-InstallerText $status.Text
    if ($script:PhoneInfo -and -not $script:PhoneInfo.ProductVersion) {
        $script:PhoneInfo.DisplayName = $script:PhoneInfo.ModelName + ' • ' + (Get-InstallerText 'iOS неизвестна')
        Set-InstallerPhone $script:PhoneInfo
    }
}
$languageSelect.SelectedIndex = if ($script:InstallerLanguage -eq 'ru') { 0 } else { 1 }
$languageSelect.Add_SelectedIndexChanged({
    if ($script:Job) { return }
    Set-InstallerLanguage $(if ($languageSelect.SelectedIndex -eq 0) { 'ru' } else { 'en' })
    Update-InstallerLanguage
    try { Save-InstallerLanguage $script:InstallerLanguage }
    catch { Add-Log (Get-InstallerText 'Не удалось сохранить язык. При следующем запуске выбор может сброситься.') }
})
function Set-InstallerPhone($Device) {
    $script:PhoneInfo = $Device
    $script:DeviceId = ''; $script:DeviceName = ''; $phoneDisplay.Text = ''
    if ($Device) {
        $script:DeviceId = [string]$Device.Id; $script:DeviceName = [string]$Device.DisplayName
        $phoneDisplay.Text = $script:DeviceName
    }
}
function Select-InstallerIpa([string]$Path) {
    $ipaPath.Text = [IO.Path]::GetFullPath($Path); $ipaPath.SelectionStart = $ipaPath.TextLength
    Update-StartState
}
function Start-InstallerJob([string]$Action) {
    if ($script:Job) { return }
    $script:Bus.Cancel = $false; $script:TerminalEvent = $false
    $options = @{ AppRoot = $script:AppRoot; Action = $Action; IpaPath = $ipaPath.Text; DeviceId = ''; Language = $script:InstallerLanguage }
    if ($Action -eq 'install') {
        if (-not $script:DeviceId -or -not [IO.File]::Exists($ipaPath.Text)) { return }
        $options.DeviceId = $script:DeviceId
        Add-Log ((Get-InstallerText 'Файл: ') + [IO.Path]::GetFileName($ipaPath.Text))
        Add-Log ('iPhone: ' + $script:DeviceName)
    }
    if ($Action -eq 'devices') { Set-InstallerPhone $null }
    $fields.Enabled = $false; $start.Enabled = $false; $editAccount.Enabled = $false; $languageSelect.Enabled = $false; $stop.Enabled = $true; $progress.Style = 'Marquee'
    $status.Text = if ($Action -eq 'devices') { (Get-InstallerText 'Поиск iPhone…') } else { (Get-InstallerText 'Подготовка установки…') }
    $runner = $null
    try {
        $runner = [PowerShell]::Create()
        $null = $runner.AddScript('param($EnginePath,$Options,$Bus); . $EnginePath; Invoke-InstallerWorkflow $Options $Bus').AddArgument((Join-Path $script:AppRoot 'Engine.ps1')).AddArgument($options).AddArgument($script:Bus)
        $handle = $runner.BeginInvoke()
        $script:Job = @{ Runner = $runner; Handle = $handle; Action = $Action; IpaPath = $ipaPath.Text }
    } catch {
        if ($runner) { $runner.Dispose() }
        $fields.Enabled = $true; $stop.Enabled = $false; $progress.Style = 'Blocks'
        $status.Text = (Get-InstallerText 'Ошибка запуска'); Add-Log (Get-InstallerText 'Не удалось запустить операцию.'); Update-StartState
    }
}
$browse.Add_Click({
    $picker = [Windows.Forms.OpenFileDialog]::new(); $picker.Title = (Get-InstallerText 'Выберите IPA'); $picker.Filter = (Get-InstallerText 'Приложение iPhone (*.ipa)|*.ipa'); $picker.CheckFileExists = $true; $picker.Multiselect = $false
    try { if ($picker.ShowDialog($form) -eq 'OK') { Select-InstallerIpa $picker.FileName } } finally { $picker.Dispose() }
})
$ipaPath.Add_DragEnter({
    param($sender, $eventArgs)
    if (-not $script:Job -and $eventArgs.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
        $files = @($eventArgs.Data.GetData([Windows.Forms.DataFormats]::FileDrop))
        if ($files.Count -eq 1 -and [IO.Path]::GetExtension($files[0]) -ieq '.ipa') { $eventArgs.Effect = 'Copy' }
    }
})
$ipaPath.Add_DragDrop({
    param($sender, $eventArgs)
    if (-not $script:Job -and $eventArgs.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
        $files = @($eventArgs.Data.GetData([Windows.Forms.DataFormats]::FileDrop))
        if ($files.Count -eq 1 -and [IO.File]::Exists($files[0]) -and [IO.Path]::GetExtension($files[0]) -ieq '.ipa') { Select-InstallerIpa $files[0] }
    }
})
$refresh.Add_Click({ Start-InstallerJob 'devices' })
$start.Add_Click({ Start-InstallerJob 'install' })
$stop.Add_Click({ $script:Bus.Cancel = $true; $stop.Enabled = $false; $status.Text = (Get-InstallerText 'Остановка…') })
$editAccount.Add_Click({
    try { $null = Edit-InstallerAccount $form $script:CredentialKey (Get-InstallerText 'Учётные данные iCloud') $script:CredentialOptions }
    catch { Add-Log (Get-InstallerText 'Не удалось открыть учётные данные в Windows.') }
})
$timer = [Windows.Forms.Timer]::new(); $timer.Interval = 150
$timer.Add_Tick({
    $timer.Stop()
    try {
        $eventItem = $null
        while ($script:Bus.Events.TryDequeue([ref]$eventItem)) {
            switch ($eventItem.Kind) {
                'status' { $status.Text = [string]$eventItem.Data; if ($script:Job -and $script:Job.Action -eq 'install') { Add-Log $status.Text } }
                'devices' {
                    $connected = @($eventItem.Data | Where-Object { $null -ne $_ })
                    Set-InstallerPhone $null
                    if ($connected.Count -eq 1) {
                        Set-InstallerPhone $connected[0]; $status.Text = (Get-InstallerText 'iPhone подключён')
                    } elseif ($connected.Count -eq 0) {
                        $status.Text = (Get-InstallerText 'Подключите iPhone по USB и нажмите «Обновить»')
                    } else { $status.Text = (Get-InstallerText 'Оставьте подключённым один iPhone и нажмите «Обновить»') }
                    $script:TerminalEvent = $true
                }
                'deviceinfo' { Set-InstallerPhone $eventItem.Data }
                'done' {
                    $script:TerminalEvent = $true; $status.Text = (Get-InstallerText 'Приложение установлено'); Add-Log ((Get-InstallerText 'Установлено: ') + $eventItem.Data.Name)
                    $script:PendingAccountDisplay = $true
                }
                'error' { $script:TerminalEvent = $true; $status.Text = (Get-InstallerText 'Ошибка — см. журнал'); Add-Log ([string]$eventItem.Data) }
                'cancelled' { $script:TerminalEvent = $true; $status.Text = (Get-InstallerText 'Остановлено'); Add-Log ([string]$eventItem.Data) }
            }
        }
        if ($script:Job -and $script:Job.Handle.IsCompleted -and $script:Bus.Events.IsEmpty) {
            try {
                $null = $script:Job.Runner.EndInvoke($script:Job.Handle)
                if ($script:Job.Runner.HadErrors -or -not $script:TerminalEvent) { $status.Text = (Get-InstallerText 'Ошибка'); Add-Log (Get-InstallerText 'Операция завершилась без результата. Проверьте файлы программы.') }
            } catch { $status.Text = (Get-InstallerText 'Ошибка'); Add-Log (Get-InstallerText 'Не удалось завершить операцию. Проверьте файлы программы.') }
            finally { $script:Job.Runner.Dispose(); $script:Job = $null; $fields.Enabled = $true; $stop.Enabled = $false; $progress.Style = 'Blocks'; Update-StartState }
        }
        if ($script:PendingAccountDisplay -and -not $script:Job -and -not $script:Closing) {
            $script:PendingAccountDisplay = $false
            try { Show-InstallerAccount $form $script:CredentialKey (Get-InstallerText 'Учётные данные iCloud') $script:CredentialOptions }
            catch { Add-Log (Get-InstallerText 'Не удалось открыть учётные данные в Windows.') }
        }
        if ($script:Closing -and -not $script:Job) { $form.Close() }
    } finally { if (-not $form.IsDisposed) { $timer.Start() } }
})
$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($script:Job) { $eventArgs.Cancel = $true; $script:Closing = $true; $script:Bus.Cancel = $true; $status.Text = (Get-InstallerText 'Остановка…') }
})
if ($SmokeTestPath) {
    # Exercise both languages with synthetic state; never read credentials, scan
    # USB devices or persist a preference during the isolated startup check.
    $initialLanguage = $script:InstallerLanguage
    $testIpa = Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($SmokeTestPath))) 'sample.ipa'
    $ipaPath.Text = $testIpa
    Set-InstallerPhone ([pscustomobject]@{ Id='fixture'; ModelName='iPhone'; ProductVersion='18.0'; DisplayName='iPhone • iOS 18.0' })
    foreach ($testLanguage in @('ru','en')) {
        Set-InstallerLanguage $testLanguage
        Update-InstallerLanguage
        if ($ipaPath.Text -cne $testIpa -or $script:DeviceId -cne 'fixture' -or $phoneDisplay.Text -cne 'iPhone • iOS 18.0') { throw 'Language switch changed input state' }
        if ($testLanguage -eq 'en' -and ($start.Text -cne 'Install' -or $browse.Text -cne 'Browse…' -or $editAccount.Text -cne 'iCloud credentials')) { throw 'English controls did not update' }
        if ($testLanguage -eq 'ru' -and $start.Text -cne 'Установить') { throw 'Russian controls did not update' }
    }
    $script:Job = @{ Action='install' }; Update-StartState
    if ($languageSelect.Enabled) { throw 'Language selector must be disabled during installation' }
    $script:Job = $null; Update-StartState
    if (-not $languageSelect.Enabled) { throw 'Language selector did not unlock after installation' }
    $ipaPath.Text = ''; Set-InstallerPhone $null
    Set-InstallerLanguage $initialLanguage; Update-InstallerLanguage; Update-StartState
    $form.Opacity = 0; $form.ShowInTaskbar = $false; $form.Show(); $form.PerformLayout(); [Windows.Forms.Application]::DoEvents()
    $bitmap = [Drawing.Bitmap]::new($form.Width, $form.Height)
    try { $form.DrawToBitmap($bitmap, [Drawing.Rectangle]::new(0, 0, $form.Width, $form.Height)); $bitmap.Save($SmokeTestPath, [Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose(); $form.Dispose() }
    return
}
$form.Add_Shown({ Start-InstallerJob 'devices' })
$timer.Start()
try { $null = $form.ShowDialog() } finally { $timer.Stop(); $timer.Dispose(); $form.Dispose() }
