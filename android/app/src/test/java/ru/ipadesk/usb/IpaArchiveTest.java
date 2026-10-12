package ru.ipadesk.usb;

import org.junit.*;
import org.junit.rules.TemporaryFolder;
import static org.junit.Assert.*;
import java.io.*;
import java.nio.file.Files;
import java.util.zip.CRC32;
import java.util.zip.ZipException;
import org.apache.commons.compress.archivers.zip.*;

public class IpaArchiveTest {
    @Rule public TemporaryFolder temp = new TemporaryFolder();
    private static final String ROOT = "Payload/FreshKeys.app/";
    private static final byte[] EMPTY = new byte[0];

    private void entry(ZipArchiveOutputStream out, String name, byte[] data) throws IOException {
        ZipArchiveEntry e = new ZipArchiveEntry(name);
        e.setMethod(0); e.setSize(data.length);
        CRC32 crc = new CRC32(); crc.update(data); e.setCrc(crc.getValue());
        e.setUnixMode(name.endsWith("/") ? 040755 : 0100755);
        out.putArchiveEntry(e); out.write(data); out.closeArchiveEntry();
    }
    private File archive(Zip64Mode mode, String[] names, byte[][] data) throws Exception {
        File f = temp.newFile();
        try (ZipArchiveOutputStream out = new ZipArchiveOutputStream(f)) {
            out.setUseZip64(mode);
            entry(out, ROOT, EMPTY); entry(out, ROOT + "SC_Info/", EMPTY);
            entry(out, ROOT + "Info.plist", Plists.dict("CFBundleIdentifier", "test.keys", "CFBundleExecutable", "FreshKeys",
                "CFBundleDisplayName", "Тестовое приложение", "CFBundleShortVersionString", "1.2.1", "MinimumOSVersion", "16.0")
                .toXMLPropertyList().getBytes("UTF-8"));
            entry(out, ROOT + "FreshKeys", new byte[] {1, 2, 3});
            entry(out, ROOT + "SC_Info/FreshKeys.sinf", new byte[] {4, 5, 6});
            entry(out, "iTunesMetadata.plist", Plists.dict("itemId", 123).toXMLPropertyList().getBytes("UTF-8"));
            for (int i = 0; i < names.length; i++) entry(out, names[i], data[i]);
        }
        return f;
    }
    private File repeatedFolders(Zip64Mode mode) throws Exception {
        return archive(mode, new String[] {ROOT, ROOT + "SC_Info/"}, new byte[][] {EMPTY, EMPTY});
    }
    @Test public void acceptsRepeatedEmptyFoldersWithoutChangingArchiveOrFairPlayData() throws Exception {
        File f = repeatedFolders(Zip64Mode.AsNeeded);
        byte[] before = Files.readAllBytes(f.toPath());
        Ipa ipa = Ipa.open(f);
        assertSame(f, ipa.file); assertEquals("Тестовое приложение", ipa.title);
        assertEquals("1.2.1", ipa.version); assertEquals("16.0", ipa.minimum);
        assertArrayEquals(new byte[] {4, 5, 6}, ipa.sinf);
        assertTrue(ipa.options().containsKey("iTunesMetadata"));
        assertArrayEquals(before, Files.readAllBytes(f.toPath()));
    }
    @Test public void handlesZip64WithRepeatedFolders() throws Exception {
        assertEquals("test.keys", Ipa.open(repeatedFolders(Zip64Mode.Always)).bundle);
    }
    @Test public void rejectsDuplicateFilesEvenWhenContentsAreIdentical() throws Exception {
        File f = archive(Zip64Mode.AsNeeded, new String[] {ROOT + "FreshKeys"}, new byte[][] {{1, 2, 3}});
        IOException e = assertThrows(IOException.class, () -> Ipa.open(f));
        assertEquals(L10n.t(L10n.Key.IPA_DUPLICATE), e.getMessage());
    }
    @Test public void rejectsDuplicateInfoPlist() throws Exception {
        File f = archive(Zip64Mode.AsNeeded, new String[] {ROOT + "Info.plist"}, new byte[][] {EMPTY});
        assertEquals(L10n.t(L10n.Key.IPA_DUPLICATE), assertThrows(IOException.class, () -> Ipa.open(f)).getMessage());
    }
    @Test public void rejectsDirectoryWithHiddenContents() throws Exception {
        File f = archive(Zip64Mode.AsNeeded, new String[] {ROOT}, new byte[][] {{42}});
        assertThrows(IOException.class, () -> Ipa.open(f));
    }
    @Test public void rejectsFileDirectoryCollisionAndFileAsParent() throws Exception {
        for (String name : new String[] {"Payload/FreshKeys.app", ROOT + "FreshKeys/", ROOT + "FreshKeys/child"}) {
            File f = archive(Zip64Mode.AsNeeded, new String[] {name}, new byte[][] {EMPTY});
            assertThrows(name, IOException.class, () -> Ipa.open(f));
        }
    }
    @Test public void rejectsUnsafePathsWithTheIndependentZipReader() throws Exception {
        for (String name : new String[] {"../outside", "/absolute", "Payload/../outside", "Payload//bad", "C:/bad", "Payload/./bad"}) {
            File f = archive(Zip64Mode.AsNeeded, new String[] {name}, new byte[][] {EMPTY});
            assertThrows(name, IOException.class, () -> Ipa.open(f));
        }
    }
    @Test public void rejectsRawBackslashEvenWhenReaderNormalizesIt() throws Exception {
        File f = archive(Zip64Mode.AsNeeded, new String[] {"Payload/bad"}, new byte[][] {EMPTY});
        byte[] data = Files.readAllBytes(f.toPath()), name = "Payload/bad".getBytes("UTF-8");
        int replaced = 0;
        for (int i = 0; i <= data.length - name.length; i++) {
            boolean match = true;
            for (int j = 0; j < name.length; j++) if (data[i+j] != name[j]) { match = false; break; }
            if (match) { data[i+7] = '\\'; replaced++; }
        }
        assertEquals(2, replaced); // Local and central-directory names.
        Files.write(f.toPath(), data);
        assertThrows(IOException.class, () -> Ipa.open(f));
    }
    @Test public void rejectsWrongMetadataCrc() throws Exception {
        File f = repeatedFolders(Zip64Mode.AsNeeded); long offset;
        try (ZipFile zip = ZipFile.builder().setFile(f).get()) { offset = zip.getEntry("iTunesMetadata.plist").getDataOffset(); }
        try (RandomAccessFile bytes = new RandomAccessFile(f, "rw")) { bytes.seek(offset); bytes.write('!'); }
        IOException e = assertThrows(IOException.class, () -> Ipa.open(f));
        assertTrue(e.getCause() instanceof ZipException);
    }
    @Test public void rejectsTruncatedArchive() throws Exception {
        File f = repeatedFolders(Zip64Mode.AsNeeded);
        try (RandomAccessFile bytes = new RandomAccessFile(f, "rw")) { bytes.setLength(bytes.length() / 2); }
        assertThrows(IOException.class, () -> Ipa.open(f));
    }
}
