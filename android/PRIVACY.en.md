# Data storage

[Русский](PRIVACY.md) | **English**

The app does not collect telemetry and does not request the INTERNET permission. It sends the selected IPA and pairing/installation requests to the iPhone over USB.

A working copy of the IPA is kept in private cache. After a crash, it may remain until the next launch or until app data is cleared. The temporary file on the iPhone is removed after the installation result is confirmed; an interrupted operation may leave it until installation or cleanup completes.

The pairing record is stored locally using AES-GCM with a key held in Android Keystore. Reconnection can reuse the record while the iPhone still trusts it. Clearing app data removes the local record. The app does not read Apple IDs, passwords or verification codes.

The language choice is saved in local app preferences.

Logs are exported manually. They may contain IPA filenames, including an email address if present in the name, device models, OS versions and errors. Remove personal information before sharing. Request contents, private keys and full device identifiers are not logged.

[IPA USB guide](README.en.md)
