# Building from source

For installation instructions, see [README](../README.md).

Requires JDK 17, Android SDK Platform 35 and Build Tools 35.0.0. Set their paths in `JAVA_HOME` and `ANDROID_HOME`.

Run the following commands from the repository's `android/` directory:

```sh
cd android
```

## Gradle

Windows:

```powershell
.\gradlew.bat testDebugUnitTest assembleDebug
```

Linux/macOS:

```sh
chmod +x gradlew
./gradlew testDebugUnitTest assembleDebug
```

Gradle downloads the required tools on first use. The debug APK is written to `app/build/outputs/apk/debug/`.

## Windows build script

To compile the source and run tests:

```powershell
.\Build-Manual.ps1 -Sdk 'C:\Android\sdk' -Jdk 'C:\Java\jdk-17' -TestsOnly
```

To build an APK, set your keystore and key passwords in the `IPA_USB_STORE_PASSWORD` and `IPA_USB_KEY_PASSWORD` environment variables, then run:

```powershell
.\Build-Manual.ps1 -Sdk 'C:\Android\sdk' -Jdk 'C:\Java\jdk-17' -KeyStore 'C:\Keys\release.jks' -KeyAlias 'release'
```

Output: `manual-build/ipa-usb-0.7.0-beta.2.apk`. The script does not download JDK or Android SDK.

Updating an installed app requires the same signing key. An APK signed with a different key cannot be installed over the published version.

Dependencies are stored in `libs/` and `test-libs/`, with checksums in `DEPENDENCIES.sha256`. Licenses and source links are listed in [NOTICE](../licenses/NOTICE.txt).
