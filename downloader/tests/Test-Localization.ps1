#requires -Version 5.1
param([string]$WorkRoot=[IO.Path]::GetTempPath())
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'Localization.ps1')
$script:checks=0
function Assert($Condition,[string]$Message){if(-not $Condition){throw "FAIL: $Message"};$script:checks++;Write-Output "PASS: $Message"}
$work=Join-Path $WorkRoot ('language-test-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($work)
$accounts=Join-Path $work 'accounts.json'
[IO.File]::WriteAllText($accounts,'account-store-fixture-must-not-change')
$before=(Get-FileHash -LiteralPath $accounts -Algorithm SHA256).Hash
Save-IpaLanguage $work 'en'
Set-IpaLanguage 'ru'
Initialize-IpaLanguage $work
Assert ((Get-IpaLanguage) -eq 'en' -and (Get-IpaText 'Скачать IPA') -ceq 'Download IPA') 'Saved English language loads independently of Windows locale'
Save-IpaLanguage $work 'ru'
Initialize-IpaLanguage $work
Assert ((Get-IpaText 'Скачать IPA') -ceq 'Скачать IPA') 'Switching back preserves Russian text'
Assert ((Get-FileHash -LiteralPath $accounts -Algorithm SHA256).Hash -eq $before) 'Saving language never changes account data'
[IO.File]::WriteAllText((Join-Path $work 'language.txt'),'invalid')
Initialize-IpaLanguage $work
$default=if([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ru'){'ru'}else{'en'}
Assert ((Get-IpaLanguage) -eq $default) 'Invalid preference falls back to OS language'
Initialize-IpaLanguage $work 'ru'
Assert ((Get-IpaLanguage) -eq 'ru') 'Explicit test language takes priority'
Set-IpaLanguage 'en'
$missing=@();$formatMismatch=@();$unwrapped=@()
foreach($key in $script:IpaEnglish.Keys){
    $left=@([regex]::Matches($key,'\{\d+\}') | ForEach-Object Value) -join ','
    $right=@([regex]::Matches($script:IpaEnglish[$key],'\{\d+\}') | ForEach-Object Value) -join ','
    if($left -cne $right){$formatMismatch+=$key}
    if(-not $script:IpaEnglish[$key] -or $script:IpaEnglish[$key] -match '[А-Яа-яЁё]'){$missing+=$key}
}
foreach($file in @('IPA-Desk.ps1','Engine.ps1','Accounts.ps1','Metadata.ps1','Install-Tools.ps1')){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file),[ref]$tokens,[ref]$errors)
    Assert (-not $errors) "PowerShell parses: $file"
    foreach($node in $ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Get-IpaText'},$true)){
        if($node.CommandElements.Count -gt 1 -and $node.CommandElements[1] -is [Management.Automation.Language.StringConstantExpressionAst]){
            $key=$node.CommandElements[1].Value
            if(-not $script:IpaEnglish.ContainsKey($key)){$missing+=$key}
        }
    }
}
Assert ($missing.Count -eq 0) ('All UI keys have nonempty English translations: '+($missing -join ', '))
Assert ($formatMismatch.Count -eq 0) 'Formatting placeholders match between languages'
Assert (((Get-IpaText 'Готово: {0}; ошибок: {1}{2}') -f 3,1,'') -ceq 'Completed: 3; errors: 1') 'Formatted English summary renders correctly'
Assert ((Convert-IpaDisplayText 'Сохранить') -ceq 'Save') 'Controls translate from Russian to English'
Set-IpaLanguage 'ru'
Assert ((Convert-IpaDisplayText 'Download IPA') -ceq 'Скачать IPA') 'Controls translate back from English to Russian'
Write-Output ("Localization checks passed: "+$script:checks)
