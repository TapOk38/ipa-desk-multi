# Download component

Uses **ipatool-cpp 1.1.6** from [Sorvigolova/ipatool](https://github.com/Sorvigolova/ipatool/releases/tag/1.1.6), based on [ipatool](https://github.com/majd/ipatool).

The EXE downloads the pinned component on first use and verifies its SHA-256 checksum before execution. The shared component cache survives interface updates. Source checkouts can prepare the same component through Install-Tools.ps1.

## Manual setup when running from source

The EXE prepares the component automatically. For the source package with `Start.cmd`, use these steps if automatic downloading is unavailable:

1. Download the [official ZIP](https://github.com/Sorvigolova/ipatool/releases/download/1.1.6/windows_amd64_ipatool-cpp.zip).
2. Open PowerShell in the `downloader/` folder.
3. Run the command below with the path to the downloaded archive:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\Install-Tools.ps1 -ArchivePath 'C:\Downloads\windows_amd64_ipatool-cpp.zip'
```

Then run `Start.cmd` again.

## Version and checksums

- Archive entry: `ipatool-cpp-windows-amd64.exe`.
- Installed file: `tools/cpp-1.1.6/ipatool-cpp.exe`.
- ZIP SHA-256: `18313C41400958F467CA177B7DFEC7C7A642CC3D1E18E73B2452F9D4E95BB841`.
- EXE SHA-256: `F053593059A5ADA859F2D28F8707BEB8D53F02B7830A9895C5913653A23A0CE2`.

## Licenses

The [ipatool MIT license](licenses/ipatool-MIT.txt) is included with attribution. The component is downloaded from the pinned release; see the [author's README](https://github.com/Sorvigolova/ipatool/blob/1.1.6/README.md) for details. The TapOk IPA Downloader license covers its own code.

Purchase history uses the same pinned ipatool-cpp component, querying invoices for each year from 2008 to the current year.
