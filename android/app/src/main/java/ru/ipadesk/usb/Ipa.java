package ru.ipadesk.usb;

import com.dd.plist.*;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.zip.CRC32;
import java.util.zip.ZipEntry;
import java.util.zip.ZipException;
import org.apache.commons.compress.archivers.zip.ZipArchiveEntry;
import org.apache.commons.compress.archivers.zip.ZipFile;

final class Ipa {
    final File file;
    final String bundle, title, version, minimum;
    final byte[] metadata, sinf;
    private Ipa(File file, String bundle, String title, String version, String minimum, byte[] metadata, byte[] sinf) {
        this.file = file; this.bundle = bundle; this.title = title; this.version = version;
        this.minimum = minimum; this.metadata = metadata; this.sinf = sinf;
    }
    static byte[] read(ZipFile zip, ZipArchiveEntry entry, int limit) throws IOException {
        if (entry == null) return null;
        if (entry.getSize() > limit) throw new IOException(L10n.t(L10n.Key.IPA_ENTRY_LARGE));
        try (InputStream in = zip.getInputStream(entry); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            CRC32 crc = new CRC32(); byte[] b = new byte[8192]; int n;
            while ((n = in.read(b)) != -1) {
                if (out.size() + n > limit) throw new IOException(L10n.t(L10n.Key.IPA_ENTRY_LARGE));
                out.write(b, 0, n); crc.update(b, 0, n);
            }
            if (out.size() != entry.getSize() || crc.getValue() != entry.getCrc())
                throw new ZipException("IPA entry size/CRC mismatch");
            return out.toByteArray();
        }
    }
    private static void checkPath(String name) throws IOException {
        if (name.isEmpty() || name.startsWith("/") || name.contains("\\") || name.contains(":") || name.indexOf('\0') >= 0)
            throw new IOException(L10n.t(L10n.Key.IPA_BAD_PATH));
        String[] parts = name.split("/", -1);
        for (int i = 0; i < parts.length; i++) {
            if (parts[i].equals(".") || parts[i].equals("..") || (parts[i].isEmpty() && i < parts.length - 1))
                throw new IOException(L10n.t(L10n.Key.IPA_BAD_PATH));
        }
    }
    private static ZipFile openZip(File file) throws IOException {
        try {
            // Android ZipFile rejects even repeated empty directory records. Read the
            // central directory with Commons Compress, retaining our own ambiguity checks.
            // Never rewrite the IPA: Installer uploads exactly the selected bytes.
            return ZipFile.builder().setFile(file).setCharset(StandardCharsets.UTF_8)
                .setUseUnicodeExtraFields(false).setMaxNumberOfDisks(1).get();
        } catch (IOException e) { throw new IOException(L10n.t(L10n.Key.IPA_INVALID), e); }
    }
    private static Collection<ZipArchiveEntry> checkedEntries(ZipFile zip, long fileSize) throws IOException {
        Map<String, ZipArchiveEntry> names = new LinkedHashMap<>();
        Enumeration<ZipArchiveEntry> entries = zip.getEntries();
        while (entries.hasMoreElements()) {
            if (Thread.currentThread().isInterrupted()) throw new IOException(L10n.t(L10n.Key.CANCELLED));
            ZipArchiveEntry e = entries.nextElement();
            // Check raw UTF-8 too: some ZIP readers normalize backslashes in DOS entries.
            String rawName = StandardCharsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(e.getRawName())).toString();
            checkPath(rawName); checkPath(e.getName());
            if (!rawName.equals(e.getName())) throw new IOException(L10n.t(L10n.Key.IPA_AMBIGUOUS_NAME));
            if ((e.getMethod() != ZipEntry.STORED && e.getMethod() != ZipEntry.DEFLATED) || !zip.canReadEntryData(e))
                throw new IOException(L10n.t(L10n.Key.IPA_UNSUPPORTED));
            if (e.getSize() < 0 || e.getDataOffset() < 0 || e.getCompressedSize() < 0 ||
                    e.getDataOffset() > fileSize || e.getCompressedSize() > fileSize - e.getDataOffset())
                throw new ZipException("IPA entry outside archive");
            if (e.isDirectory()) {
                if (e.isUnixSymlink()) throw new IOException(L10n.t(L10n.Key.IPA_AMBIGUOUS_FOLDER));
                read(zip, e, 0); // An empty directory must actually contain zero bytes, with CRC=0.
            }
            String key = e.isDirectory() ? e.getName().substring(0, e.getName().length() - 1) : e.getName();
            ZipArchiveEntry previous = names.get(key);
            if (previous != null) {
                if (!previous.isDirectory() || !e.isDirectory())
                    throw new IOException(L10n.t(L10n.Key.IPA_DUPLICATE));
                continue; // Only duplicate empty directories are harmless.
            }
            names.put(key, e);
        }
        for (String name : names.keySet()) {
            for (int slash = name.indexOf('/'); slash >= 0; slash = name.indexOf('/', slash + 1)) {
                ZipArchiveEntry parent = names.get(name.substring(0, slash));
                if (parent != null && !parent.isDirectory()) throw new IOException(L10n.t(L10n.Key.IPA_PATH_CONFLICT));
            }
        }
        return names.values();
    }
    static Ipa open(File file) throws IOException {
        try (ZipFile zip = openZip(file)) {
            ZipArchiveEntry info = null;
            for (ZipArchiveEntry e : checkedEntries(zip, file.length())) {
                if (e.getName().matches("Payload/[^/]+\\.app/Info\\.plist")) {
                    if (info != null) throw new IOException(L10n.t(L10n.Key.IPA_MULTIPLE_APPS));
                    info = e;
                }
            }
            if (info == null) throw new IOException(L10n.t(L10n.Key.IPA_NO_APP));
            NSDictionary d = Plists.parse(read(zip, info, 4 * 1024 * 1024));
            String bundle = Plists.str(d, "CFBundleIdentifier"), exe = Plists.str(d, "CFBundleExecutable");
            if (bundle.isEmpty() || exe.isEmpty() || exe.contains("/") || exe.contains("\\")) throw new IOException(L10n.t(L10n.Key.IPA_BAD_METADATA));
            String dir = info.getName().substring(0, info.getName().lastIndexOf('/') + 1);
            ZipArchiveEntry binary = zip.getEntry(dir + exe);
            if (binary == null || binary.isDirectory() || binary.isUnixSymlink()) throw new IOException(L10n.t(L10n.Key.IPA_NO_BINARY));
            String title = Plists.str(d, "CFBundleDisplayName"); if (title.isEmpty()) title = Plists.str(d, "CFBundleName");
            if (title.isEmpty()) title = bundle;
            byte[] meta = read(zip, zip.getEntry("iTunesMetadata.plist"), 8 * 1024 * 1024);
            if (meta != null) Plists.parse(meta);
            byte[] sinf = read(zip, zip.getEntry(dir + "SC_Info/" + exe + ".sinf"), 2 * 1024 * 1024);
            return new Ipa(file, bundle, title, Plists.str(d, "CFBundleShortVersionString"), Plists.str(d, "MinimumOSVersion"), meta, sinf);
        } catch (ZipException e) { throw new IOException(L10n.t(L10n.Key.IPA_INVALID), e); }
    }
    static int compareVersions(String first, String second) throws IOException {
        if (!first.matches("[0-9]+(\\.[0-9]+)*") || !second.matches("[0-9]+(\\.[0-9]+)*"))
            throw new IOException(L10n.t(L10n.Key.IOS_COMPARE_FAILED));
        String[] a = first.split("\\."), b = second.split("\\.");
        try {
            for (int i = 0; i < Math.max(a.length, b.length); i++) {
                int av = i < a.length ? Integer.parseInt(a[i]) : 0, bv = i < b.length ? Integer.parseInt(b[i]) : 0;
                if (av != bv) return Integer.compare(av, bv);
            }
            return 0;
        } catch (NumberFormatException e) { throw new IOException(L10n.t(L10n.Key.IOS_INVALID)); }
    }
    NSDictionary options() {
        NSDictionary d = Plists.dict("CFBundleIdentifier", bundle);
        // Do not force PackageType=Developer: preserve App Store/FairPlay metadata.
        if (metadata != null) d.put("iTunesMetadata", new NSData(metadata));
        if (sinf != null) d.put("ApplicationSINF", new NSData(sinf));
        return d;
    }
}
