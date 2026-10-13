# Data storage

The selected IPA is sent to the connected iPhone over USB. Installation uses a temporary copy; the application attempts to remove it afterwards. The original IPA is preserved.

If credentials are saved through **iCloud credentials**, they are stored in `%LOCALAPPDATA%\IPA-Install\accounts.dat`, encrypted for the current Windows user. They are not passed to USB tools or entered on the iPhone automatically. Saved credentials are displayed after a successful installation.

The language preference is stored separately in `language.txt` in the same application data folder.

The native .NET executable contains its USB components and extracts them only to a unique `%TEMP%\TapOk-IPA-Installer-<random>` folder. Temporary IPA copies also use that folder. It removes its own temporary files on normal exit where possible; a crash or forced termination may leave files in TEMP. No PowerShell scripts are executed. No components are downloaded or copied into the Windows directory. Saved accounts and IPA files are not included in the EXE. The Apple Devices link opens the official Microsoft Store page only when clicked; driver installation is separate.

The interface does not collect telemetry. The log may contain IPA filenames and device details. Do not share passwords, `accounts.dat`, or screenshots showing credentials.

[TapOk IPA Installer — Windows guide](README.md)
