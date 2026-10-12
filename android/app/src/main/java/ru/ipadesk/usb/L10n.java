package ru.ipadesk.usb;

import java.util.Locale;

/** Shared by the Android UI and the resource-free protocol code/manual build. */
final class L10n {
    private static volatile String language = resolve(null, Locale.getDefault());
    private L10n() {}

    static String resolve(String saved, Locale system) {
        if ("ru".equals(saved) || "en".equals(saved)) return saved;
        return "en";
    }
    static void setLanguage(String value) {
        if (!"ru".equals(value) && !"en".equals(value)) throw new IllegalArgumentException("Unsupported language");
        language = value;
    }
    static String language() { return language; }
    static String t(Key key, Object... args) { return text(language, key, args); }
    static String text(String language, Key key, Object... args) {
        String pattern = "ru".equals(language) ? key.ru : key.en;
        return args.length == 0 ? pattern : String.format(Locale.ROOT, pattern, args);
    }

    enum Key {
        TITLE("Установка IPA", "Install IPA"),
        LANGUAGE("Язык", "Language"),
        IPA_NOT_SELECTED("IPA не выбран", "No IPA selected"),
        SELECT_IPA("Выбрать IPA", "Select IPA"),
        CONNECT("Подключить", "Connect"),
        DISCONNECTED("iPhone не подключён", "iPhone not connected"),
        INSTALL("Установить", "Install"),
        STOP("Остановить", "Stop"),
        READY("Готово к проверке", "Ready"),
        SAVE_LOG("Сохранить журнал", "Save log"),
        STOPPING("Остановка…", "Stopping…"),
        CONNECTED("iPhone подключён", "iPhone connected"),
        NO_USB("USB-устройства не обнаружены", "No USB devices found"),
        NO_USB_HELP("Android не видит ни одного USB-устройства. Сохраните журнал для проверки соединения.", "Android cannot detect any USB devices. Save the log to check the connection."),
        NO_IPHONE("iPhone не обнаружен", "iPhone not found"),
        NO_APPLE_HELP("Android видит USB-устройства, но среди них нет устройства Apple. Сохраните журнал.", "Android detects USB devices, but no Apple device. Save the log."),
        APPLE_FOUND("Устройство Apple обнаружено", "Apple device found"),
        NO_INTERFACE("Интерфейс iPhone недоступен", "iPhone interface unavailable"),
        NO_INTERFACE_HELP("Устройство Apple найдено, но USB-интерфейс для установки недоступен. Сохраните журнал.", "Apple device found, but the USB interface for installation is unavailable. Save the log."),
        MULTIPLE_APPLE("Подключено несколько устройств Apple", "Multiple Apple devices connected"),
        ONE_IPHONE("Оставьте подключённым один iPhone.", "Keep only one iPhone connected."),
        USB_ALLOW("Разрешите доступ USB", "Allow USB access"),
        CONNECT_FIRST("Сначала подключите iPhone.", "Connect your iPhone first."),
        PREPARING("Подготовка установки…", "Preparing installation…"),
        CONNECTING("Подключение…", "Connecting…"),
        INSTALLED("Приложение установлено", "App installed"),
        OPEN_FILE_FAILED("Не удалось открыть файл.", "Could not open the file."),
        LOG_SAVED("Журнал сохранён", "Log saved"),
        CHECKING_IPA("Проверка IPA…", "Checking IPA…"),
        DEFAULT_FILE("Приложение.ipa", "Application.ipa"),
        FILE_SELECTED("Файл: %s", "File: %s"),
        IPA_READ_FAILED("Не удалось прочитать IPA.", "Could not read the IPA."),
        IPA_SELECTED("IPA выбран", "IPA selected"),
        CANCELLED("Операция остановлена.", "Operation stopped."),
        TRUST_DENIED("На iPhone не разрешено доверие. Переподключите его и нажмите «Доверять».", "Trust was denied on the iPhone. Reconnect it and tap Trust."),
        UNLOCK_RETRY("Разблокируйте iPhone и повторите подключение.", "Unlock the iPhone and try connecting again."),
        STOPPED("Остановлено", "Stopped"),
        FAILED("Не удалось завершить — см. журнал", "Could not complete — see log"),
        WAIT_OR_STOP("Дождитесь завершения или остановите передачу", "Wait for completion or stop the transfer"),
        USB_DENIED("Доступ USB не разрешён", "USB access denied"),
        USB_DENIED_LOG("Доступ USB не разрешён.", "USB access denied."),
        APPLE_ATTACHED("Устройство Apple подключено. Нажмите «Подключить».", "Apple device attached. Tap Connect."),
        USB_DETACHED("USB отключён.", "USB disconnected."),
        AFC_ERROR("AFC: ошибка %s", "AFC: error %s"),
        AFC_BAD_REPLY("AFC: неверный ответ устройства.", "AFC: invalid device response."),
        AFC_SHORT_STATUS("AFC: неполный статус.", "AFC: incomplete status."),
        AFC_NO_ACK("AFC: отсутствует подтверждение операции.", "AFC: operation not acknowledged."),
        AFC_OPEN_FAILED("AFC: не удалось открыть файл.", "AFC: could not open the file."),
        TRANSFER_STOPPED("Передача остановлена.", "Transfer stopped."),
        IPA_SIZE_CHANGED("Размер IPA изменился во время передачи.", "IPA size changed during transfer."),
        MISSING_VALUE("iPhone не сообщил %s.", "iPhone did not provide %s."),
        CONNECTING_IPHONE("Подключение iPhone…", "Connecting to iPhone…"),
        UNKNOWN_REPLY("Неизвестный ответ iPhone.", "Unrecognized iPhone response."),
        TRUST_AGAIN("Повторное подтверждение доверия.", "Trust needs to be confirmed again."),
        CONNECTED_LOG("iPhone подключён.", "iPhone connected."),
        TRUST_KEY_MISSING("iPhone не передал ключ для подтверждения доверия.", "iPhone did not provide a pairing key."),
        TRUST_PROMPT("Разблокируйте iPhone и нажмите «Доверять».", "Unlock the iPhone and tap Trust."),
        TRUST_TIMEOUT("Доверие не подтверждено. Нажмите «Подключить» ещё раз.", "Trust was not confirmed. Tap Connect again."),
        SESSION_FAILED("iPhone не открыл сессию.", "iPhone did not open a session."),
        SECURING("Защищённое соединение…", "Establishing a secure connection…"),
        IOS_REQUIRED("Приложению требуется iOS %s или новее.", "This app requires iOS %s or later."),
        TRANSFERRING_LOG("Передача IPA…", "Transferring IPA…"),
        TRANSFERRING("Передача IPA", "Transferring IPA"),
        INSTALLING_LOG("Установка…", "Installing…"),
        INSTALLING("Установка", "Installing"),
        INSTALLED_LOG("Приложение установлено.", "App installed."),
        INSTALL_TIMEOUT("Время ожидания установки истекло.", "Installation timed out."),
        INSTALL_UNCONFIRMED("Результат установки не подтверждён. Проверьте приложение на iPhone.", "Installation could not be confirmed. Check the app on your iPhone."),
        INSTALL_REJECTED("iPhone отклонил установку: %s. %s", "iPhone rejected the installation: %s. %s"),
        INSTALL_STATUS_MISSING("iPhone не сообщил статус установки.", "iPhone did not report the installation status."),
        IPA_ENTRY_LARGE("Слишком большой служебный файл IPA.", "An IPA metadata file is too large."),
        IPA_BAD_PATH("IPA содержит недопустимые пути файлов.", "The IPA contains invalid file paths."),
        IPA_INVALID("Файл повреждён или не является IPA.", "The file is damaged or is not an IPA."),
        IPA_AMBIGUOUS_NAME("IPA содержит неоднозначные имена файлов.", "The IPA contains ambiguous file names."),
        IPA_UNSUPPORTED("IPA содержит зашифрованные файлы или неподдерживаемое сжатие.", "The IPA contains encrypted files or unsupported compression."),
        IPA_AMBIGUOUS_FOLDER("IPA содержит неоднозначную запись папки.", "The IPA contains an ambiguous folder entry."),
        IPA_DUPLICATE("В IPA повторяются имена файлов. Выберите другую копию IPA.", "The IPA contains duplicate file names. Select another copy of the IPA."),
        IPA_PATH_CONFLICT("IPA содержит конфликт файлов и папок.", "The IPA contains conflicting file and folder paths."),
        IPA_MULTIPLE_APPS("В IPA найдено несколько основных приложений.", "The IPA contains multiple main apps."),
        IPA_NO_APP("В IPA не найдено приложение Payload/*.app.", "No Payload/*.app application found in the IPA."),
        IPA_BAD_METADATA("IPA: неверные данные приложения.", "IPA: invalid app metadata."),
        IPA_NO_BINARY("В IPA отсутствует исполняемый файл.", "The IPA is missing its executable."),
        IOS_COMPARE_FAILED("Не удалось сравнить версии iOS.", "Could not compare iOS versions."),
        IOS_INVALID("Некорректная версия iOS.", "Invalid iOS version."),
        PHONE_TIMEOUT("iPhone не ответил вовремя. Разблокируйте его и проверьте USB-подключение.", "iPhone did not respond in time. Unlock it and check the USB connection."),
        MUX_BAD_LENGTH_VALUE("USB mux: неверная длина пакета %s", "USB mux: invalid packet length %s"),
        MUX_OVERFLOW("USB mux: переполнение буфера.", "USB mux: buffer overflow."),
        MUX_BAD_LENGTH("USB mux: неверная длина пакета.", "USB mux: invalid packet length."),
        MUX_SHORT_HEADER("USB mux: неполный заголовок.", "USB mux: incomplete header."),
        MUX_BAD_VERSION("USB mux: неверный ответ версии.", "USB mux: invalid version response."),
        MUX_UNSUPPORTED_VERSION("USB mux: версия %s не поддерживается.", "USB mux: version %s is not supported."),
        MUX_SHORT_TCP("USB mux: неполный TCP-пакет.", "USB mux: incomplete TCP packet."),
        MUX_BAD_PORT("USB mux: неверный порт.", "USB mux: invalid port."),
        CONNECTION_CLOSED("Соединение с iPhone закрыто.", "The iPhone connection is closed."),
        MUX_CHANNEL_RESET("iPhone прервал обмен по каналу %s. Сохраните журнал.", "iPhone interrupted communication on channel %s. Save the log."),
        MUX_CHANNEL_REJECTED("iPhone отклонил открытие канала %s. Сохраните журнал.", "iPhone refused to open channel %s. Save the log."),
        MUX_BAD_ACK("USB mux: некорректное подтверждение подключения.", "USB mux: invalid connection acknowledgement."),
        MUX_BUFFER_FULL("USB mux: входной буфер заполнен.", "USB mux: receive buffer full."),
        MUX_OUT_OF_ORDER("USB mux: нарушен порядок данных.", "USB mux: out-of-order data."),
        USB_INTERFACE_UNAVAILABLE("USB: интерфейс iPhone недоступен. Разблокируйте iPhone и переподключите кабель.", "USB: iPhone interface unavailable. Unlock the iPhone and reconnect the cable."),
        USB_OPEN_FAILED("USB: не удалось открыть устройство.", "USB: could not open the device."),
        USB_NO_ENDPOINTS("USB: отсутствуют каналы передачи.", "USB: transfer endpoints are missing."),
        USB_CONFIGURATION_FAILED("USB: не удалось выбрать конфигурацию iPhone.", "USB: could not select the iPhone configuration."),
        USB_BUSY("USB: интерфейс занят.", "USB: interface is busy."),
        USB_CLOSED("USB: соединение закрыто.", "USB: connection closed."),
        USB_WRITE_FAILED("USB: ошибка отправки. Проверьте кабель.", "USB: send failed. Check the cable."),
        USB_PACKET_FAILED("USB: ошибка завершения пакета.", "USB: failed to complete the packet."),
        PAIR_FORMAT_INVALID("Неверный формат записи доверия.", "Invalid pairing record format."),
        PAIR_RECORD_DAMAGED("Повреждена запись доверия.", "The pairing record is damaged."),
        PAIR_BAD_KEY("Неверный DevicePublicKey от iPhone.", "Invalid DevicePublicKey received from iPhone."),
        PLIST_MISSING_DATA("Нет данных %s.", "Missing data: %s."),
        PLIST_EXPECTED_DICT("Ожидался словарь plist.", "Expected a plist dictionary."),
        PLIST_READ_FAILED("Не удалось прочитать plist.", "Could not read the plist."),
        RESPONSE_BAD_LENGTH("Недопустимая длина ответа.", "Invalid response length."),
        RESPONSE_INTERRUPTED("iPhone прервал ответ.", "iPhone interrupted the response.");

        final String ru, en;
        Key(String ru, String en) { this.ru = ru; this.en = en; }
    }
}
