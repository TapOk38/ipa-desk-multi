# IPA Install

[Русский](README.md) | **English**

Installs IPA files on an iPhone from Windows over USB.

**[Download EXE](https://github.com/TapOk38/ipa-desk-multi/releases/download/suite-v1.0.0-beta.1/IPA-Install.exe)** · 1.1.0-beta.1

## Requirements

Windows 10/11 x64, an Apple device driver, a USB data cable and an IPA file. The driver is installed with [Apple Devices](https://apps.microsoft.com/detail/9np83lwlpz9k).

## Usage

1. Run the EXE and select the interface language. Connect an unlocked iPhone and confirm trust if prompted.
2. Click **Refresh**, then **Browse…** and select an IPA.
3. Click **Install**. Keep the cable connected until **App installed** appears.

If the app requests an Apple ID when launched, use the account that downloaded the IPA.

To install on another iPhone, reconnect the cable and click **Refresh**. Connect one device at a time.

<details>
<summary>Saving account credentials</summary>

**iCloud credentials** saves an Apple ID and password to display after installation. Enter them on the iPhone manually. One shared account is saved; selecting another IPA does not change it automatically.

</details>

## Troubleshooting

- **iPhone not detected:** check the cable, trust confirmation and connection in Apple Devices.
- **Installation error:** check the log. The IPA must be compatible with iOS and have a valid signature. The tool does not re-sign files or remove their Apple ID association.

[All apps](../README.en.md) · [Report an issue](https://github.com/TapOk38/ipa-desk-multi/issues) · [Data storage](PRIVACY.en.md)
