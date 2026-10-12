import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.time.LocalDateTime;
import java.util.*;
import java.util.zip.*;

/** Aligns stored ZIP entries without native ZIP writers. No native libraries are packaged. */
public final class AlignApk {
    private static final class Counter extends FilterOutputStream {
        long count;
        Counter(OutputStream output) { super(output); }
        @Override public void write(int value) throws IOException { out.write(value); count++; }
        @Override public void write(byte[] bytes, int offset, int length) throws IOException {
            out.write(bytes, offset, length); count += length;
        }
    }
    public static void main(String[] args) throws Exception {
        try (ZipFile input = new ZipFile(args[0]);
             Counter counter = new Counter(Files.newOutputStream(Paths.get(args[1])));
             ZipOutputStream output = new ZipOutputStream(counter)) {
            Enumeration<? extends ZipEntry> entries = input.entries();
            byte[] buffer = new byte[32768];
            while (entries.hasMoreElements()) {
                ZipEntry source = entries.nextElement();
                if (source.getMethod() != ZipEntry.STORED && source.getMethod() != ZipEntry.DEFLATED)
                    throw new IOException("Unsupported compression: " + source.getName());
                ZipEntry entry = new ZipEntry(source.getName());
                entry.setTimeLocal(LocalDateTime.of(2000, 1, 1, 0, 0));
                // Older .NET ZIP writers may still DEFLATE with NoCompression.
                entry.setMethod(source.getName().equals("resources.arsc") ? ZipEntry.STORED : source.getMethod());
                if (entry.getMethod() == ZipEntry.STORED) {
                    entry.setSize(source.getSize()); entry.setCompressedSize(source.getSize());
                    entry.setCrc(source.getCrc());
                    long offset = counter.count + 30 + entry.getName().getBytes(StandardCharsets.UTF_8).length;
                    int padding = (int)((4 - offset % 4) % 4);
                    if (padding != 0) {
                        // Private extra field: four-byte header plus alignment padding.
                        byte[] extra = new byte[4 + padding];
                        extra[0] = 0x35; extra[1] = (byte)0xd9; extra[2] = (byte)padding;
                        entry.setExtra(extra);
                    }
                }
                output.putNextEntry(entry);
                if (entry.getMethod() == ZipEntry.STORED && counter.count % 4 != 0)
                    throw new IOException("Stored resource is not aligned: " + entry.getName());
                CRC32 crc = new CRC32(); long size = 0;
                try (InputStream stream = input.getInputStream(source)) {
                    int length;
                    while ((length = stream.read(buffer)) != -1) {
                        output.write(buffer, 0, length); crc.update(buffer, 0, length); size += length;
                    }
                }
                if (size != source.getSize() || crc.getValue() != source.getCrc())
                    throw new IOException("Resource checksum differs: " + entry.getName());
                output.closeEntry();
            }
        }
        System.out.println("APK stored resources aligned to four bytes; entry checksums preserved.");
    }
}
