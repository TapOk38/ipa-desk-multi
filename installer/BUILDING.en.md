# Building IPA Install

[Русский](BUILDING.md) | **English**

Requires 64-bit Windows, Windows PowerShell 5.1 and .NET Framework 4.5 or later.

Run from the repository root:

```powershell
.\installer\Prepare-Tools.ps1
.\installer\Build-Exe.ps1 -Destination .\dist-install
```

The first script downloads pinned MSYS2 packages and their corresponding sources, verifies SHA-256 checksums, and extracts only the required EXE/DLL files. Licenses and build recipes are stored in `installer/tools/`. The output is `dist-install/IPA-Install.exe`.

To check startup and bundled components:

```powershell
.\installer\Test-Exe.ps1 -ExePath .\dist-install\IPA-Install.exe -TestRoot .\.test-install-exe
.\installer\tests\Test-Engine.ps1 -AppRoot .\installer -TestRoot .\.test-install-engine
.\installer\tests\Test-Credentials.ps1 -ModulePath .\installer\Credentials.ps1 -TestRoot .\.test-install-credentials
```

Workflow tests simulate iPhone responses; they do not install apps on real devices.

The interface code is licensed under [MIT](../LICENSE). Third-party tools and libraries retain the licenses listed in [NOTICE](tools/THIRD-PARTY-NOTICES.txt).
