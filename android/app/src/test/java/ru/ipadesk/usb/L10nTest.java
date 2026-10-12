package ru.ipadesk.usb;

import static org.junit.Assert.*;
import java.io.*;
import java.util.*;
import org.junit.After;
import org.junit.Test;

public class L10nTest {
    private final String original = L10n.language();
    @After public void restoreLanguage() { L10n.setLanguage(original); }

    @Test public void selectsRussianOnlyForRussianSystemLocale() {
        assertEquals("ru", L10n.resolve(null, Locale.forLanguageTag("ru-RU")));
        assertEquals("ru", L10n.resolve(null, Locale.forLanguageTag("ru-KZ")));
        assertEquals("en", L10n.resolve(null, Locale.US));
        assertEquals("en", L10n.resolve(null, Locale.GERMANY));
        assertEquals("en", L10n.resolve(null, null));
    }
    @Test public void persistedChoiceOverridesSystemAndInvalidPreferenceFallsBack() {
        assertEquals("en", L10n.resolve("en", Locale.forLanguageTag("ru")));
        assertEquals("ru", L10n.resolve("ru", Locale.US));
        assertEquals("en", L10n.resolve("broken", Locale.JAPAN));
        assertEquals("ru", L10n.resolve("", Locale.forLanguageTag("ru")));
    }
    @Test public void catalogueIsCompleteAndParameterCountsMatch() {
        for (L10n.Key key : L10n.Key.values()) {
            assertFalse(key.name(), key.ru.trim().isEmpty());
            assertFalse(key.name(), key.en.trim().isEmpty());
            assertFalse(key.name(), key.en.matches(".*[А-Яа-яЁё].*"));
            int ruCount = key.ru.split("%s", -1).length - 1;
            int enCount = key.en.split("%s", -1).length - 1;
            assertEquals(key.name(), ruCount, enCount);
            Object[] args = new Object[ruCount]; Arrays.fill(args, "sample");
            assertFalse(key.name(), L10n.text("ru", key, args).contains("%s"));
            assertFalse(key.name(), L10n.text("en", key, args).contains("%s"));
        }
    }
    @Test public void changingLanguageAffectsNewProtocolErrors() {
        for (String lang : new String[]{"ru", "en"}) {
            L10n.setLanguage(lang);
            IOException reply = assertThrows(IOException.class, () -> Plists.exact(new ByteArrayInputStream(new byte[0]), 1));
            assertEquals(L10n.text(lang, L10n.Key.RESPONSE_INTERRUPTED), reply.getMessage());
            assertEquals(L10n.text(lang, L10n.Key.AFC_ERROR, 8), new Afc.Status(8).getMessage());
            IOException version = assertThrows(IOException.class, () -> Ipa.compareVersions("invalid", "16.0"));
            assertEquals(L10n.text(lang, L10n.Key.IOS_COMPARE_FAILED), version.getMessage());
        }
    }
    @Test public void preservesDeviceErrorCodesAndDescriptionsVerbatim() {
        String code = "ApplicationVerificationFailed", detail = "Device says: 100% / %s / Ошибка";
        for (String lang : new String[]{"ru", "en"}) {
            L10n.setLanguage(lang);
            IOException error = assertThrows(IOException.class, () -> Installer.installStatus(
                Plists.dict("Error", code, "ErrorDescription", detail)));
            assertEquals(L10n.text(lang, L10n.Key.INSTALL_REJECTED, code, detail), error.getMessage());
            assertTrue(error.getMessage().endsWith(detail));
            assertEquals(code, new Installer.DeviceError(code).getMessage());
        }
    }
    @Test public void preservesUnicodeFileNamesAndVersionMetadata() {
        String file = "Home Ключи_16.6+_100%.ipa";
        assertEquals("File: " + file, L10n.text("en", L10n.Key.FILE_SELECTED, file));
        assertEquals("Приложению требуется iOS 16.6 или новее.", L10n.text("ru", L10n.Key.IOS_REQUIRED, "16.6"));
        assertEquals("This app requires iOS 16.6 or later.", L10n.text("en", L10n.Key.IOS_REQUIRED, "16.6"));
    }
    @Test public void rejectsUnsupportedLanguageWithoutChangingSelection() {
        L10n.setLanguage("en");
        assertThrows(IllegalArgumentException.class, () -> L10n.setLanguage("de"));
        assertEquals("en", L10n.language());
    }
}
