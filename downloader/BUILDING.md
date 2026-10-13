# Building TapOk IPA Downloader

Requires 64-bit Windows, Windows PowerShell 5.1 and .NET Framework 4.5 or later.

Run these commands from the `downloader/` folder.

```powershell
.\Build-Exe.ps1 -Destination .\dist
.\tests\Test-Native.ps1 -ExePath .\dist\TapOk-IPA-Downloader-0.6.0-test.1.exe -WorkRoot $env:TEMP
.\tests\Test-Engine.ps1
.\tests\Test-Tools.ps1
.\tests\Test-Localization.ps1
```

The 0.6.0 test EXE compiles `native/Model.cs`, `native/Engine.cs`, `native/App.cs` and the existing `Metadata.cs` into a .NET Framework application. It has no embedded scripts, self-extracting archive, PowerShell host or PowerShell subprocess. The compiler and runtime libraries come from Windows/.NET Framework; no new package dependency is required. It runs as the current user without administrator privileges.

On first use it downloads the pinned ipatool-cpp component into the existing shared local cache and verifies its SHA-256 before execution. Existing DPAPI-encrypted accounts, app lists and language preferences remain compatible with the PowerShell edition. The source ZIP build includes the pinned component.

`Test-Native.ps1` uses only synthetic accounts and a fake native tool. It checks legacy data compatibility, account isolation, 2FA, purchase history, IPA validation, cancellation, command-line quoting, and the actual English/Russian UI. It also launches an Internet-marked copy without removing the marker. These checks do not establish an antivirus verdict or test real Apple access. Versions 0.5.0-beta.1 and 0.5.1-test.1 were withdrawn after Defender detections; the new native build is for local testing until download-time behavior is verified.

`Build-Release.ps1` and the original PowerShell workflow tests are retained for the legacy source edition. The native EXE saves files to **Downloads → TapOk IPA Downloader**.

[Building TapOk IPA Installer — Windows](../installer/BUILDING.md)
