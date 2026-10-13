# Data storage

## Accounts

Apple IDs, descriptions and passwords are saved in `%LOCALAPPDATA%\IPA-Desk-Multi\accounts.json`. Passwords are encrypted using Windows DPAPI for the current Windows user. Apple IDs and descriptions are stored as plain text.

Verification codes are not saved. Each operation uses a temporary profile that is removed when the operation finishes. Temporary files may remain after a crash. Saving an account does not guarantee that Apple will not request another verification code.

The language preference is stored separately in `language.txt` in the same application data folder.

App IDs, names and selection flags are stored in `download-list.json` in the same data folder. Purchase history is held in memory; only the entries added to the download list are saved.

## Network access

The EXE downloads a pinned ipatool-cpp release from GitHub on first use and checks its SHA-256 before execution. The component cache is stored separately under `%LOCALAPPDATA%\IPA-Desk-Multi\components` and reused across app updates. It contacts Apple servers for authentication, license acquisition and downloads. Purchase history is requested from Apple using the same temporary session. Invoice details are processed in memory; only app IDs and names selected by the user are saved in the download list. Apple IDs are not sent to GitHub. The interface does not collect telemetry.

## IPA files and logs

IPA filenames and contents may contain Apple ID information. Removing an account does not delete downloaded files. Logs and screenshots may contain email addresses, account descriptions and local paths; remove personal information before sharing them.

Passwords and verification codes are passed to ipatool-cpp as process arguments. Local software with sufficient privileges may read them. Do not publish account files, passwords, verification codes or session files.

## EXE version

Components are extracted to `%LOCALAPPDATA%\IPA-Desk-Multi\app`. IPA files are saved to **Downloads → TapOk IPA Downloader**. Account data is stored separately and retained when the EXE is updated.

[TapOk IPA Downloader guide](README.md)
