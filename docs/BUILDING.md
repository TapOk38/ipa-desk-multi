# Сборка IPA Desk Multi

Нужна 64-разрядная Windows с Windows PowerShell 5.1 и .NET Framework 4.5 или новее.

```powershell
.\Build-Exe.ps1 -Destination .\dist
.\tests\Test-Exe.ps1 -ExePath .\dist\IPA-Desk-Multi-0.3.1-beta.1.exe -WorkRoot $env:TEMP
.\tests\Test-Engine.ps1
.\tests\Test-Tools.ps1
```

EXE включает интерфейс, код программы и документы о лицензиях. Компонент ipatool-cpp получается при первом скачивании IPA, с проверкой закреплённых контрольных сумм.

Для старого формата с Start.cmd доступен `Build-Release.ps1`. В этом формате файлы сохраняются в папке Downloads рядом со скриптами. При запуске через EXE — в системной папке «Загрузки → IPA Desk Multi».

[Сборка IPA Install](../installer/BUILDING.md)
