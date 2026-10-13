#requires -Version 5.1
# Included by IPA-Desk.ps1 after New-Button is defined.
$fields=[Windows.Forms.GroupBox]::new(); $fields.Text=Get-IpaText 'Приложения'; $fields.Dock='Fill'
$appLayout=[Windows.Forms.TableLayoutPanel]::new(); $appLayout.Dock='Fill'; $appLayout.RowCount=2; $appLayout.Padding=[Windows.Forms.Padding]::new(4)
$null=$appLayout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',46)); $null=$appLayout.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100)); $fields.Controls.Add($appLayout)
$appActions=[Windows.Forms.FlowLayoutPanel]::new(); $appActions.Dock='Fill'; $appActions.WrapContents=$false; $appLayout.Controls.Add($appActions,0,0)
$addApp=New-Button $appActions (Get-IpaText 'Добавить') 100
$editApp=New-Button $appActions (Get-IpaText 'Изменить') 100
$deleteApp=New-Button $appActions (Get-IpaText 'Удалить') 100
$ownedApps=New-Button $appActions (Get-IpaText 'История покупок') 165
$allApps=New-Button $appActions (Get-IpaText 'Выбрать все') 125
$noApps=New-Button $appActions (Get-IpaText 'Снять выбор') 125
$appsList=[Windows.Forms.ListView]::new(); $appsList.Dock='Fill'; $appsList.View='Details'; $appsList.CheckBoxes=$true; $appsList.FullRowSelect=$true; $appsList.MultiSelect=$false; $appsList.HideSelection=$false
$null=$appsList.Columns.Add((Get-IpaText 'Приложение'),520); $null=$appsList.Columns.Add('App Store ID',240)
$appLayout.Controls.Add($appsList,0,1); $root.Controls.Add($fields,0,1)
$script:UpdatingApps=$false; $script:AppsReady=$false; $script:AppListReadError=$null
$form.Add_Shown({$script:AppsReady=$true})
function Get-AppEntries {
    foreach($row in $appsList.Items){[pscustomobject]@{Id=$row.Tag.Id;Name=$row.Tag.Name;Selected=$row.Checked}}
}
function Set-AppEntries([object[]]$Entries, [switch]$Save) {
    $normalized=@(ConvertTo-DownloadEntries $Entries)
    if($Save){
        if($script:AppListReadError){throw $script:AppListReadError}
        Write-DownloadEntries $script:DownloadListPath $normalized
    }
    $script:UpdatingApps=$true; $appsList.BeginUpdate()
    try {
        $appsList.Items.Clear()
        foreach($entry in $normalized){
            $row=[Windows.Forms.ListViewItem]::new($(if($entry.Name){$entry.Name}else{$entry.Id})); $row.Tag=$entry; $row.Checked=$entry.Selected
            $null=$row.SubItems.Add($entry.Id); $null=$appsList.Items.Add($row)
        }
    }finally{$appsList.EndUpdate(); $script:UpdatingApps=$false}
}
function Save-AppEdit($Existing, [string]$InputId, [string]$Name) {
    $id=Resolve-AppId $InputId
    $entries=@(Get-AppEntries)
    if(@($entries | Where-Object {$_.Id -eq $id -and (-not $Existing -or $_.Id -ne $Existing.Id)}).Count){throw (Get-IpaText 'Это приложение уже добавлено.')}
    $new=[pscustomobject]@{Id=$id;Name=$Name.Trim();Selected=$(if($Existing){$Existing.Selected}else{$true})}
    if($Existing){$entries=@($entries | ForEach-Object {if($_.Id -eq $Existing.Id){$new}else{$_}})}else{$entries+=@($new)}
    Set-AppEntries $entries -Save
}
function Show-AppEditor($Existing) {
    $dialog=[Windows.Forms.Form]::new(); $dialog.Text=if($Existing){Get-IpaText 'Изменить приложение'}else{Get-IpaText 'Добавить приложение'}
    $dialog.ClientSize=[Drawing.Size]::new(570,164); $dialog.StartPosition='CenterParent'; $dialog.FormBorderStyle='FixedDialog'; $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false; $dialog.Font=$form.Font
    $layout=[Windows.Forms.TableLayoutPanel]::new(); $layout.Dock='Fill'; $layout.Padding=[Windows.Forms.Padding]::new(16); $layout.ColumnCount=2
    $null=$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',185)); $null=$layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100))
    foreach($height in @(38,38,50)){$null=$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',$height))}; $dialog.Controls.Add($layout)
    $idLabel=[Windows.Forms.Label]::new(); $idLabel.Text=Get-IpaText 'Ссылка или App Store ID'; $idLabel.Dock='Fill'
    $idInput=[Windows.Forms.TextBox]::new(); $idInput.Dock='Fill'; $idInput.AccessibleName=$idLabel.Text
    $nameLabel=[Windows.Forms.Label]::new(); $nameLabel.Text=Get-IpaText 'Название (необязательно)'; $nameLabel.Dock='Fill'
    $nameInput=[Windows.Forms.TextBox]::new(); $nameInput.Dock='Fill'; $nameInput.MaxLength=200; $nameInput.AccessibleName=$nameLabel.Text
    $layout.Controls.Add($idLabel,0,0); $layout.Controls.Add($idInput,1,0); $layout.Controls.Add($nameLabel,0,1); $layout.Controls.Add($nameInput,1,1)
    if($Existing){$idInput.Text=$Existing.Id; $nameInput.Text=$Existing.Name}
    $buttons=[Windows.Forms.FlowLayoutPanel]::new(); $buttons.Dock='Fill'; $buttons.FlowDirection='RightToLeft'; $layout.Controls.Add($buttons,0,2); $layout.SetColumnSpan($buttons,2)
    $save=New-Button $buttons (Get-IpaText 'Сохранить') 120; $cancel=New-Button $buttons (Get-IpaText 'Отмена') 100; $cancel.DialogResult='Cancel'; $dialog.AcceptButton=$save; $dialog.CancelButton=$cancel
    $save.Add_Click({
        try {Save-AppEdit $Existing $idInput.Text $nameInput.Text; $dialog.DialogResult='OK'; $dialog.Close()}
        catch{
            if($SmokeTestPath){$script:AppValidationError=$_.Exception.Message}
            else{$null=[Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message,(Get-IpaText 'Приложение'))}
        }
    })
    try {
        if($SmokeTestPath){
            $dialog.Opacity=0; $dialog.ShowInTaskbar=$false; $dialog.Show(); [Windows.Forms.Application]::DoEvents()
            $before=[IO.File]::ReadAllText($script:DownloadListPath); $script:AppValidationError=$null
            $idInput.Text='invalid app id'; $save.PerformClick()
            if(-not $script:AppValidationError -or $dialog.DialogResult -eq 'OK' -or [IO.File]::ReadAllText($script:DownloadListPath) -ne $before){throw 'Invalid ID was not safely rejected.'}
            $script:AppValidationError=$null
            $idInput.Text='https://apps.apple.com/app/test/id404'; $nameInput.Text=if($Existing){'Edited App'}else{'Manual App'}
            $save.PerformClick()
            if($dialog.DialogResult -ne 'OK'){throw 'App editor did not save.'}
        }else{$null=$dialog.ShowDialog($form)}
    }finally{$dialog.Dispose()}
}
try {Set-AppEntries @(Read-DownloadEntries $script:DownloadListPath)}
catch {if($SmokeTestPath){[IO.File]::WriteAllText(($SmokeTestPath+'.error.txt'),($_.ToString()+[Environment]::NewLine+$_.ScriptStackTrace));return};$script:AppListReadError=$_.Exception.Message; $null=[Windows.Forms.MessageBox]::Show($form,$script:AppListReadError,(Get-IpaText 'Список приложений'))}
$addApp.Add_Click({Show-AppEditor $null})
$editApp.Add_Click({if($appsList.SelectedItems.Count){Show-AppEditor $appsList.SelectedItems[0].Tag}})
$appsList.Add_DoubleClick({if(-not $script:Active -and $appsList.SelectedItems.Count){Show-AppEditor $appsList.SelectedItems[0].Tag}})
$deleteApp.Add_Click({
    if(-not $appsList.SelectedItems.Count){return}
    try {$id=$appsList.SelectedItems[0].Tag.Id; Set-AppEntries @(Get-AppEntries | Where-Object Id -ne $id) -Save}
    catch {if($SmokeTestPath){[IO.File]::WriteAllText(($SmokeTestPath+'.error.txt'),($_.ToString()+[Environment]::NewLine+$_.ScriptStackTrace));return};$null=[Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,(Get-IpaText 'Список приложений'))}
})
$appsList.Add_ItemChecked({param($sender,$e)
    # WinForms raises ItemChecked while materializing the native list on Show.
    # At that point other items may not be fully available for enumeration.
    if(-not $script:AppsReady -or $script:UpdatingApps -or $form.Disposing -or $form.IsDisposed -or $null -eq $e.Item.Tag){return}
    if($e.Item.Tag.Selected -eq $e.Item.Checked){return}
    try {
        if($script:AppListReadError){throw $script:AppListReadError}
        Write-DownloadEntries $script:DownloadListPath @(Get-AppEntries)
        $e.Item.Tag.Selected=$e.Item.Checked
    }catch {
        if($SmokeTestPath){[IO.File]::WriteAllText(($SmokeTestPath+'.error.txt'),($_.ToString()+[Environment]::NewLine+$_.ScriptStackTrace));return}
        $script:UpdatingApps=$true; $e.Item.Checked=$e.Item.Tag.Selected; $script:UpdatingApps=$false
        $null=[Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,(Get-IpaText 'Список приложений'))
    }
})
function Select-AllApps([bool]$Value) {
    try {Set-AppEntries @(Get-AppEntries | ForEach-Object {[pscustomobject]@{Id=$_.Id;Name=$_.Name;Selected=$Value}}) -Save}
    catch {if($SmokeTestPath){[IO.File]::WriteAllText(($SmokeTestPath+'.error.txt'),($_.ToString()+[Environment]::NewLine+$_.ScriptStackTrace));return};$null=[Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,(Get-IpaText 'Список приложений'))}
}
$allApps.Add_Click({Select-AllApps $true}); $noApps.Add_Click({Select-AllApps $false})
