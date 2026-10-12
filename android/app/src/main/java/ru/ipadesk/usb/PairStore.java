package ru.ipadesk.usb;

import android.content.Context;
import android.security.keystore.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;

/** Pairing keys only. Apple ID/password/SMS are never requested or stored. */
final class PairStore {
    private final Context context;
    PairStore(Context context) { this.context = context; }
    private File file(String device) throws Exception {
        byte[] hash = MessageDigest.getInstance("SHA-256").digest(device.getBytes(StandardCharsets.UTF_8));
        StringBuilder s = new StringBuilder(); for (byte b : hash) s.append(String.format("%02x", b & 255));
        return new File(context.getNoBackupFilesDir(), "pair-" + s + ".bin");
    }
    private SecretKey key() throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore"); ks.load(null);
        String alias = "ipa-usb-pairing-v1";
        if (!ks.containsAlias(alias)) {
            KeyGenerator gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            gen.init(new KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
            return gen.generateKey();
        }
        return (SecretKey)ks.getKey(alias, null);
    }
    Pairing load(String device) throws Exception {
        File f = file(device); if (!f.exists()) return null;
        try (DataInputStream in = new DataInputStream(new FileInputStream(f))) {
            if (in.readInt() != 0x49504131) throw new IOException("Неверный формат записи доверия.");
            byte[] nonce = Plists.exact(in, 12); int size = in.readInt();
            if (size < 16 || size > 65536) throw new IOException("Повреждена запись доверия.");
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding"); c.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, nonce));
            c.updateAAD(device.getBytes(StandardCharsets.UTF_8));
            return Pairing.restore(Plists.parse(c.doFinal(Plists.exact(in, size))));
        }
    }
    void save(String device, Pairing pair) throws Exception {
        Cipher c = Cipher.getInstance("AES/GCM/NoPadding"); c.init(Cipher.ENCRYPT_MODE, key());
        c.updateAAD(device.getBytes(StandardCharsets.UTF_8));
        byte[] data = c.doFinal(pair.savedRecord().toXMLPropertyList().getBytes(StandardCharsets.UTF_8));
        File target = file(device), temp = new File(target.getPath() + ".tmp");
        try (DataOutputStream out = new DataOutputStream(new FileOutputStream(temp))) {
            out.writeInt(0x49504131); out.write(c.getIV()); out.writeInt(data.length); out.write(data);
        }
        java.nio.file.Files.move(temp.toPath(), target.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
    }
    void remove(String device) throws Exception { java.nio.file.Files.deleteIfExists(file(device).toPath()); }
}
