# Сборка IPA Install

Нужна 64-разрядная Windows с Windows PowerShell 5.1 и .NET Framework 4.5 или новее.

Из корня репозитория:

```powershell
.\installer\Prepare-Tools.ps1
.\installer\Build-Exe.ps1 -Destination .\dist-install
```

Первый скрипт скачивает закреплённые пакеты MSYS2 и соответствующие исходники, проверяет SHA-256 и извлекает только нужные EXE/DLL. Лицензии и рецепты сборки хранятся в `tools/`. Готовый файл — `dist-install/IPA-Install.exe`.

Проверка запуска и встроенных компонентов:

```powershell
.\installer\Test-Exe.ps1 -ExePath .\dist-install\IPA-Install.exe -TestRoot .\.test-install-exe
.\installer\tests\Test-Engine.ps1 -AppRoot .\installer -TestRoot .\.test-install-engine
.\installer\tests\Test-Credentials.ps1 -ModulePath .\installer\Credentials.ps1 -TestRoot .\.test-install-credentials
```

Тесты сценариев используют имитацию ответов iPhone; они не устанавливают приложения на реальные устройства.

Собственный код оболочки распространяется по [MIT](../LICENSE). Сторонние утилиты и библиотеки — по лицензиям в [NOTICE](tools/THIRD-PARTY-NOTICES.txt).
