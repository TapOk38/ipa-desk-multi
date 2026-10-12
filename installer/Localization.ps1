#requires -Version 5.1
# Russian source strings are stable message keys. Format placeholders keep values
# (paths, versions, device names) outside the translated text.
$script:InstallerEnglish = @{
    'Установка IPA' = 'Install IPA'
    'Запустите IPA-Install.exe.' = 'Run IPA-Install.exe.'
    'IPA-файл' = 'IPA file'
    'Выбрать…' = 'Browse…'
    'Обновить' = 'Refresh'
    'Установить' = 'Install'
    'Отмена' = 'Cancel'
    'Учётные данные iCloud' = 'iCloud credentials'
    'Подключите iPhone по USB' = 'Connect an iPhone via USB'
    'Файл: ' = 'File: '
    'Поиск iPhone…' = 'Searching for an iPhone…'
    'Подготовка установки…' = 'Preparing installation…'
    'Ошибка запуска' = 'Startup error'
    'Не удалось запустить операцию.' = 'Could not start the operation.'
    'Выберите IPA' = 'Select an IPA'
    'Приложение iPhone (*.ipa)|*.ipa' = 'iPhone app (*.ipa)|*.ipa'
    'Остановка…' = 'Stopping…'
    'Не удалось открыть учётные данные в Windows.' = 'Could not open the saved credentials in Windows.'
    'iPhone подключён' = 'iPhone connected'
    'Подключите iPhone по USB и нажмите «Обновить»' = 'Connect an iPhone via USB and click Refresh'
    'Оставьте подключённым один iPhone и нажмите «Обновить»' = 'Connect only one iPhone and click Refresh'
    'Приложение установлено' = 'App installed'
    'Установлено: ' = 'Installed: '
    'Ошибка — см. журнал' = 'Error — see the log'
    'Остановлено' = 'Stopped'
    'Ошибка' = 'Error'
    'Операция завершилась без результата. Проверьте файлы программы.' = 'The operation ended without a result. Check the program files.'
    'Не удалось завершить операцию. Проверьте файлы программы.' = 'Could not complete the operation. Check the program files.'
    'Не удалось сохранить язык. При следующем запуске выбор может сброситься.' = 'Could not save the language. Your selection may reset on the next launch.'
    'Учётные данные' = 'Credentials'
    'Пароль' = 'Password'
    'Показать пароль' = 'Show password'
    'Сохранить' = 'Save'
    'Введите Apple ID и пароль.' = 'Enter an Apple ID and password.'
    'Не удалось сохранить учётные данные в Windows.' = 'Could not save the credentials in Windows.'
    'Введите на iPhone' = 'Enter on your iPhone'
    'Закрыть' = 'Close'
    'Изменить' = 'Edit'
    'Не удалось прочитать сохранённые учётные данные.' = 'Could not read the saved credentials.'
    'Не удалось сохранить учётные данные.' = 'Could not save the credentials.'
    'Не удалось удалить учётные данные.' = 'Could not remove the credentials.'
    'Операция отменена.' = 'Operation cancelled.'
    'Не найдены компоненты установки. Закройте программу и запустите IPA-Install.exe повторно.' = 'Installation components are missing. Close the program and run IPA-Install.exe again.'
    'Не удалось запустить файлы установки. Закройте программу и запустите IPA-Install.exe повторно.' = 'Could not start the installation components. Close the program and run IPA-Install.exe again.'
    'Не удалось запустить файлы установки.' = 'Could not start the installation components.'
    'Время ожидания истекло. Проверьте установку на iPhone.' = 'The operation timed out. Check the installation on your iPhone.'
    'iPhone не отвечает. Разблокируйте его и проверьте USB-подключение.' = 'The iPhone is not responding. Unlock it and check the USB connection.'
    'Не удалось загрузить компоненты установки. Закройте программу и запустите IPA-Install.exe повторно.' = 'Could not load the installation components. Close the program and run IPA-Install.exe again.'
    'Не удалось обнаружить iPhone. Проверьте USB-кабель и наличие Apple Devices на компьютере.' = 'Could not find an iPhone. Check the USB cable and that Apple Devices is installed on this PC.'
    'Не удалось прочитать список iPhone. Проверьте USB-подключение.' = 'Could not read the iPhone list. Check the USB connection.'
    'iOS неизвестна' = 'iOS version unknown'
    'На iPhone отклонено доверие компьютеру. Подключите его заново и нажмите «Доверять».' = 'Trust was declined on the iPhone. Reconnect it and tap Trust.'
    'Разблокируйте iPhone и повторите установку.' = 'Unlock the iPhone and try installing again.'
    'Не удалось подключиться к iPhone. Проверьте USB-кабель и повторите установку.' = 'Could not connect to the iPhone. Check the USB cable and try installing again.'
    'Не удалось подтвердить доверие iPhone. Разблокируйте его и повторите установку.' = 'Could not confirm trust with the iPhone. Unlock it and try installing again.'
    'Разблокируйте iPhone и нажмите «Доверять».' = 'Unlock the iPhone and tap Trust.'
    'Доверие не подтверждено. Нажмите «Доверять» на iPhone и повторите установку.' = 'Trust was not confirmed. Tap Trust on the iPhone and try installing again.'
    'Не удалось создать временные файлы. Переместите программу в доступную для записи папку.' = 'Could not create temporary files. Check write access to the program folder.'
    'Не удалось подготовить IPA. Проверьте доступ к файлу и свободное место на диске.' = 'Could not prepare the IPA. Check file access and available disk space.'
    'Выберите существующий файл IPA.' = 'Select an existing IPA file.'
    'Выберите файл с расширением .ipa.' = 'Select a file with the .ipa extension.'
    'В файле IPA не найдено корректное приложение.' = 'No valid app was found in the IPA file.'
    'Не удалось прочитать сведения о приложении в IPA.' = 'Could not read the app information in the IPA.'
    'iPhone отклонил подпись или разрешение на установку этого IPA.' = 'The iPhone rejected the signature or installation permission for this IPA.'
    'Для этого IPA требуется другая версия iOS.' = 'This IPA requires a different iOS version.'
    'Это приложение несовместимо с выбранным iPhone.' = 'This app is not compatible with the selected iPhone.'
    'На iPhone недостаточно свободного места.' = 'There is not enough free space on the iPhone.'
    'Разблокируйте iPhone, нажмите «Доверять» и повторите установку.' = 'Unlock the iPhone, tap Trust and try installing again.'
    'Соединение с iPhone прервано. Проверьте USB-кабель и результат установки на телефоне.' = 'The iPhone connection was interrupted. Check the USB cable and installation result on the phone.'
    'iPhone отклонил установку: ' = 'The iPhone rejected installation: '
    'Установка не подтверждена. Проверьте сообщение на iPhone и совместимость IPA.' = 'Installation was not confirmed. Check the message on the iPhone and IPA compatibility.'
    'Не удалось удалить временную копию IPA: ' = 'Could not remove the temporary IPA copy: '
    'Неизвестное действие.' = 'Unknown operation.'
    'Подключите iPhone по USB и нажмите «Обновить».' = 'Connect an iPhone via USB and click Refresh.'
    'Проверка IPA…' = 'Checking IPA…'
    'iPhone отключён. Проверьте USB-кабель и нажмите «Обновить».' = 'The iPhone is disconnected. Check the USB cable and click Refresh.'
    'Для приложения нужна iOS {0} или новее. На iPhone установлена iOS {1}.' = 'The app requires iOS {0} or later. The iPhone is running iOS {1}.'
    'Установка…' = 'Installing…'
    'iPhone сообщил об установке, но приложение не найдено в списке. Проверьте результат на телефоне.' = 'The iPhone reported installation, but the app was not found in its app list. Check the result on the phone.'
    'Ожидание остановлено. Проверьте установку на iPhone.' = 'Stopped waiting. Check the installation on your iPhone.'
}

function Get-InstallerLanguagePath {
    return Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'IPA-Install/language.txt'
}
function Get-InstallerDefaultLanguage([string]$CultureName = [Globalization.CultureInfo]::CurrentUICulture.Name) {
    return 'en'
}
function Get-InstallerSavedLanguage([string]$Path = (Get-InstallerLanguagePath), [string]$CultureName = [Globalization.CultureInfo]::CurrentUICulture.Name) {
    try {
        if ([IO.File]::Exists($Path) -and [IO.FileInfo]::new($Path).Length -le 16) {
            $saved = [IO.File]::ReadAllText($Path).Trim()
            if ($saved -in @('ru','en')) { return $saved }
        }
    } catch { }
    return Get-InstallerDefaultLanguage $CultureName
}
function Set-InstallerLanguage([ValidateSet('ru','en')][string]$Language) { $script:InstallerLanguage = $Language }
function Save-InstallerLanguage([ValidateSet('ru','en')][string]$Language, [string]$Path = (Get-InstallerLanguagePath)) {
    $folder = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    $null = [IO.Directory]::CreateDirectory($folder)
    $temporary = Join-Path $folder ('.language-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, $Language, [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function Get-InstallerText([string]$Text, [object[]]$Values = @()) {
    $translated = $Text
    if ($script:InstallerLanguage -eq 'en' -and $script:InstallerEnglish.ContainsKey($Text)) { $translated = $script:InstallerEnglish[$Text] }
    if ($Values.Count) { return [string]::Format([Globalization.CultureInfo]::CurrentCulture, $translated, $Values) }
    return $translated
}
function Convert-InstallerText([string]$Text) {
    if ($script:InstallerEnglish.ContainsKey($Text)) { return Get-InstallerText $Text }
    foreach ($key in $script:InstallerEnglish.Keys) {
        if ($script:InstallerEnglish[$key] -ceq $Text) { return Get-InstallerText $key }
    }
    return $Text
}
if (-not (Get-Variable -Name InstallerLanguage -Scope Script -ErrorAction SilentlyContinue)) {
    Set-InstallerLanguage (Get-InstallerDefaultLanguage)
}
