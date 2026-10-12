import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;

/** Checks both ZIP access paths: signature verification alone does not validate local headers. */
public final class VerifyApk {
    public static void main(String[] args) throws Exception {
        Set<String> expected = new HashSet<>(), streamed = new HashSet<>();
        byte[] buffer = new byte[65536];
        try (ZipFile archive = new ZipFile(args[0])) {
            for (Enumeration<? extends ZipEntry> entries = archive.entries(); entries.hasMoreElements();) {
                ZipEntry entry = entries.nextElement();
                if (!expected.add(entry.getName())) throw new IOException("Duplicate ZIP entry: " + entry.getName());
                CRC32 crc = new CRC32(); long size = 0;
                try (InputStream in = archive.getInputStream(entry)) {
                    int n; while ((n = in.read(buffer)) != -1) { crc.update(buffer, 0, n); size += n; }
                }
                if (size != entry.getSize() || crc.getValue() != entry.getCrc())
                    throw new IOException("ZIP size/CRC mismatch: " + entry.getName());
            }
        }
        // Sequential reading validates local headers and data descriptors. ZipFile
        // alone accepts a missing descriptor if the central directory is intact.
        try (ZipInputStream in = new ZipInputStream(Files.newInputStream(Paths.get(args[0])))) {
            ZipEntry entry;
            while ((entry = in.getNextEntry()) != null) {
                if (!streamed.add(entry.getName())) throw new IOException("Duplicate local ZIP entry: " + entry.getName());
                while (in.read(buffer) != -1) {}
                in.closeEntry();
            }
        }
        if (!streamed.equals(expected)) throw new IOException("Local ZIP entries differ from the central directory");
        if (!expected.contains("AndroidManifest.xml") || !expected.contains("classes.dex")) throw new IOException("Incomplete APK");
        System.out.println("APK ZIP verified: " + expected.size() + " entries, local headers and content CRCs valid");
    }
}
