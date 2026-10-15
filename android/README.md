# TapOk IPA Installer — Android

<details>
<summary>English</summary>

Installs IPA files on an iPhone from Android over USB.

**[Download APK](https://github.com/TapOk38/tapok-ipa-tools/releases/download/suite-v1.0.0-beta.5/TapOk-IPA-Installer-Android-0.7.0-beta.4.apk)** · 0.7.0-beta.4

## Requirements

Android 8.0+ with OTG support, a USB data cable and an IPA file saved on Android. An OTG adapter or USB hub may be required. You can download IPA files with [TapOk IPA Downloader](../downloader/README.md).

## Usage

1. Download and open the APK on Android. Allow installation from the browser or file manager if prompted, then install the app.
2. Save the IPA on Android. Enable OTG if your phone has this setting, connect the phones with the cable and unlock the iPhone.
3. Open the installer and tap **Connect**. Allow USB access on Android and confirm trust on the iPhone if prompted.
4. Tap **Select IPA**, select the file, then tap **Install**. Keep the cable connected until **App installed** appears.
5. Open the installed app on the iPhone. If it requests an Apple ID, use the account that downloaded the IPA.

The IPA must be compatible with the iPhone's iOS version and have a valid signature. The installer does not re-sign apps or remove their Apple ID association.

## Troubleshooting

- **iPhone not detected:** check OTG and the data cable. If a direct USB-C connection fails, connect an OTG adapter or hub to Android, then connect the iPhone to it. [Connection help](docs/TESTING.md).
- **Installation failed:** check the log and the IPA's compatibility with iOS. Tap **Save log** to attach it to an issue; remove personal information first.

[All apps](../README.md) · [Report an issue](https://github.com/TapOk38/tapok-ipa-tools/issues) · [Data storage](PRIVACY.md)

</details>

Устанавливает IPA на iPhone с Android через USB.

**[Скачать APK](https://github.com/TapOk38/tapok-ipa-tools/releases/download/suite-v1.0.0-beta.5/TapOk-IPA-Installer-Android-0.7.0-beta.4.apk)** · 0.7.0-beta.4

## Требования

Android 8.0+ с поддержкой OTG, USB-кабель с передачей данных и IPA-файл на Android. Может потребоваться OTG-переходник или USB-хаб. Скачать IPA можно через [TapOk IPA Downloader](../downloader/README.md).

## Использование

1. Скачайте и откройте APK на Android. Если появится запрос, разрешите установку из браузера или файлового менеджера и установите приложение.
2. Сохраните IPA на Android. Включите OTG, если такой переключатель есть в настройках, соедините телефоны кабелем и разблокируйте iPhone.
3. Откройте установщик и переключите **EN → RU**. Нажмите **«Подключить»**, разрешите USB-доступ на Android и подтвердите доверие на iPhone, если появится запрос.
4. Нажмите **«Выбрать IPA»**, укажите файл и нажмите **«Установить»**. Не отключайте кабель до сообщения **«Приложение установлено»**.
5. Откройте установленное приложение на iPhone. Если потребуется Apple ID, используйте учётную запись, с которой скачан IPA.

IPA должен быть совместим с версией iOS на iPhone и иметь действующую подпись. Установщик не переподписывает приложения и не снимает привязку к Apple ID.

## Решение проблем

- **iPhone не определяется:** проверьте OTG и кабель с передачей данных. Если прямое соединение USB-C не работает, подключите OTG-переходник или хаб к Android, а iPhone — к нему. [Помощь с подключением](docs/TESTING.md).
- **Установка завершилась ошибкой:** проверьте журнал и совместимость IPA с iOS. Для обращения об ошибке нажмите **«Сохранить журнал»** и удалите из него личные данные.

[Все программы](../README.md) · [Сообщить об ошибке](https://github.com/TapOk38/tapok-ipa-tools/issues) · [Хранение данных](PRIVACY.md)
