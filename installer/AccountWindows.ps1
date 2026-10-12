#requires -Version 5.1

function New-InstallerAccountEditor($Owner, [string]$Key, [string]$AppName, $Account, [hashtable]$StoreOptions = @{}) {
    $window = [Windows.Forms.Form]::new()
    $window.Text = 'Учётные данные'; $window.ClientSize = [Drawing.Size]::new(600, 290)
    $window.MinimumSize = [Drawing.Size]::new(616, 329); $window.StartPosition = 'CenterParent'
    $window.Font = [Drawing.Font]::new('Segoe UI', 11); $window.BackColor = [Drawing.Color]::FromArgb(245, 247, 251)
    $window.AutoScaleMode = 'Dpi'; $window.MinimizeBox = $false; $window.MaximizeBox = $false
    $layout = [Windows.Forms.TableLayoutPanel]::new(); $layout.Dock = 'Fill'; $layout.Padding = [Windows.Forms.Padding]::new(20)
    $layout.ColumnCount = 2; $layout.RowCount = 6
    $null = $layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute', 95)); $null = $layout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100))
    foreach ($h in @(40, 38, 38, 32, 48, 44)) { $null = $layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', $h)) }
    $window.Controls.Add($layout)
    $appLabel = [Windows.Forms.Label]::new(); $appLabel.Text = $AppName; $appLabel.Dock = 'Fill'; $appLabel.AutoEllipsis = $true
    $appLabel.Font = [Drawing.Font]::new('Segoe UI', 13, [Drawing.FontStyle]::Bold)
    $layout.Controls.Add($appLabel, 0, 0); $layout.SetColumnSpan($appLabel, 2)
    $idLabel = [Windows.Forms.Label]::new(); $idLabel.Text = 'Apple ID'; $idLabel.Dock = 'Fill'; $idLabel.TextAlign = 'MiddleLeft'
    $idBox = [Windows.Forms.TextBox]::new(); $idBox.Dock = 'Fill'; $idBox.MaxLength = 320
    $passLabel = [Windows.Forms.Label]::new(); $passLabel.Text = 'Пароль'; $passLabel.Dock = 'Fill'; $passLabel.TextAlign = 'MiddleLeft'
    $passBox = [Windows.Forms.TextBox]::new(); $passBox.Dock = 'Fill'; $passBox.MaxLength = 1024; $passBox.UseSystemPasswordChar = $true
    if ($Account) { $idBox.Text = [string]$Account.AppleId; $passBox.Text = [string]$Account.Password }
    $layout.Controls.Add($idLabel, 0, 1); $layout.Controls.Add($idBox, 1, 1)
    $layout.Controls.Add($passLabel, 0, 2); $layout.Controls.Add($passBox, 1, 2)
    $showPass = [Windows.Forms.CheckBox]::new(); $showPass.Text = 'Показать пароль'; $showPass.AutoSize = $true
    $showPass.Add_CheckedChanged({ $passBox.UseSystemPasswordChar = -not $showPass.Checked }.GetNewClosure())
    $layout.Controls.Add($showPass, 1, 3)
    $errorLabel = [Windows.Forms.Label]::new(); $errorLabel.Dock = 'Fill'; $errorLabel.ForeColor = [Drawing.Color]::Firebrick
    $layout.Controls.Add($errorLabel, 0, 4); $layout.SetColumnSpan($errorLabel, 2)
    $buttons = [Windows.Forms.FlowLayoutPanel]::new(); $buttons.Dock = 'Fill'; $buttons.FlowDirection = 'RightToLeft'
    $saveButton = [Windows.Forms.Button]::new(); $saveButton.Text = 'Сохранить'; $saveButton.Size = [Drawing.Size]::new(125, 32)
    $cancelButton = [Windows.Forms.Button]::new(); $cancelButton.Text = 'Отмена'; $cancelButton.Size = [Drawing.Size]::new(100, 32); $cancelButton.DialogResult = 'Cancel'
    $buttons.Controls.Add($saveButton); $buttons.Controls.Add($cancelButton)
    $layout.Controls.Add($buttons, 0, 5); $layout.SetColumnSpan($buttons, 2)
    $window.AcceptButton = $saveButton; $window.CancelButton = $cancelButton
    $window.Tag = [pscustomobject]@{ AppleId = $idBox; Password = $passBox; Save = $saveButton; ErrorLabel = $errorLabel }
    $saveButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($idBox.Text) -or [string]::IsNullOrEmpty($passBox.Text)) { $errorLabel.Text = 'Введите Apple ID и пароль.'; return }
        try {
            Set-InstallerCredential -Key $Key -AppleId $idBox.Text.Trim() -Password $passBox.Text @StoreOptions
            $window.DialogResult = 'OK'; $window.Close()
        } catch { $errorLabel.Text = 'Не удалось сохранить учётные данные в Windows.' }
    }.GetNewClosure())
    return $window
}

function Edit-InstallerAccount($Owner, [string]$Key, [string]$AppName, [hashtable]$StoreOptions = @{}) {
    $account = Get-InstallerCredential -Key $Key @StoreOptions
    $window = New-InstallerAccountEditor $Owner $Key $AppName $account $StoreOptions
    try { return ($window.ShowDialog($Owner) -eq 'OK') }
    finally { $window.Tag.Password.Text = ''; $window.Dispose() }
}

function New-InstallerAccountDisplay($Owner, [string]$Key, [string]$AppName, $Account, [hashtable]$StoreOptions = @{}) {
    $window = [Windows.Forms.Form]::new()
    $window.Text = 'Введите на iPhone'; $window.ClientSize = [Drawing.Size]::new(860, 460)
    $window.MinimumSize = [Drawing.Size]::new(736, 430); $window.StartPosition = 'CenterParent'
    $window.Font = [Drawing.Font]::new('Segoe UI', 11); $window.BackColor = [Drawing.Color]::FromArgb(245, 247, 251)
    $window.AutoScaleMode = 'Dpi'; $window.MinimizeBox = $false
    $layout = [Windows.Forms.TableLayoutPanel]::new(); $layout.Dock = 'Fill'; $layout.Padding = [Windows.Forms.Padding]::new(24)
    $layout.ColumnCount = 1; $layout.RowCount = 6
    foreach ($h in @(48, 28)) { $null = $layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', $h)) }
    $null = $layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent', 50))
    $null = $layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 28))
    $null = $layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent', 50))
    $null = $layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 48))
    $window.Controls.Add($layout)
    $heading = [Windows.Forms.Label]::new(); $heading.Text = $AppName; $heading.Dock = 'Fill'; $heading.AutoEllipsis = $true
    $heading.Font = [Drawing.Font]::new('Segoe UI', 19, [Drawing.FontStyle]::Bold)
    $layout.Controls.Add($heading, 0, 0)
    $idLabel = [Windows.Forms.Label]::new(); $idLabel.Text = 'Apple ID'; $idLabel.Dock = 'Fill'
    $passLabel = [Windows.Forms.Label]::new(); $passLabel.Text = 'Пароль'; $passLabel.Dock = 'Fill'
    $idText = [Windows.Forms.TextBox]::new(); $passwordText = [Windows.Forms.TextBox]::new()
    foreach ($field in @($idText, $passwordText)) {
        $field.ReadOnly = $true; $field.Multiline = $true; $field.WordWrap = $true; $field.ScrollBars = 'Vertical'
        $field.Dock = 'Fill'; $field.BackColor = [Drawing.Color]::White; $field.BorderStyle = 'FixedSingle'
        $field.Font = [Drawing.Font]::new('Consolas', 25)
    }
    $idText.Text = [string]$Account.AppleId; $passwordText.Text = [string]$Account.Password
    $layout.Controls.Add($idLabel, 0, 1); $layout.Controls.Add($idText, 0, 2)
    $layout.Controls.Add($passLabel, 0, 3); $layout.Controls.Add($passwordText, 0, 4)
    $buttons = [Windows.Forms.FlowLayoutPanel]::new(); $buttons.Dock = 'Fill'; $buttons.FlowDirection = 'RightToLeft'; $buttons.Padding = [Windows.Forms.Padding]::new(0, 8, 0, 0)
    $closeButton = [Windows.Forms.Button]::new(); $closeButton.Text = 'Закрыть'; $closeButton.Size = [Drawing.Size]::new(120, 32); $closeButton.DialogResult = 'OK'
    $editButton = [Windows.Forms.Button]::new(); $editButton.Text = 'Изменить'; $editButton.Size = [Drawing.Size]::new(120, 32)
    $buttons.Controls.Add($closeButton); $buttons.Controls.Add($editButton); $layout.Controls.Add($buttons, 0, 5)
    $window.CancelButton = $closeButton
    $window.ActiveControl = $closeButton
    $window.Tag = [pscustomobject]@{ AppleId = $idText; Password = $passwordText; Edit = $editButton; Close = $closeButton }
    $editButton.Add_Click({
        try {
            if (Edit-InstallerAccount $window $Key $AppName $StoreOptions) {
                $updated = Get-InstallerCredential -Key $Key @StoreOptions
                $idText.Text = [string]$updated.AppleId; $passwordText.Text = [string]$updated.Password
            }
        } catch { $null = [Windows.Forms.MessageBox]::Show($window, 'Не удалось открыть учётные данные в Windows.', 'Учётные данные', 'OK', 'Error') }
    }.GetNewClosure())
    return $window
}

function Show-InstallerAccount($Owner, [string]$Key, [string]$AppName, [hashtable]$StoreOptions = @{}) {
    $account = Get-InstallerCredential -Key $Key @StoreOptions
    if (-not $account) { return }
    $window = New-InstallerAccountDisplay $Owner $Key $AppName $account $StoreOptions
    try { $null = $window.ShowDialog($Owner) }
    finally { $window.Tag.Password.Text = ''; $window.Tag.AppleId.Text = ''; $window.Dispose() }
}
