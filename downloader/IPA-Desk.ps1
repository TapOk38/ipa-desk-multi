#requires -Version 5.1
param([string]$SmokeTestPath, [string]$TestDataRoot, [string]$OutputRoot, [ValidateSet('ru','en')][string]$Language)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Localization.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw (Get-IpaText 'Запустите Start.cmd.') }
. (Join-Path $PSScriptRoot 'DownloadList.ps1')
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
$script:DownloadListPath = Join-Path $script:DataRoot 'download-list.json'
$script:AccountsPath = Join-Path $script:DataRoot 'accounts.json'
Initialize-IpaLanguage $script:DataRoot $Language
$script:StoreLock = $null
try {
    $null = [IO.Directory]::CreateDirectory($script:DataRoot)
    $script:StoreLock = [IO.File]::Open((Join-Path $script:DataRoot 'accounts.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $script:Accounts = [Collections.Generic.List[object]]::new()
    foreach ($a in @(Read-Accounts $script:AccountsPath)) { if ($a) { $script:Accounts.Add($a) } }
} catch {
    if ($script:StoreLock) { $script:StoreLock.Dispose() }
    $null = [Windows.Forms.MessageBox]::Show(((Get-IpaText 'Не удалось открыть учётки. Закройте другое окно TapOk IPA Downloader, если оно открыто.') + "`n" + $_.Exception.Message), 'TapOk IPA Downloader')
    return
}
$script:Job = $null; $script:Active = $false; $script:Closing = $false; $script:StopRequested = $false
$script:Queue = @(); $script:Next = 0; $script:Success = 0; $script:Failed = 0
$script:Current = $null; $script:Terminal = $false; $script:Secrets = @()
$script:Bus = [hashtable]::Synchronized(@{ Events=[Collections.Concurrent.ConcurrentQueue[object]]::new(); Cancel=$false; Answer=$null; AnswerReady=$false })

$form = [Windows.Forms.Form]::new(); $form.Text = 'TapOk IPA Downloader'
$form.ClientSize = [Drawing.Size]::new(900, 760); $form.MinimumSize = [Drawing.Size]::new(860, 760)
$form.StartPosition = 'CenterScreen'; $form.AutoScaleMode = 'Dpi'
$form.Font = [Drawing.Font]::new('Segoe UI', 10); $form.BackColor = [Drawing.Color]::FromArgb(245,247,251)
$root = [Windows.Forms.TableLayoutPanel]::new(); $root.Dock = 'Fill'; $root.Padding = [Windows.Forms.Padding]::new(24)
$root.ColumnCount = 1; $root.RowCount = 7
foreach ($height in @(60,206,54,160,54,32)) { $null = $root.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',$height)) }
$null = $root.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100)); $form.Controls.Add($root)
$title = [Windows.Forms.Label]::new(); $title.Text = 'TapOk IPA Downloader'; $title.Dock = 'Fill'; $title.Font = [Drawing.Font]::new('Segoe UI',21,[Drawing.FontStyle]::Bold); $title.ForeColor = [Drawing.Color]::FromArgb(24,38,68)
$header=[Windows.Forms.TableLayoutPanel]::new(); $header.Dock='Fill'; $header.ColumnCount=2
$null=$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100)); $null=$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',120))
$languagePicker=[Windows.Forms.ComboBox]::new(); $languagePicker.DropDownStyle='DropDownList'; $languagePicker.Width=110; $languagePicker.Anchor='Right'; $languagePicker.AccessibleName='Language / Язык'
$null=$languagePicker.Items.AddRange(@('Русский','English')); $languagePicker.SelectedIndex=if((Get-IpaLanguage) -eq 'ru'){0}else{1}
$header.Controls.Add($title,0,0); $header.Controls.Add($languagePicker,1,0); $root.Controls.Add($header,0,0)
function New-Button($Panel,[string]$Text,[int]$Width) {
    $b=[Windows.Forms.Button]::new(); $b.Text=$Text; $b.Size=[Drawing.Size]::new($Width,34); $b.FlatStyle='Flat'; $b.FlatAppearance.BorderColor=[Drawing.Color]::FromArgb(207,215,227)
    $Panel.Controls.Add($b); return $b
}
. (Join-Path $PSScriptRoot 'AppListUI.ps1')
$manage=[Windows.Forms.FlowLayoutPanel]::new(); $manage.Dock='Fill'; $manage.Padding=[Windows.Forms.Padding]::new(0,5,0,0); $manage.WrapContents=$false
$add=New-Button $manage (Get-IpaText 'Добавить') 105; $edit=New-Button $manage (Get-IpaText 'Изменить') 105; $delete=New-Button $manage (Get-IpaText 'Удалить') 100
$all=New-Button $manage (Get-IpaText 'Выбрать все') 130; $none=New-Button $manage (Get-IpaText 'Снять выбор') 130
$root.Controls.Add($manage,0,2)
$list=[Windows.Forms.ListView]::new(); $list.Dock='Fill'; $list.View='Details'; $list.CheckBoxes=$true; $list.FullRowSelect=$true; $list.MultiSelect=$false; $list.HideSelection=$false
$null=$list.Columns.Add('Apple ID',300); $null=$list.Columns.Add((Get-IpaText 'Результат'),245); $null=$list.Columns.Add((Get-IpaText 'Описание'),230)
$list.Columns[2].DisplayIndex=1
$root.Controls.Add($list,0,3)
$actions=[Windows.Forms.FlowLayoutPanel]::new(); $actions.Dock='Fill'; $actions.Padding=[Windows.Forms.Padding]::new(0,6,0,0)
$start=New-Button $actions (Get-IpaText 'Скачать IPA') 170; $start.BackColor=[Drawing.Color]::FromArgb(41,94,220); $start.ForeColor=[Drawing.Color]::White
$stop=New-Button $actions (Get-IpaText 'Отмена') 110; $stop.Enabled=$false
$openFolder=New-Button $actions (Get-IpaText 'Открыть папку') 160
$openFolder.Add_Click({
    try {
        $null=[IO.Directory]::CreateDirectory($script:OutputRoot)
        $folderProcess=[Diagnostics.ProcessStartInfo]::new(); $folderProcess.FileName=$script:OutputRoot; $folderProcess.UseShellExecute=$true
        $null=[Diagnostics.Process]::Start($folderProcess)
    } catch { $null=[Windows.Forms.MessageBox]::Show($form,(Get-IpaText 'Не удалось открыть папку: ')+$script:OutputRoot,(Get-IpaText 'Папка загрузок')) }
})
$root.Controls.Add($actions,0,4)
$status=[Windows.Forms.Label]::new(); $status.Dock='Fill'; $status.Text=(Get-IpaText 'Выберите учётки'); $status.TextAlign='MiddleLeft'; $root.Controls.Add($status,0,5)
$log=[Windows.Forms.TextBox]::new(); $log.Multiline=$true; $log.ReadOnly=$true; $log.ScrollBars='Vertical'; $log.Dock='Fill'; $log.BorderStyle='None'
$log.BackColor=[Drawing.Color]::FromArgb(20,29,47); $log.ForeColor=[Drawing.Color]::FromArgb(222,232,247); $log.Font=[Drawing.Font]::new('Consolas',10)
$root.Controls.Add($log,0,6)
function Add-Log([string]$Text) {
    foreach ($secret in $script:Secrets) { if ($secret) { $Text=$Text.Replace($secret,(Get-IpaText '[скрыто]')) } }
    if ($log.TextLength -gt 100000) { $log.Text=$log.Text.Substring($log.TextLength-60000) }
    $log.AppendText(('['+(Get-Date -Format 'HH:mm:ss')+'] '+$Text+"`r`n")); $log.SelectionStart=$log.TextLength; $log.ScrollToCaret()
}
function Add-AccountRow($Account) {
    $item=[Windows.Forms.ListViewItem]::new([string]$Account.Email); $item.Tag=$Account; $item.Checked=$true
    $null=$item.SubItems.Add(''); $null=$item.SubItems.Add((Get-AccountDescription $Account)); $null=$list.Items.Add($item)
}
foreach ($a in $script:Accounts) { Add-AccountRow $a }
function Show-AccountEditor($Existing) {
    $dialog=[Windows.Forms.Form]::new(); $dialog.Text=if($Existing){(Get-IpaText 'Изменить учётку')}else{(Get-IpaText 'Добавить учётку')}
    $dialog.ClientSize=[Drawing.Size]::new(560,236); $dialog.StartPosition='CenterParent'; $dialog.FormBorderStyle='FixedDialog'; $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false; $dialog.Font=$form.Font
    $layout=[Windows.Forms.TableLayoutPanel]::new(); $layout.Dock='Fill'; $layout.Padding=[Windows.Forms.Padding]::new(16); $layout.ColumnCount=2; $layout.RowCount=5
    $null=$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',125)); $null=$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100))
    foreach($h in @(36,36,36,32,50)){$null=$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',$h))}
    $dialog.Controls.Add($layout)
    $e=[Windows.Forms.TextBox]::new(); $e.Dock='Fill'; $p=[Windows.Forms.TextBox]::new(); $p.Dock='Fill'; $p.UseSystemPasswordChar=$true
    $el=[Windows.Forms.Label]::new(); $el.Text='Apple ID'; $el.Dock='Fill'; $pl=[Windows.Forms.Label]::new(); $pl.Text=(Get-IpaText 'Пароль'); $pl.Dock='Fill'
    $layout.Controls.Add($el,0,0); $layout.Controls.Add($e,1,0); $layout.Controls.Add($pl,0,1); $layout.Controls.Add($p,1,1)
    $description=[Windows.Forms.TextBox]::new(); $description.Dock='Fill'; $description.MaxLength=200
    $dl=[Windows.Forms.Label]::new(); $dl.Text=(Get-IpaText 'Описание'); $dl.Dock='Fill'
    $layout.Controls.Add($dl,0,2); $layout.Controls.Add($description,1,2)
    $hint=[Windows.Forms.Label]::new(); $hint.Dock='Fill'; $hint.Text=if($Existing){(Get-IpaText 'Пустой пароль — оставить сохранённый.')}else{''}; $layout.Controls.Add($hint,1,3)
    if($Existing){$e.Text=$Existing.Email; $description.Text=Get-AccountDescription $Existing}
    $buttons=[Windows.Forms.FlowLayoutPanel]::new(); $buttons.Dock='Fill'; $buttons.FlowDirection='RightToLeft'; $layout.Controls.Add($buttons,0,4); $layout.SetColumnSpan($buttons,2)
    $save=New-Button $buttons (Get-IpaText 'Сохранить') 120; $cancel=New-Button $buttons (Get-IpaText 'Отмена') 100; $cancel.DialogResult='Cancel'; $dialog.AcceptButton=$save; $dialog.CancelButton=$cancel
    $save.Add_Click({
        try {
            $email=$e.Text.Trim().ToLowerInvariant()
            if($email -notmatch '^\S+@\S+\.\S+$'){throw (Get-IpaText 'Введите Apple ID в виде email.')}
            foreach($a in $script:Accounts){if($a.Email -eq $email -and (-not $Existing -or $a.Id -ne $Existing.Id)){throw (Get-IpaText 'Эта учётка уже добавлена.')}}
            if(-not $p.Text -and -not $Existing){throw (Get-IpaText 'Введите пароль.')}
            if($p.Text.StartsWith('-')){throw (Get-IpaText 'Компонент входа пока не поддерживает пароль, начинающийся с дефиса.')}
            $cipher=if($p.Text){Lock-Password $p.Text}else{$Existing.Password}
            $id=if($Existing){$Existing.Id}else{[guid]::NewGuid().ToString('N')}
            $dialog.Tag=[pscustomobject]@{Id=$id;Email=$email;Password=$cipher;Description=$description.Text.Trim()}
            $dialog.DialogResult='OK'; $dialog.Close()
        } catch {$null=[Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message,(Get-IpaText 'Учётка'))}
    })
    try {if($dialog.ShowDialog($form) -eq 'OK'){return $dialog.Tag}} finally {$p.Clear(); $dialog.Dispose()}
}
$add.Add_Click({
    $a=Show-AccountEditor $null
    if($a){try{Write-Accounts $script:AccountsPath (@($script:Accounts.ToArray())+@($a)); $script:Accounts.Add($a); Add-AccountRow $a}catch{$null=[Windows.Forms.MessageBox]::Show($form,(Get-IpaText 'Не удалось сохранить учётку.'),(Get-IpaText 'Ошибка'))}}
})
$edit.Add_Click({
    if(-not $list.SelectedItems.Count){return}; $row=$list.SelectedItems[0]; $a=Show-AccountEditor $row.Tag
    if($a){try{$updated=@($script:Accounts | ForEach-Object {if($_.Id -eq $a.Id){$a}else{$_}}); Write-Accounts $script:AccountsPath $updated; $index=$script:Accounts.IndexOf($row.Tag); $script:Accounts[$index]=$a; $row.Tag=$a; $row.Text=$a.Email; $row.SubItems[1].Text=''; $row.SubItems[2].Text=Get-AccountDescription $a}catch{$null=[Windows.Forms.MessageBox]::Show($form,(Get-IpaText 'Не удалось сохранить изменения.'),(Get-IpaText 'Ошибка'))}}
})
$delete.Add_Click({
    if(-not $list.SelectedItems.Count){return}; $row=$list.SelectedItems[0]
    try{$updated=@($script:Accounts | Where-Object Id -ne $row.Tag.Id); Write-Accounts $script:AccountsPath $updated; $null=$script:Accounts.Remove($row.Tag); $list.Items.Remove($row)}catch{$null=[Windows.Forms.MessageBox]::Show($form,(Get-IpaText 'Не удалось удалить учётку.'),(Get-IpaText 'Ошибка'))}
})
$all.Add_Click({foreach($row in $list.Items){$row.Checked=$true}})
$none.Add_Click({foreach($row in $list.Items){$row.Checked=$false}})
function Set-Busy([bool]$Value){$manage.Enabled=-not $Value; $list.Enabled=-not $Value; $fields.Enabled=-not $Value; $start.Enabled=-not $Value; $stop.Enabled=$Value; $languagePicker.Enabled=-not $Value}
function Update-MainLanguage {
    foreach($control in @($form,$title,$fields,$addApp,$editApp,$deleteApp,$allApps,$noApps,$ownedApps,$add,$edit,$delete,$all,$none,$start,$stop,$openFolder)) { $control.Text=Convert-IpaDisplayText $control.Text }
    foreach($column in @($list.Columns)+@($appsList.Columns)) { $column.Text=Convert-IpaDisplayText $column.Text }
    foreach($row in $list.Items) { $row.SubItems[1].Text=Convert-IpaDisplayText $row.SubItems[1].Text }
    $status.Text=Get-IpaText 'Выберите учётки'
}
$languagePicker.Add_SelectedIndexChanged({
    if($script:Active){return}
    $previous=Get-IpaLanguage
    $chosen=if($languagePicker.SelectedIndex -eq 0){'ru'}else{'en'}
    if($chosen -eq $previous){return}
    try { Save-IpaLanguage $script:DataRoot $chosen; Update-MainLanguage }
    catch { $languagePicker.SelectedIndex=if($previous -eq 'ru'){0}else{1}; $null=[Windows.Forms.MessageBox]::Show($form,(Get-IpaText 'Не удалось сохранить язык интерфейса.'),(Get-IpaText 'Ошибка')) }
})
function Stop-Queue {$script:StopRequested=$true; $script:Bus.Cancel=$true; $stop.Enabled=$false; $status.Text=(Get-IpaText 'Остановка…')}
$stop.Add_Click({Stop-Queue})
function Show-Code([string]$Message) {
    $accountDescription=Get-AccountDescription $script:Current.Tag
    $dialog=[Windows.Forms.Form]::new(); $dialog.Text=(Get-IpaText 'Код подтверждения'); $dialog.ClientSize=[Drawing.Size]::new(590,170); $dialog.StartPosition='CenterParent'; $dialog.FormBorderStyle='FixedDialog'; $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false; $dialog.Font=$form.Font
    if($accountDescription){$dialog.Text+=' — '+$accountDescription}
    $caption=[Windows.Forms.Label]::new(); $caption.Text=$Message; $caption.SetBounds(16,16,550,55)
    $code=[Windows.Forms.TextBox]::new(); $code.SetBounds(16,78,550,30); $code.MaxLength=6
    $ok=[Windows.Forms.Button]::new(); $ok.Text=(Get-IpaText 'Продолжить'); $ok.SetBounds(306,120,130,32)
    $cancel=[Windows.Forms.Button]::new(); $cancel.Text=(Get-IpaText 'Остановить'); $cancel.SetBounds(442,120,124,32); $cancel.DialogResult='Cancel'
    $dialog.Controls.AddRange(@($caption,$code,$ok,$cancel)); $dialog.AcceptButton=$ok; $dialog.CancelButton=$cancel
    $ok.Add_Click({if($code.Text -cmatch '^[0-9]{6}$'){$dialog.Tag=$code.Text; $dialog.DialogResult='OK'; $dialog.Close()}else{$null=[Windows.Forms.MessageBox]::Show($dialog,(Get-IpaText 'Введите 6 цифр.'),(Get-IpaText 'Код'))}})
    $dialog.Add_Shown({$code.Focus()})
    try {
        if($dialog.ShowDialog($form) -eq 'OK'){$script:Secrets=@([string]$dialog.Tag); $script:Bus.Answer=[string]$dialog.Tag; $script:Bus.AnswerReady=$true}
        else{Stop-Queue}
    } finally{$code.Clear(); $dialog.Tag=$null; $dialog.Dispose()}
}
function Show-Purchases([object[]]$Apps) {
    if (-not $Apps.Count) {$status.Text=Get-IpaText 'История покупок пуста'; Add-Log $status.Text; return}
    $dialog=[Windows.Forms.Form]::new(); $dialog.Text=(Get-IpaText 'Покупки учётки')+' — '+$script:Current.Tag.Email
    $dialog.ClientSize=[Drawing.Size]::new(720,480); $dialog.MinimumSize=[Drawing.Size]::new(620,400); $dialog.StartPosition='CenterParent'; $dialog.Font=$form.Font
    $layout=[Windows.Forms.TableLayoutPanel]::new(); $layout.Dock='Fill'; $layout.Padding=[Windows.Forms.Padding]::new(12); $layout.RowCount=3
    $null=$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',36)); $null=$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100)); $null=$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',46)); $dialog.Controls.Add($layout)
    $searchRow=[Windows.Forms.TableLayoutPanel]::new(); $searchRow.Dock='Fill'; $searchRow.ColumnCount=2
    $null=$searchRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',200)); $null=$searchRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100))
    $searchLabel=[Windows.Forms.Label]::new(); $searchLabel.Text=Get-IpaText 'Поиск по названию или ID'; $searchLabel.Dock='Fill'
    $filter=[Windows.Forms.TextBox]::new(); $filter.Dock='Fill'; $filter.AccessibleName=$searchLabel.Text; $searchRow.Controls.Add($searchLabel,0,0); $searchRow.Controls.Add($filter,1,0); $layout.Controls.Add($searchRow,0,0)
    $view=[Windows.Forms.ListView]::new(); $view.Dock='Fill'; $view.View='Details'; $view.CheckBoxes=$true; $view.FullRowSelect=$true
    $null=$view.Columns.Add((Get-IpaText 'Приложение'),460); $null=$view.Columns.Add('App Store ID',190); $layout.Controls.Add($view,0,1)
    $selection=@{}; $viewState=@{Suppress=$false}; $sorted=@($Apps | Sort-Object Name)
    $populate={
        $viewState.Suppress=$true; $view.BeginUpdate()
        try {
            $view.Items.Clear(); $needle=$filter.Text.Trim()
            foreach($app in $sorted){
                if($needle -and $app.Name.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -lt 0 -and $app.Id.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
                $row=[Windows.Forms.ListViewItem]::new([string]$app.Name); $row.Tag=[string]$app.Id; $null=$row.SubItems.Add([string]$app.Id); $row.Checked=$selection.ContainsKey($row.Tag); $null=$view.Items.Add($row)
            }
        }finally{$view.EndUpdate();$viewState.Suppress=$false}
    }
    $view.Add_ItemChecked({param($sender,$e);if(-not $viewState.Suppress){if($e.Item.Checked){$selection[$e.Item.Tag]=$true}else{$selection.Remove($e.Item.Tag)}}})
    $filter.Add_TextChanged($populate); & $populate
    $buttons=[Windows.Forms.FlowLayoutPanel]::new();$buttons.Dock='Fill';$buttons.FlowDirection='RightToLeft';$layout.Controls.Add($buttons,0,2)
    $ok=New-Button $buttons (Get-IpaText 'Добавить в список') 190; $cancel=New-Button $buttons (Get-IpaText 'Отмена') 110; $cancel.DialogResult='Cancel'; $dialog.CancelButton=$cancel
    $ok.Add_Click({
        try {
            if(-not $selection.Count){return}
            $combined=@(Get-AppEntries)
            foreach($app in $sorted | Where-Object {$selection.ContainsKey($_.Id)}){
                $existing=@($combined | Where-Object Id -eq $app.Id)
                if($existing.Count){$existing[0].Selected=$true; if(-not $existing[0].Name){$existing[0].Name=$app.Name}}
                else{$combined+=@([pscustomobject]@{Id=$app.Id;Name=$app.Name;Selected=$true})}
            }
            Set-AppEntries $combined -Save
            $dialog.DialogResult='OK';$dialog.Close()
        }catch{$null=[Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message,(Get-IpaText 'Список приложений'))}
    })
    try {
        if($SmokeTestPath){
            $dialog.Opacity=0; $dialog.ShowInTaskbar=$false; $dialog.Show(); [Windows.Forms.Application]::DoEvents()
            $filter.Text='Removed'; [Windows.Forms.Application]::DoEvents()
            if($view.Items.Count -ne 1 -or $view.Items[0].Tag -ne '303'){throw 'Purchase search did not find the delisted fixture.'}
            $view.Items[0].Checked=$true; $filter.Text='nothing matches'; $filter.Text=''
            if(-not $selection.ContainsKey('303')){throw 'Filtering lost the checked purchase.'}
            $bitmap=[Drawing.Bitmap]::new($dialog.Width,$dialog.Height)
            try{$dialog.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$dialog.Width,$dialog.Height));$bitmap.Save(($SmokeTestPath+'.purchases.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
            $ok.PerformClick()
            if(@(Get-AppEntries | ForEach-Object Id) -notcontains '303'){throw 'Selected purchase was not added to the saved list.'}
            $script:PurchasePickerVerified=$true
        }else{$null=$dialog.ShowDialog($form)}
    }finally{$dialog.Dispose()}
}
$ownedApps.Add_Click({
    if($script:Active){return}
    if(-not $list.SelectedItems.Count){$null=[Windows.Forms.MessageBox]::Show($form,(Get-IpaText 'Выделите одну учётку в таблице для просмотра её покупок.'),(Get-IpaText 'Покупки учётки'));return}
    $script:Current=$list.SelectedItems[0];$a=$script:Current.Tag
    $options=@{AppRoot=$script:AppRoot;DataRoot=(Join-Path $script:DataRoot 'sessions');Language=(Get-IpaLanguage);Email=$a.Email;Password='';EncryptedPassword=$a.Password;Mode='purchases'}
    $script:Bus.Cancel=$false;$script:Bus.Answer=$null;$script:Bus.AnswerReady=$false;$script:PendingPurchases=$null;$script:Secrets=@();$script:Terminal=$false;$script:StopRequested=$false
    $script:StageText='';$script:HistoryMode=$true;$script:Active=$true;Set-Busy $true
    $status.Text=(Get-IpaText 'Покупки учётки')+' — '+$a.Email; Add-Log $status.Text
    $runner=$null
    try {
        $runner=[PowerShell]::Create();$null=$runner.AddScript('param($Path,$Options,$Bus); . $Path; Invoke-Workflow $Options $Bus').AddArgument((Join-Path $script:AppRoot 'Engine.ps1')).AddArgument($options).AddArgument($script:Bus)
        $script:Job=@{Runner=$runner;Handle=$runner.BeginInvoke()}
    }catch{if($runner){$runner.Dispose()};$script:Active=$false;$script:HistoryMode=$false;Set-Busy $false;Add-Log (Get-IpaText 'Не удалось запустить обработку учётки.')}
})


function Start-Next {
    if($script:StopRequested -or $script:Next -ge $script:Queue.Count){
        foreach($row in $script:Queue){if($row.SubItems[1].Text -eq (Get-IpaText 'В очереди')){$row.SubItems[1].Text=(Get-IpaText 'Не выполнено')}}
        $script:Active=$false; Set-Busy $false
        $status.Text=((Get-IpaText 'Готово: {0}; ошибок: {1}{2}') -f $script:Success,$script:Failed,$(if($script:StopRequested){(Get-IpaText '; остановлено')}else{''}))
        Add-Log $status.Text; if($script:Closing){$form.Close()}; return
    }
    $script:Current=$script:Queue[$script:Next]; $script:Next++; $script:Terminal=$false; $script:Secrets=@(); $script:CurrentSuccess=0; $script:CurrentFailed=0
    $a=$script:Current.Tag
    $folderName=([regex]::Replace($a.Email,'[^a-zA-Z0-9@._-]','_'))
    if($folderName.Length -gt 70){$folderName=$folderName.Substring(0,70)}
    $downloads=@(foreach($id in $script:AppIds){[pscustomobject]@{AppId=$id;OutputFolder=(Join-Path (Join-Path $script:OutputRoot $id) ($folderName+'-'+$a.Id.Substring(0,8)))}})
    $options=@{AppRoot=$script:AppRoot;DataRoot=(Join-Path $script:DataRoot 'sessions');Language=(Get-IpaLanguage);Email=$a.Email;Description=(Get-AccountDescription $a);Password='';EncryptedPassword=$a.Password;Downloads=$downloads;FileName='';ToolPath=''}
    $script:Bus.Cancel=$false; $script:Bus.Answer=$null; $script:Bus.AnswerReady=$false
    $accountLabel=$a.Email; $accountDescription=Get-AccountDescription $a
    if($accountDescription){$accountLabel=$accountDescription+' — '+$a.Email}
    $script:Current.SubItems[1].Text=(Get-IpaText 'Вход…'); $status.Text=((Get-IpaText '{0} из {1}: {2}') -f $script:Next,$script:Queue.Count,$accountLabel); Add-Log $status.Text
    $runner=$null
    try{
        $runner=[PowerShell]::Create()
        $null=$runner.AddScript('param($Path,$Options,$Bus); . $Path; Invoke-Workflow $Options $Bus').AddArgument((Join-Path $script:AppRoot 'Engine.ps1')).AddArgument($options).AddArgument($script:Bus)
        $handle=$runner.BeginInvoke(); $script:Job=@{Runner=$runner;Handle=$handle}
    }catch{if($runner){$runner.Dispose()}; $script:Current.SubItems[1].Text=(Get-IpaText 'Ошибка запуска'); $script:Failed+=$script:AppIds.Count; Add-Log (Get-IpaText 'Не удалось запустить обработку учётки.')}
}
$start.Add_Click({
    if($script:Active){return}
    try{$script:AppIds=@(Get-AppEntries | Where-Object Selected | ForEach-Object Id); if(-not $script:AppIds.Count){throw (Get-IpaText 'Отметьте приложения галочками.')}; if($script:AppListReadError){throw $script:AppListReadError}}catch{$null=[Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,(Get-IpaText 'Приложение'));return}
    $script:Queue=@($list.Items | Where-Object Checked)
    if(-not $script:Queue.Count){$null=[Windows.Forms.MessageBox]::Show($form,(Get-IpaText 'Отметьте учётки галочками.'),(Get-IpaText 'Учётки'));return}
    foreach($row in $script:Queue){$row.SubItems[1].Text=(Get-IpaText 'В очереди')}
    $script:HistoryMode=$false; $script:Next=0; $script:Success=0; $script:Failed=0; $script:StopRequested=$false; $script:Active=$true
    Set-Busy $true; $log.Clear(); Start-Next
})
$timer=[Windows.Forms.Timer]::new(); $timer.Interval=150
$timer.Add_Tick({
    $timer.Stop()
    try {
        $eventItem=$null
        while($script:Bus.Events.TryDequeue([ref]$eventItem)){
            switch($eventItem.Kind){
                'status' {
                    $text=[string]$eventItem.Data; $script:Current.SubItems[1].Text=$text
                    $script:StageText=$text; $script:StageStarted=[DateTime]::UtcNow
                    $status.Text=$text; Add-Log $text
                }
                'log' {Add-Log ([string]$eventItem.Data)}
                'code' {if(-not $script:StopRequested){Show-Code ([string]$eventItem.Data)}}
                'app-start' {$script:CurrentAppId=[string]$eventItem.Data; Add-Log ($script:Current.Tag.Email+' — App ID '+$script:CurrentAppId)}
                'app-done' {$script:Success++; $script:CurrentSuccess++; Add-Log ((Get-IpaText 'Сохранён: ')+$eventItem.Data.Path)}
                'app-error' {$script:Failed++; $script:CurrentFailed++; Add-Log ('App ID '+$eventItem.Data.AppId+' — '+(Get-IpaText 'Ошибка: ')+$eventItem.Data.Message)}
                'batch-done' {$script:Terminal=$true; $script:Current.SubItems[1].Text=((Get-IpaText 'Скачано: {0}; ошибок: {1}') -f $script:CurrentSuccess,$script:CurrentFailed)}
                'purchases' {$script:Terminal=$true; $status.Text=Get-IpaText 'Список получен'; $script:PendingPurchases=@($eventItem.Data); $script:Current.SubItems[1].Text=(Get-IpaText 'Список получен')}
                'error' {$script:Terminal=$true; $status.Text=Get-IpaText 'Ошибка — см. журнал'; if(-not $script:HistoryMode){$script:Failed+=($script:AppIds.Count-$script:CurrentSuccess-$script:CurrentFailed)}; $script:Current.SubItems[1].Text=(Get-IpaText 'Ошибка — см. журнал'); Add-Log ((Get-IpaText 'Ошибка: ')+$eventItem.Data)}
                'cancelled' {$script:Terminal=$true; $status.Text=Get-IpaText 'Отменено'; $script:Current.SubItems[1].Text=(Get-IpaText 'Отменено')}
                default {Stop-Queue; Add-Log (Get-IpaText 'Неожиданный запрос. Очередь остановлена.')}
            }
        }
        if($script:Active -and $script:HistoryMode -and -not $script:Terminal -and -not $script:StopRequested -and $script:StageText){
            $elapsed=[int]([DateTime]::UtcNow-$script:StageStarted).TotalSeconds
            $status.Text=$script:StageText+'  '+((Get-IpaText '{0} с') -f $elapsed)
        }
        if($script:Job -and $script:Job.Handle.IsCompleted){
            if(-not $script:Bus.Events.IsEmpty){return}
            try{$null=$script:Job.Runner.EndInvoke($script:Job.Handle)}catch{}
            if(-not $script:Terminal){if(-not $script:HistoryMode){$script:Failed+=($script:AppIds.Count-$script:CurrentSuccess-$script:CurrentFailed)}; $script:Current.SubItems[1].Text=(Get-IpaText 'Ошибка'); Add-Log (Get-IpaText 'Обработка учётки завершилась без результата.')}
            $script:Job.Runner.Dispose(); $script:Job=$null; $script:Bus.Answer=$null; $script:Secrets=@()
        }
        if($script:Active -and -not $script:Job){
            if($script:HistoryMode){
                $script:Active=$false; $script:HistoryMode=$false; Set-Busy $false
                if(-not $script:Closing -and $null -ne $script:PendingPurchases){Show-Purchases $script:PendingPurchases; $script:PendingPurchases=$null}
                if($script:Closing){$form.Close()}
            }else{Start-Next}
        }
    } finally {if(-not $form.IsDisposed){$timer.Start()}}
})
$form.Add_FormClosing({param($sender,$eventArgs); if($script:Active){$eventArgs.Cancel=$true; $script:Closing=$true; Stop-Queue}})
try {
    if($SmokeTestPath){
        $form.Opacity=0; $form.ShowInTaskbar=$false; $form.Show(); $form.PerformLayout(); [Windows.Forms.Application]::DoEvents()
        # Exercise actual UI switching against isolated smoke-test preferences.
        $originalIndex=$languagePicker.SelectedIndex
        foreach($index in @((1-$originalIndex),$originalIndex)) {
            $languagePicker.SelectedIndex=$index
            if($start.Text -cne $(if($index -eq 0){'Скачать IPA'}else{'Download IPA'})) { throw 'Language switch did not update the download button.' }
            if($list.Columns[1].Text -cne $(if($index -eq 0){'Результат'}else{'Result'})) { throw 'Language switch did not update the result column.' }
        }
        Set-Busy $true
        if($languagePicker.Enabled){throw 'Language selector must be disabled while processing.'}
        if($appsList.Enabled -or $addApp.Enabled -or $ownedApps.Enabled){throw 'App list must be disabled while processing.'}
        Set-Busy $false
        $addApp.PerformClick()
        $manual=@($appsList.Items | Where-Object {$_.Tag.Id -eq '404'})[0]
        $manual.Selected=$true; $editApp.PerformClick()
        $manual=@($appsList.Items | Where-Object {$_.Tag.Id -eq '404'})[0]
        if($manual.Tag.Name -ne 'Edited App'){throw 'App editor did not update the name.'}
        $manual.Checked=$false
        if(@(Read-DownloadEntries $script:DownloadListPath | Where-Object Id -eq '404')[0].Selected){throw 'App selection was not saved.'}
        $manual.Selected=$true; $deleteApp.PerformClick()
        if(@(Get-AppEntries | Where-Object Id -eq '404').Count){throw 'App delete did not remove the row.'}
        $script:Current=$list.Items[0]
        Show-Purchases @([pscustomobject]@{Id='101';Name='Example App'},[pscustomobject]@{Id='303';Name='Removed App'})
        if([IO.File]::Exists($SmokeTestPath+'.error.txt')){throw [IO.File]::ReadAllText($SmokeTestPath+'.error.txt')}
        $state=@{Language=(Get-IpaLanguage);Title=$title.Text;Download=$start.Text;Add=$add.Text;OpenFolder=$openFolder.Text;Status=$status.Text;SwitchVerified=$true;LanguageDisabledWhileBusy=$true;AppEditorVerified=$true;PurchasePickerVerified=$script:PurchasePickerVerified;AppList=(Read-DownloadList $script:DownloadListPath)}
        [IO.File]::WriteAllText(($SmokeTestPath+'.json'),($state | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height)
        try{$form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height)); $bitmap.Save($SmokeTestPath,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    }else{$timer.Start(); $null=$form.ShowDialog()}
} finally {$script:UpdatingApps=$true; $timer.Stop(); $timer.Dispose(); $form.Dispose(); $script:StoreLock.Dispose()}
