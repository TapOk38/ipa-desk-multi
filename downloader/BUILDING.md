# Building TapOk IPA Downloader

Requires 64-bit Windows, Windows PowerShell 5.1 and .NET Framework 4.5 or later.

Run these commands from the `downloader/` folder:

```powershell
. .\Install-Tools.ps1
Ensure-IpaTool -AppRoot $PWD
.\Build-Exe.ps1 -Destination .\dist
.\tests\Test-Native.ps1 -ExePath .\dist\TapOk-IPA-Downloader-0.6.1-test.1.exe -WorkRoot $env:TEMP
```

The builder verifies and embeds ipatool-cpp 1.1.6 with its license notices. Preparing the build input may require Internet access. The resulting EXE prepares its component offline in a separate TEMP directory and removes it on normal exit. Interrupted processes can leave temporary files. No adjacent component folder, PowerShell runtime or administrator privileges are required. Windows/.NET Framework supplies the system libraries.

The native application preserves compatibility with existing encrypted accounts, app lists and language preferences. IPA files are saved to **Downloads → TapOk IPA Downloader**.

`Test-Native.ps1` uses synthetic accounts and a fake native tool for Apple workflows. It checks data compatibility, authentication handling, purchase history, IPA validation, cancellation, command-line arguments, the embedded component and its cleanup, and the English/Russian interface. It launches an Internet-marked copy without removing the marker. These checks do not test real Apple access or establish an antivirus verdict.

`Build-Release.ps1` and the original PowerShell workflow tests remain available for the source edition.

[Building TapOk IPA Installer — Windows](../installer/BUILDING.md)