# Building TapOk IPA Installer — Windows

Building requires 64-bit Windows, PowerShell 5.1 or later and the .NET Framework C# compiler. The compiled application runs on .NET Framework 4.5 or later and does not use PowerShell.

Run from the repository root:

```powershell
.\installer\Prepare-Tools.ps1
.\installer\Build-Exe.ps1 -Destination .\dist-install
```

The first script downloads pinned MSYS2 packages and their corresponding sources, verifies SHA-256 checksums, and extracts only the required EXE/DLL files. Licenses and build recipes are stored in `installer/tools/`.

The build compiles `native/*.cs` and the shared managed plist reader in `downloader/Metadata.cs`. It produces a single `dist-install/TapOk-IPA-Installer-Windows-1.2.0-test.2.exe`. USB tools, libraries, licenses and corresponding sources are embedded in a ZIP resource with a compiled SHA-256 digest. At runtime they are extracted to a unique `%TEMP%\TapOk-IPA-Installer-<random>` directory and verified before execution. The application removes its own extracted files on normal exit; interrupted sessions may leave temporary files. It does not download components, copy programs into the Windows directory, or run PowerShell.

Apple Devices and its USB driver must already be installed. The UI links to its official Microsoft Store page; the app does not install system drivers automatically. Windows itself must provide .NET Framework 4.5 or later. `Build-result.json` records the EXE and embedded archive hashes. Use a fresh output directory for each build.
To check startup and bundled components:

```powershell
.\installer\tests\Test-Native.ps1 -ExePath .\dist-install\TapOk-IPA-Installer-Windows-1.2.0-test.2.exe -WorkRoot .\.test-install-native
.\installer\Test-Exe.ps1 -ExePath .\dist-install\TapOk-IPA-Installer-Windows-1.2.0-test.2.exe -TestRoot .\.test-install-exe
.\installer\tests\Test-Engine.ps1 -AppRoot .\installer -TestRoot .\.test-install-engine
.\installer\tests\Test-Credentials.ps1 -ModulePath .\installer\Credentials.ps1 -TestRoot .\.test-install-credentials
```

Native workflow tests launch fixture tools and use synthetic credentials. They cover trust, cancellation, timeouts, IPA metadata, installation confirmation, dependency integrity, and compatibility with the previous DPAPI storage format. GUI tests use an isolated profile with no USB calls. These checks do not log into Apple accounts, install on real devices, or certify antivirus acceptance. The legacy PowerShell tests remain as regression references.

The interface code is licensed under [MIT](../LICENSE). Third-party tools and libraries retain the licenses listed in [NOTICE](tools/THIRD-PARTY-NOTICES.txt).
