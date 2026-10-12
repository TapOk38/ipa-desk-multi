# Contributing

| Application | Source | Build instructions |
| --- | --- | --- |
| IPA Desk Multi | `downloader/` | [Windows downloader](../downloader/BUILDING.md) |
| IPA Install | `installer/` | [Windows installer](../installer/BUILDING.md) |
| IPA USB | `android/` | [Android installer](../android/docs/BUILDING.md) |

Windows code is licensed under [MIT](../LICENSE); Android code is [GPL-3.0-only](../android/LICENSE). Third-party components retain their respective licenses.

Run the relevant tests before submitting changes. Use fictitious accounts and generated test IPA files. Do not include real apps, passwords, signing keys or personal logs.

Document the version, source and license of any new dependency. Keep TLS and checksum verification enabled. Describe the change and validation in the pull request.

Language catalogs are `downloader/Localization.ps1`, `installer/Localization.ps1` and `android/app/src/main/java/ru/ipadesk/usb/L10n.java`. Keep Russian and English messages and format placeholders consistent.
