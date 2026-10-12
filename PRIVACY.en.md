# Data storage

[Русский](PRIVACY.md) | **English**

## Accounts

Apple IDs, descriptions and passwords are saved in `%LOCALAPPDATA%\IPA-Desk-Multi\accounts.json`. Passwords are encrypted using Windows DPAPI for the current Windows user. Apple IDs and descriptions are stored as plain text.

Verification codes are not saved. Each operation uses a temporary profile that is removed when the operation finishes. Temporary files may remain after a crash. Saving an account does not guarantee that Apple will not request another verification code.

The language preference is stored separately in `language.txt` in the same application data folder.

## Network access

The ipatool-cpp component is downloaded from GitHub during initial setup. It contacts Apple servers for authentication, license acquisition and downloads. Apple IDs are not sent to GitHub. The interface does not collect telemetry.

## IPA files and logs

IPA filenames and contents may contain Apple ID information. Removing an account does not delete downloaded files. Logs and screenshots may contain email addresses, account descriptions and local paths; remove personal information before sharing them.

Passwords and verification codes are passed to ipatool-cpp as process arguments. Local software with sufficient privileges may read them. Do not publish account files, passwords, verification codes or session files.

## EXE version

Components are extracted to `%LOCALAPPDATA%\IPA-Desk-Multi\app`. IPA files are saved to **Downloads → IPA Desk Multi**. Account data is stored separately and retained when the EXE is updated.

[IPA Desk Multi guide](docs/DOWNLOAD.en.md)
