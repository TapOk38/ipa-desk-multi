import java.io.*;
import java.nio.*;
import java.nio.file.*;
import java.util.zip.*;

/** Retains AAPT2's complete, CRC-checked binary manifest, then writes a fresh ZIP.
 * This build sandbox crashes native AAPT when finalizing resources/ZIP archives.
 * The app uses platform resources only; no compiled app resource table is required.
 * Do NOT use this fallback for an app with custom resources.
 */
public final class RecoverManifest {
    public static void main(String[] args) throws Exception {
        byte[] manifest = null;
        try (ZipInputStream in = new ZipInputStream(Files.newInputStream(Paths.get(args[0])))) {
            ZipEntry entry;
            while ((entry = in.getNextEntry()) != null) {
                if (entry.getName().equals("AndroidManifest.xml")) {
                    ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                    byte[] block = new byte[8192]; int n;
                    while ((n = in.read(block)) != -1) {
                        if (bytes.size() + n > 1024 * 1024) throw new IOException("Manifest too large");
                        bytes.write(block,0,n);
                    }
                    in.closeEntry(); // validates the ZIP entry CRC, even when the central directory is absent
                    manifest=bytes.toByteArray(); break;
                }
            }
        }
        if (manifest == null || manifest.length < 8) throw new IOException("AAPT did not finish the binary manifest");
        ByteBuffer data=ByteBuffer.wrap(manifest).order(ByteOrder.LITTLE_ENDIAN);
        if (data.getShort()!=3 || data.getShort()!=8 || data.getInt()!=manifest.length)
            throw new IOException("Invalid binary XML root");
        int pos=8;
        while(pos<manifest.length) {
            if(pos+8>manifest.length)throw new IOException("Truncated XML chunk");
            int header=data.getShort(pos+2)&65535, size=data.getInt(pos+4);
            if(header<8 || size<header || size>manifest.length-pos)throw new IOException("Invalid XML chunk length");
            pos+=size;
        }
        try(ZipOutputStream out=new ZipOutputStream(Files.newOutputStream(Paths.get(args[1])))) {
            out.putNextEntry(new ZipEntry("AndroidManifest.xml"));out.write(manifest);out.closeEntry();
        }
        System.out.println("Binary manifest validated: "+manifest.length+" bytes");
    }
}
