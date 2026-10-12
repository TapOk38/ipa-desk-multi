#requires -Version 5.1
param([string]$SmokeTestPath, [string]$TestDataRoot, [string]$OutputRoot)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Запустите Start.cmd.' }
. (Join-Path $PSScriptRoot 'Accounts.ps1')
# Some launch environments contain both PATH and Path. .NET requires unique keys.
$environment = [Environment]::GetEnvironmentVariables()
$pathKeys = @($environment.Keys | Where-Object { $_ -ieq 'PATH' })
if ($pathKeys.Count -gt 1) {
    $pathValue = $environment[$pathKeys[0]]
    foreach ($key in $pathKeys) { [Environment]::SetEnvironmentVariable($key, $null, 'Process') }
    [Environment]::SetEnvironmentVariable('Path', $pathValue, 'Process')
}
$script:AppRoot = $PSScriptRoot
$script:OutputRoot = if ($OutputRoot) { [IO.Path]::GetFullPath($OutputRoot) } else { Join-Path $script:AppRoot 'Downloads' }
$script:DataRoot = if ($TestDataRoot) { [IO.Path]::GetFullPath($TestDataRoot) } elseif ($SmokeTestPath) { Join-Path ([IO.Path]::GetTempPath()) ('ipa-multi-smoke-' + [guid]::NewGuid().ToString('N')) } else { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'IPA-Desk-Multi' }
$script:AccountsPath = Join-Path $script:DataRoot 'accounts.json'
$script:StoreLock = $null
try {
    $null = [IO.Directory]::CreateDirectory($script:DataRoot)
    $script:StoreLock = [IO.File]::Open((Join-Path $script:DataRoot 'accounts.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $script:Accounts = [Collections.Generic.List[object]]::new()
    foreach ($a in @(Read-Accounts $script:AccountsPath)) { if ($a) { $script:Accounts.Add($a) } }
} catch {
    if ($script:StoreLock) { $script:StoreLock.Dispose() }
    $null = [Windows.Forms.MessageBox]::Show(('Не удалось открыть учётки. Закройте другое окно IPA-Desk Multi, если оно открыто.' + "`n" + $_.Exception.Message), 'IPA-Desk Multi')
    return
}
$script:Job = $null; $script:Active = $false; $script:Closing = $false; $script:StopRequested = $false
$script:Queue = @(); $script:Next = 0; $script:Success = 0; $script:Failed = 0
$script:Current = $null; $script:Terminal = $false; $script:Secrets = @()
$script:Bus = [hashtable]::Synchronized(@{ Events=[Collections.Concurrent.ConcurrentQueue[object]]::new(); Cancel=$false; Answer=$null; AnswerReady=$false })

$form = [Windows.Forms.Form]::new(); $form.Text = 'Выгрузка IPA — учётки'
$form.ClientSize = [Drawing.Size]::new(860, 660); $form.MinimumSize = [Drawing.Size]::new(820, 680)
$form.StartPosition = 'CenterScreen'; $form.AutoScaleMode = 'Dpi'
$form.Font = [Drawing.Font]::new('Segoe UI', 10); $form.BackColor = [Drawing.Color]::FromArgb(245,247,251)
$root = [Windows.Forms.TableLayoutPanel]::new(); $root.Dock = 'Fill'; $root.Padding = [Windows.Forms.Padding]::new(24)
$root.ColumnCount = 1; $root.RowCount = 7
foreach ($height in @(60,58,54,230,54,32)) { $null = $root.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',$height)) }
$null = $root.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100)); $form.Controls.Add($root)
$title = [Windows.Forms.Label]::new(); $title.Text = 'Выгрузка IPA'; $title.Dock = 'Fill'; $title.Font = [Drawing.Font]::new('Segoe UI',23,[Drawing.FontStyle]::Bold); $title.ForeColor = [Drawing.Color]::FromArgb(24,38,68)
$root.Controls.Add($title,0,0)
$fields = [Windows.Forms.TableLayoutPanel]::new(); $fields.Dock='Fill'; $fields.BackColor=[Drawing.Color]::White; $fields.Padding=[Windows.Forms.Padding]::new(10)
$fields.ColumnCount=2; $null=$fields.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',150)); $null=$fields.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100))
$label=[Windows.Forms.Label]::new(); $label.Text='Ссылка или ID'; $label.Dock='Fill'; $label.TextAlign='MiddleLeft'
$query=[Windows.Forms.TextBox]::new(); $query.Dock='Fill'
$fields.Controls.Add($label,0,0); $fields.Controls.Add($query,1,0); $root.Controls.Add($fields,0,1)
function New-Button($Panel,[string]$Text,[int]$Width) {
    $b=[Windows.Forms.Button]::new(); $b.Text=$Text; $b.Size=[Drawing.Size]::new($Width,34); $b.FlatStyle='Flat'; $b.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(207,215,227)
    $Panel.Controls.Add($b); return $b
}
$manage=[Windows.Forms.FlowLayoutPanel]::new(); $manage.Dock='Fill'; $manage.Padding=[Windows.Forms.Padding]::new(0,5,0,0); $manage.WrapContents=$false
$add=New-Button $manage 'Добавить' 105; $edit=New-Button $manage 'Изменить' 105; $delete=New-Button $manage 'Удалить' 100
$all=New-Button $manage 'Выбрать все' 130; $none=New-Button $manage 'Снять выбор' 130
$root.Controls.Add($manage,0,2)
$list=[Windows.Forms.ListView]::new(); $list.Dock='Fill'; $list.View='Details'; $list.CheckBoxes=$true; $list.FullRowSelect=$true; $list.MultiSelect=$false; $list.HideSelection=$false
$null=$list.Columns.Add('Apple ID',300); $null=$list.Columns.Add('Результат',245); $null=$list.Columns.Add('Описание',230)
$list.Columns[2].DisplayIndex=1
$root.Controls.Add($list,0,3)
$actions=[Windows.Forms.FlowLayoutPanel]::new(); $actions.Dock='Fill'; $actions.Padding=[Windows.Forms.Padding]::new(0,6,0,0)
$start=New-Button $actions 'Скачать IPA' 170; $start.BackColor=[Drawing.Color]::FromArgb(41,94,220); $start.ForeColor=[Drawing.Color]::White
$stop=New-Button $actions 'Отмена' 110; $stop.Enabled=$false
$openFolder=New-Button $actions 'Открыть папку' 160
$openFolder.Add_Click({
    try {
        $null=[IO.Directory]::CreateDirectory($script:OutputRoot)
        $folderProcess=[Diagnostics.ProcessStartInfo]::new(); $folderProcess.FileName=$script:OutputRoot; $folderProcess.UseShellExecute=$true
        $null=[Diagnostics.Process]::Start($folderProcess)
    } catch { $null=[Windows.Forms.MessageBox]::Show($form,'Не удалось открыть папку: '+$script:OutputRoot,'Папка загрузок') }
})
$root.Controls.Add($actions,0,4)
$status=[Windows.Forms.Label]::new(); $status.Dock='Fill'; $status.Text='Выберите учётки'; $status.TextAlign='MiddleLeft'; $root.Controls.Add($status,0,5)
$log=[Windows.Forms.TextBox]::new(); $log.Multiline=$true; $log.ReadOnly=$true; $log.ScrollBars='Vertical'; $log.Dock='Fill'; $log.BorderStyle='None'
$log.BackColor=[Drawing.Color]::FromArgb(20,29,47); $log.ForeColor=[Drawing.Color]::FromArgb(222,232,247); $log.Font=[Drawing.Font]::new('Consolas',10)
$root.Controls.Add($log,0,6)
function Add-Log([string]$Text) {
    foreach ($secret in $script:Secrets) { if ($secret) { $Text=$Text.Replace($secret,'[скрыто]') } }
    if ($log.TextLength -gt 100000) { $log.Text=$log.Text.Substring($log.TextLength-60000) }
    $log.AppendText(('['+(Get-Date -Format 'HH:mm:ss')+'] '+$Text+"`r`n")); $log.SelectionStart=$log.TextLength; $log.ScrollToCaret()
}
function Add-AccountRow($Account) {
    $item=[Windows.Forms.ListViewItem]::new([string]$Account.Email); $item.Tag=$Account; $item.Checked=$true
    $null=$item.SubItems.Add(''); $null=$item.SubItems.Add((Get-AccountDescription $Account)); $null=$list.Items.Add($item)
}
foreach ($a in $script:Accounts) { Add-AccountRow $a }
function Show-AccountEditor($Existing) {
    $dialog=[Windows.Forms.Form]::new(); $dialog.Text=if($Existing){'Изменить учётку'}else{'Добавить учётку'}
    $dialog.ClientSize=[Drawing.Size]::new(520,236); $dialog.StartPosition='CenterParent'; $dialog.FormBorderStyle='FixedDialog'; $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false; $dialog.Font=$form.Font
    $layout=[Windows.Forms.TableLayoutPanel]::new(); $layout.Dock='Fill'; $layout.Padding=[Windows.Forms.Padding]::new(16); $layout.ColumnCount=2; $layout.RowCount=5
    $null=$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',125)); $null=$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100))
    foreach($h in @(36,36,36,32,50)){$null=$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',$h))}
    $dialog.Controls.Add($layout)
    $e=[Windows.Forms.TextBox]::new(); $e.Dock='Fill'; $p=[Windows.Forms.TextBox]::new(); $p.Dock='Fill'; $p.UseSystemPasswordChar=$true
    $el=[Windows.Forms.Label]::new(); $el.Text='Apple ID'; $el.Dock='Fill'; $pl=[Windows.Forms.Label]::new(); $pl.Text='Пароль'; $pl.Dock='Fill'
    $layout.Controls.Add($el,0,0); $layout.Controls.Add($e,1,0); $layout.Controls.Add($pl,0,1); $layout.Controls.Add($p,1,1)
    $description=[Windows.Forms.TextBox]::new(); $description.Dock='Fill'; $description.MaxLength=200
    $dl=[Windows.Forms.Label]::new(); $dl.Text='Описание'; $dl.Dock='Fill'
    $layout.Controls.Add($dl,0,2); $layout.Controls.Add($description,1,2)
    $hint=[Windows.Forms.Label]::new(); $hint.Dock='Fill'; $hint.Text=if($Existing){'Пустой пароль — оставить сохранённый.'}else{''}; $layout.Controls.Add($hint,1,3)
    if($Existing){$e.Text=$Existing.Email; $description.Text=Get-AccountDescription $Existing}
    $buttons=[Windows.Forms.FlowLayoutPanel]::new(); $buttons.Dock='Fill'; $buttons.FlowDirection='RightToLeft'; $layout.Controls.Add($buttons,0,4); $layout.SetColumnSpan($buttons,2)
    $save=New-Button $buttons 'Сохранить' 120; $cancel=New-Button $buttons 'Отмена' 100; $cancel.DialogResult='Cancel'; $dialog.AcceptButton=$save; $dialog.CancelButton=$cancel
    $save.Add_Click({
        try {
            $email=$e.Text.Trim().ToLowerInvariant()
            if($email -notmatch '^\S+@\S+\.\S+$'){throw 'Введите Apple ID в виде email.'}
            foreach($a in $script:Accounts){if($a.Email -eq $email -and (-not $Existing -or $a.Id -ne $Existing.Id)){throw 'Эта учётка уже добавлена.'}}
            if(-not $p.Text -and -not $Existing){throw 'Введите пароль.'}
            if($p.Text.StartsWith('-')){throw 'Компонент входа пока не поддерживает пароль, начинающийся с дефиса.'}
            $cipher=if($p.Text){Lock-Password $p.Text}else{$Existing.Password}
            $id=if($Existing){$Existing.Id}else{[guid]::NewGuid().ToString('N')}
            $dialog.Tag=[pscustomobject]@{Id=$id;Email=$email;Password=$cipher;Description=$description.Text.Trim()}
            $dialog.DialogResult='OK'; $dialog.Close()
        } catch {$null=[Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message,'Учётка')}
    })
    try {if($dialog.ShowDialog($form) -eq 'OK'){return $dialog.Tag}} finally {$p.Clear(); $dialog.Dispose()}
}
$add.Add_Click({
    $a=Show-AccountEditor $null
    if($a){try{Write-Accounts $script:AccountsPath (@($script:Accounts.ToArray())+@($a)); $script:Accounts.Add($a); Add-AccountRow $a}catch{$null=[Windows.Forms.MessageBox]::Show($form,'Не удалось сохранить учётку.','Ошибка')}}
})
$edit.Add_Click({
    if(-not $list.SelectedItems.Count){return}; $row=$list.SelectedItems[0]; $a=Show-AccountEditor $row.Tag
    if($a){try{$updated=@($script:Accounts | ForEach-Object {if($_.Id -eq $a.Id){$a}else{$_}}); Write-Accounts $script:AccountsPath $updated; $index=$script:Accounts.IndexOf($row.Tag); $script:Accounts[$index]=$a; $row.Tag=$a; $row.Text=$a.Email; $row.SubItems[1].Text=''; $row.SubItems[2].Text=Get-AccountDescription $a}catch{$null=[Windows.Forms.MessageBox]::Show($form,'Не удалось сохранить изменения.','Ошибка')}}
})
$delete.Add_Click({
    if(-not $list.SelectedItems.Count){return}; $row=$list.SelectedItems[0]
    try{$updated=@($script:Accounts | Where-Object Id -ne $row.Tag.Id); Write-Accounts $script:AccountsPath $updated; $null=$script:Accounts.Remove($row.Tag); $list.Items.Remove($row)}catch{$null=[Windows.Forms.MessageBox]::Show($form,'Не удалось удалить учётку.','Ошибка')}
})
$all.Add_Click({foreach($row in $list.Items){$row.Checked=$true}})
$none.Add_Click({foreach($row in $list.Items){$row.Checked=$false}})
function Set-Busy([bool]$Value){$manage.Enabled=-not $Value; $list.Enabled=-not $Value; $fields.Enabled=-not $Value; $start.Enabled=-not $Value; $stop.Enabled=$Value}
function Stop-Queue {$script:StopRequested=$true; $script:Bus.Cancel=$true; $stop.Enabled=$false; $status.Text='Остановка…'}
$stop.Add_Click({Stop-Queue})
function Show-Code([string]$Message) {
    $accountDescription=Get-AccountDescription $script:Current.Tag
    $dialog=[Windows.Forms.Form]::new(); $dialog.Text='Код подтверждения'; $dialog.ClientSize=[Drawing.Size]::new(590,170); $dialog.StartPosition='CenterParent'; $dialog.FormBorderStyle='FixedDialog'; $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false; $dialog.Font=$form.Font
    if($accountDescription){$dialog.Text+=' — '+$accountDescription}
    $caption=[Windows.Forms.Label]::new(); $caption.Text=$Message; $caption.SetBounds(16,16,550,55)
    $code=[Windows.Forms.TextBox]::new(); $code.SetBounds(16,78,550,30); $code.MaxLength=6
    $ok=[Windows.Forms.Button]::new(); $ok.Text='Продолжить'; $ok.SetBounds(306,120,130,32)
    $cancel=[Windows.Forms.Button]::new(); $cancel.Text='Остановить'; $cancel.SetBounds(442,120,124,32); $cancel.DialogResult='Cancel'
    $dialog.Controls.AddRange(@($caption,$code,$ok,$cancel)); $dialog.AcceptButton=$ok; $dialog.CancelButton=$cancel
    $ok.Add_Click({if($code.Text -cmatch '^[0-9]{6}$'){$dialog.Tag=$code.Text; $dialog.DialogResult='OK'; $dialog.Close()}else{$null=[Windows.Forms.MessageBox]::Show($dialog,'Введите 6 цифр.','Код')}})
    $dialog.Add_Shown({$code.Focus()})
    try {
        if($dialog.ShowDialog($form) -eq 'OK'){$script:Secrets=@([string]$dialog.Tag); $script:Bus.Answer=[string]$dialog.Tag; $script:Bus.AnswerReady=$true}
        else{Stop-Queue}
    } finally{$code.Clear(); $dialog.Tag=$null; $dialog.Dispose()}
}
function Start-Next {
    if($script:StopRequested -or $script:Next -ge $script:Queue.Count){
        foreach($row in $script:Queue){if($row.SubItems[1].Text -eq 'В очереди'){$row.SubItems[1].Text='Не выполнено'}}
        $script:Active=$false; Set-Busy $false
        $status.Text=('Готово: {0}; ошибок: {1}{2}' -f $script:Success,$script:Failed,$(if($script:StopRequested){'; остановлено'}else{''}))
        Add-Log $status.Text; if($script:Closing){$form.Close()}; return
    }
    $script:Current=$script:Queue[$script:Next]; $script:Next++; $script:Terminal=$false; $script:Secrets=@()
    $a=$script:Current.Tag
    $folderName=([regex]::Replace($a.Email,'[^a-zA-Z0-9@._-]','_'))
    if($folderName.Length -gt 70){$folderName=$folderName.Substring(0,70)}
    $destination=Join-Path (Join-Path $script:OutputRoot $script:AppId) ($folderName+'-'+$a.Id.Substring(0,8))
    $options=@{AppRoot=$script:AppRoot;DataRoot=(Join-Path $script:DataRoot 'sessions');Email=$a.Email;Description=(Get-AccountDescription $a);Password='';EncryptedPassword=$a.Password;AppId=$script:AppId;OutputFolder=$destination;FileName='';ToolPath=''}
    $script:Bus.Cancel=$false; $script:Bus.Answer=$null; $script:Bus.AnswerReady=$false
    $accountLabel=$a.Email; $accountDescription=Get-AccountDescription $a
    if($accountDescription){$accountLabel=$accountDescription+' — '+$a.Email}
    $script:Current.SubItems[1].Text='Вход…'; $status.Text=('{0} из {1}: {2}' -f $script:Next,$script:Queue.Count,$accountLabel); Add-Log $status.Text
    $runner=$null
    try{
        $runner=[PowerShell]::Create()
        $null=$runner.AddScript('param($Path,$Options,$Bus); . $Path; Invoke-Workflow $Options $Bus').AddArgument((Join-Path $script:AppRoot 'Engine.ps1')).AddArgument($options).AddArgument($script:Bus)
        $handle=$runner.BeginInvoke(); $script:Job=@{Runner=$runner;Handle=$handle}
    }catch{if($runner){$runner.Dispose()}; $script:Current.SubItems[1].Text='Ошибка запуска'; $script:Failed++; Add-Log 'Не удалось запустить обработку учётки.'}
}
$start.Add_Click({
    if($script:Active){return}
    try{$script:AppId=Resolve-AppId $query.Text}catch{$null=[Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,'Приложение');return}
    $script:Queue=@($list.Items | Where-Object Checked)
    if(-not $script:Queue.Count){$null=[Windows.Forms.MessageBox]::Show($form,'Отметьте учётки галочками.','Учётки');return}
    foreach($row in $script:Queue){$row.SubItems[1].Text='В очереди'}
    $script:Next=0; $script:Success=0; $script:Failed=0; $script:StopRequested=$false; $script:Active=$true
    Set-Busy $true; $log.Clear(); Start-Next
})
$timer=[Windows.Forms.Timer]::new(); $timer.Interval=150
$timer.Add_Tick({
    $timer.Stop()
    try {
        $eventItem=$null
        while($script:Bus.Events.TryDequeue([ref]$eventItem)){
            switch($eventItem.Kind){
                'status' {$script:Current.SubItems[1].Text=[string]$eventItem.Data}
                'log' {} # Keep the journal focused on each account's result.
                'code' {if(-not $script:StopRequested){Show-Code ([string]$eventItem.Data)}}
                'done' {$script:Terminal=$true; $script:Success++; $script:Current.SubItems[1].Text='IPA сохранён'; Add-Log ('Сохранён: '+$eventItem.Data.Path)}
                'error' {$script:Terminal=$true; $script:Failed++; $script:Current.SubItems[1].Text='Ошибка — см. журнал'; Add-Log ('Ошибка: '+$eventItem.Data)}
                'cancelled' {$script:Terminal=$true; $script:Current.SubItems[1].Text='Отменено'}
                default {Stop-Queue; Add-Log 'Неожиданный запрос. Очередь остановлена.'}
            }
        }
        if($script:Job -and $script:Job.Handle.IsCompleted){
            if(-not $script:Bus.Events.IsEmpty){return}
            try{$null=$script:Job.Runner.EndInvoke($script:Job.Handle)}catch{}
            if(-not $script:Terminal){$script:Failed++; $script:Current.SubItems[1].Text='Ошибка'; Add-Log 'Обработка учётки завершилась без результата.'}
            $script:Job.Runner.Dispose(); $script:Job=$null; $script:Bus.Answer=$null; $script:Secrets=@()
        }
        if($script:Active -and -not $script:Job){Start-Next}
    } finally {if(-not $form.IsDisposed){$timer.Start()}}
})
$form.Add_FormClosing({param($sender,$eventArgs); if($script:Active){$eventArgs.Cancel=$true; $script:Closing=$true; Stop-Queue}})
try {
    if($SmokeTestPath){
        $form.Opacity=0; $form.ShowInTaskbar=$false; $form.Show(); $form.PerformLayout(); [Windows.Forms.Application]::DoEvents()
        $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height)
        try{$form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height)); $bitmap.Save($SmokeTestPath,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    }else{$timer.Start(); $null=$form.ShowDialog()}
} finally {$timer.Stop(); $timer.Dispose(); $form.Dispose(); $script:StoreLock.Dispose()}
