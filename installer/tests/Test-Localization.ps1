#requires -Version 5.1
param([string]$TestRoot = (Join-Path $PSScriptRoot ('language-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
$appRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$TestRoot = [IO.Path]::GetFullPath($TestRoot)
$null = [IO.Directory]::CreateDirectory($TestRoot)
. (Join-Path $appRoot 'Localization.ps1')
$script:checks = 0
function Assert($Condition, [string]$Description) {
    if (-not $Condition) { throw ('FAIL: ' + $Description) }
    $script:checks++; Write-Output ('PASS: ' + $Description)
}
Assert ((Get-InstallerDefaultLanguage 'ru-RU') -eq 'ru' -and (Get-InstallerDefaultLanguage 'ru-KZ') -eq 'ru') 'Russian OS variants default to Russian'
Assert ((Get-InstallerDefaultLanguage 'en-US') -eq 'en' -and (Get-InstallerDefaultLanguage 'de-DE') -eq 'en') 'Other OS languages default to English'
$path = Join-Path $TestRoot 'profile/language.txt'
Assert ((Get-InstallerSavedLanguage -Path $path -CultureName 'ru-RU') -eq 'ru' -and -not (Test-Path -LiteralPath $path)) 'Missing preference uses OS without creating a file'
Save-InstallerLanguage -Language 'en' -Path $path
Assert ((Get-InstallerSavedLanguage -Path $path -CultureName 'ru-RU') -eq 'en') 'Saved English preference overrides Russian OS'
Save-InstallerLanguage -Language 'ru' -Path $path
Assert ((Get-InstallerSavedLanguage -Path $path -CultureName 'en-US') -eq 'ru') 'Preference can be changed and persists'
[IO.File]::WriteAllText($path, 'invalid')
Assert ((Get-InstallerSavedLanguage -Path $path -CultureName 'en-US') -eq 'en') 'Corrupt preference falls back to OS language'
Set-InstallerLanguage 'en'
Assert ((Get-InstallerText 'Для приложения нужна iOS {0} или новее. На iPhone установлена iOS {1}.' @('18.1','17.0')) -ceq 'The app requires iOS 18.1 or later. The iPhone is running iOS 17.0.') 'Formatted English messages preserve both version values'
Assert ((Convert-InstallerText 'iPhone подключён') -ceq 'iPhone connected') 'Existing status updates when switching to English'
Set-InstallerLanguage 'ru'
Assert ((Convert-InstallerText 'iPhone connected') -ceq 'iPhone подключён') 'Existing status updates when switching back to Russian'
Assert ((Convert-InstallerText 'Example App 1.2') -ceq 'Example App 1.2') 'App names and other values are not translated'
$missing = @()
foreach ($file in @('IPA-Install.ps1','Engine.ps1','Credentials.ps1','AccountWindows.ps1')) {
    $tokens=$null; $parseErrors=$null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $appRoot $file), [ref]$tokens, [ref]$parseErrors)
    Assert ($parseErrors.Count -eq 0) ('PowerShell source parses: ' + $file)
    foreach ($node in $ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Get-InstallerText'}, $true)) {
        $key = $node.CommandElements[1].Value
        if (-not $script:InstallerEnglish.ContainsKey($key)) { $missing += $key }
    }
}
Assert ($missing.Count -eq 0) 'Every localized message reference has an English translation'
Assert (@($script:InstallerEnglish.Values | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -match '[А-Яа-яЁё]' }).Count -eq 0) 'English message catalogue is complete and contains no Russian fallback'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
. (Join-Path $appRoot 'Credentials.ps1')
. (Join-Path $appRoot 'AccountWindows.ps1')
$fixture = [pscustomobject]@{ AppleId='fixture@example.invalid'; Password='Test password' }
foreach ($language in @('ru','en')) {
    Set-InstallerLanguage $language
    $editor = New-InstallerAccountEditor $null 'icloud:default' (Get-InstallerText 'Учётные данные iCloud') $fixture @{StorePath=(Join-Path $TestRoot 'unused.dat')}
    $display = New-InstallerAccountDisplay $null 'icloud:default' (Get-InstallerText 'Учётные данные iCloud') $fixture
    try {
        $expectedSave = if ($language -eq 'ru') { 'Сохранить' } else { 'Save' }
        $expectedTitle = if ($language -eq 'ru') { 'Введите на iPhone' } else { 'Enter on your iPhone' }
        Assert ($editor.Tag.Save.Text -ceq $expectedSave -and $display.Text -ceq $expectedTitle) ($language + ' credential windows use the chosen language')
        Assert ($editor.Tag.AppleId.Text -ceq $fixture.AppleId -and $editor.Tag.Password.Text -ceq $fixture.Password -and $editor.Tag.Password.UseSystemPasswordChar) ($language + ' editor preserves account data and masks the password')
        Assert ($display.Tag.AppleId.Text -ceq $fixture.AppleId -and $display.Tag.Password.Text -ceq $fixture.Password) ($language + ' post-install window retains manual credential entry display')
    } finally { $editor.Dispose(); $display.Dispose() }
}
Assert (-not (Test-Path -LiteralPath (Join-Path $TestRoot 'unused.dat'))) 'UI checks do not save synthetic credentials'
Write-Output ("All $script:checks localization checks passed.")
