# Компонент для скачивания

Используется **ipatool-cpp 1.0.9** из проекта [Sorvigolova/ipatool](https://github.com/Sorvigolova/ipatool/releases/tag/1.0.9), основанного на [ipatool](https://github.com/majd/ipatool).

Компонент загружается автоматически при первом скачивании IPA. Программа проверяет SHA-256
архива и исполняемого файла. Установленная копия используется при последующих запусках.

## Ручная установка

Если автоматическая загрузка недоступна:

1. Скачайте [официальный ZIP](https://github.com/Sorvigolova/ipatool/releases/download/1.0.9/windows_amd64_ipatool-cpp.zip).
2. Откройте PowerShell в папке IPA Desk Multi.
3. Выполните команду, указав путь к скачанному архиву:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\Install-Tools.ps1 -ArchivePath 'C:\Downloads\windows_amd64_ipatool-cpp.zip'
```

После подготовки снова запустите Start.cmd.

## Версия и контрольные суммы

- Файл в архиве: `ipatool-cpp-windows-amd64.exe`.
- Установленный файл: `tools/cpp-1.0.9/ipatool-cpp.exe`.
- SHA-256 ZIP: `264BE72D4B70E8A5540647277690FB47FCF1D7D6178ACF84629E93C0E564A331`.
- SHA-256 EXE: `394E8953D317F39645F03A1BFE039D0DC0FFC04291EB9D0F535BD1BBCA4F4581`.

## Лицензии

[Лицензия MIT проекта ipatool](licenses/ipatool-MIT.txt) сохранена с указанием авторства.
Внешний компонент и входящие в него библиотеки Apple распространяются отдельно;
сведения о составе — в [README автора](https://github.com/Sorvigolova/ipatool/blob/1.0.9/README.md).
Лицензия IPA Desk Multi относится к его собственному коду.
