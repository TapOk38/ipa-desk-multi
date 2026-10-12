# Download component

Uses **ipatool-cpp 1.0.9** from [Sorvigolova/ipatool](https://github.com/Sorvigolova/ipatool/releases/tag/1.0.9), based on [ipatool](https://github.com/majd/ipatool).

The component is downloaded automatically on first use. The app verifies the archive and executable against pinned SHA-256 checksums, then reuses the installed copy.

## Manual setup when running from source

The EXE prepares the component automatically. For the source package with `Start.cmd`, use these steps if automatic downloading is unavailable:

1. Download the [official ZIP](https://github.com/Sorvigolova/ipatool/releases/download/1.0.9/windows_amd64_ipatool-cpp.zip).
2. Open PowerShell in the `downloader/` folder.
3. Run the command below with the path to the downloaded archive:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\Install-Tools.ps1 -ArchivePath 'C:\Downloads\windows_amd64_ipatool-cpp.zip'
```

Then run `Start.cmd` again.

## Version and checksums

- Archive entry: `ipatool-cpp-windows-amd64.exe`.
- Installed file: `tools/cpp-1.0.9/ipatool-cpp.exe`.
- ZIP SHA-256: `264BE72D4B70E8A5540647277690FB47FCF1D7D6178ACF84629E93C0E564A331`.
- EXE SHA-256: `394E8953D317F39645F03A1BFE039D0DC0FFC04291EB9D0F535BD1BBCA4F4581`.

## Licenses

The [ipatool MIT license](licenses/ipatool-MIT.txt) is included with attribution. The external component and its Apple libraries are distributed separately; see the [author's README](https://github.com/Sorvigolova/ipatool/blob/1.0.9/README.md) for details. The TapOk IPA Downloader license covers its own code.