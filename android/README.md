# IPA USB

Installs IPA files on an iPhone from Android over USB.

**[Download APK](https://github.com/TapOk38/ipa-desk-multi/releases/download/suite-v1.0.0-beta.1/ipa-usb-0.7.0-beta.1.apk)** · 0.7.0-beta.1

## Requirements

Android 8.0+ with OTG support, a USB data cable and an IPA file saved on Android. An OTG adapter or USB hub may be required.

## Usage

1. Install the APK and select the interface language. Save the IPA on Android.
2. Enable OTG if your device has this setting. Connect the phones with the cable and unlock the iPhone.
3. Tap **Connect**. Allow USB access on Android and confirm trust on the iPhone if prompted.
4. Tap **Select IPA**, select the file, then tap **Install**. Keep the cable connected until **App installed** appears.

If the app requests an Apple ID when launched, use the account that downloaded the IPA.

## Troubleshooting

- **iPhone not detected:** check OTG and the cable. If USB-C ↔ USB-C fails, connect an OTG adapter or hub to Android, then connect the iPhone to it. [Connection help](docs/TESTING.md).
- **Installation error:** the IPA must be compatible with iOS and have a valid signature. The tool does not re-sign files or remove their Apple ID association.

To report an error, tap **Save log** and remove personal information from the log.

[All apps](../README.md) · [Report an issue](https://github.com/TapOk38/ipa-desk-multi/issues) · [Data storage](PRIVACY.md)
