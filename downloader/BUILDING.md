# Building TapOk IPA Downloader

Requires 64-bit Windows, Windows PowerShell 5.1 and .NET Framework 4.5 or later.

Run these commands from the `downloader/` folder.

```powershell
.\Build-Exe.ps1 -Destination .\dist
.\tests\Test-Exe.ps1 -ExePath .\dist\TapOk-IPA-Downloader-0.4.0-beta.3.exe -WorkRoot $env:TEMP
.\tests\Test-Engine.ps1
.\tests\Test-Tools.ps1
.\tests\Test-Localization.ps1
```

The EXE contains the interface, application code and license notices. The ipatool-cpp component is downloaded on the first IPA download and verified against pinned checksums.

`Build-Release.ps1` creates the legacy package with `Start.cmd`. This format saves files in `Downloads` beside the scripts. The EXE saves them to the system **Downloads → IPA Desk Multi** folder.

[Building TapOk IPA Installer — Windows](../installer/BUILDING.md)
