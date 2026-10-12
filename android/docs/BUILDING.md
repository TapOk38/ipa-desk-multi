# Сборка из исходников

Для обычной установки скачайте [готовый APK](https://github.com/TapOk38/ipa-desk-multi/releases/download/android-v0.6.0-beta.1/ipa-usb-0.6.0-beta.1.apk). Инструкция ниже нужна только для самостоятельной сборки.

Потребуются JDK 17, Android SDK Platform 35 и Build Tools 35.0.0. Укажите пути в `JAVA_HOME` и `ANDROID_HOME`.

Все команды ниже выполняются из папки `android/` этого репозитория:

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

При первом запуске Gradle скачает необходимые инструменты. Debug APK появится в `app/build/outputs/apk/debug/`.

## Сборка скриптом на Windows

Проверка исходников и запуск тестов:

```powershell
.\Build-Manual.ps1 -Sdk 'C:\Android\sdk' -Jdk 'C:\Java\jdk-17' -TestsOnly
```

Для сборки APK задайте пароли своего ключа в переменных окружения `IPA_USB_STORE_PASSWORD` и `IPA_USB_KEY_PASSWORD`, затем запустите:

```powershell
.\Build-Manual.ps1 -Sdk 'C:\Android\sdk' -Jdk 'C:\Java\jdk-17' -KeyStore 'C:\Keys\release.jks' -KeyAlias 'release'
```

Результат: `manual-build/ipa-usb-0.6.0-beta.1.apk`. Скрипт не скачивает JDK и Android SDK.

Для обновления установленного приложения нужен тот же ключ подписи. APK, подписанный другим ключом, не установится поверх опубликованной версии.

Зависимости находятся в `libs/` и `test-libs/`, их контрольные суммы — в `DEPENDENCIES.sha256`, лицензии и ссылки на исходники — в [NOTICE](../licenses/NOTICE.txt).
