# Data storage

[Русский](PRIVACY.md) | **English**

The selected IPA is sent to the connected iPhone over USB. Installation uses a temporary copy; the application attempts to remove it afterwards. The original IPA is preserved.

If credentials are saved through **iCloud credentials**, they are stored in `%LOCALAPPDATA%\IPA-Install\accounts.dat`, encrypted for the current Windows user. They are not passed to USB tools or entered on the iPhone automatically. Saved credentials are displayed after a successful installation.

The language preference is stored separately in `language.txt` in the same application data folder.

The EXE extracts its components to `%LOCALAPPDATA%\IPA-Install\app`. Saved accounts and IPA files are not included in the distributed executable.

The interface does not collect telemetry. The log may contain IPA filenames and device details. Do not share passwords, `accounts.dat`, or screenshots showing credentials.

[IPA Install guide](README.en.md)
