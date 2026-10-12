package ru.ipadesk.usb;

import com.dd.plist.*;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;

final class Plists {
    static NSDictionary dict(Object... pairs) {
        NSDictionary d = new NSDictionary();
        for (int i = 0; i < pairs.length; i += 2) d.put((String)pairs[i], pairs[i + 1]);
        return d;
    }
    static String str(NSDictionary d, String key) {
        NSObject value = d.objectForKey(key);
        return value instanceof NSString ? ((NSString)value).getContent() : "";
    }
    static long number(NSDictionary d, String key, long fallback) {
        NSObject v = d.objectForKey(key); return v instanceof NSNumber ? ((NSNumber)v).longValue() : fallback;
    }
    static boolean yes(NSDictionary d, String key) {
        NSObject v = d.objectForKey(key); return v instanceof NSNumber && ((NSNumber)v).boolValue();
    }
    static byte[] data(NSDictionary d, String key) throws IOException {
        NSObject v = d.objectForKey(key);
        if (!(v instanceof NSData)) throw new IOException("Нет данных " + key + ".");
        return ((NSData)v).bytes();
    }
    static NSDictionary parse(byte[] bytes) throws IOException {
        try {
            NSObject p = PropertyListParser.parse(bytes);
            if (p instanceof NSDictionary) return (NSDictionary)p;
            throw new IOException("Ожидался словарь plist.");
        } catch (Exception e) { throw new IOException("Не удалось прочитать plist.", e); }
    }
    static byte[] exact(InputStream in, int n) throws IOException {
        if (n < 0 || n > 16 * 1024 * 1024) throw new IOException("Недопустимая длина ответа.");
        byte[] b = new byte[n]; int offset = 0;
        while (offset < n) {
            int count = in.read(b, offset, n - offset);
            if (count < 0) throw new EOFException("iPhone прервал ответ.");
            offset += count;
        }
        return b;
    }
    static final class Channel {
        InputStream in; OutputStream out;
        Channel(InputStream in, OutputStream out) { this.in = in; this.out = out; }
        void send(NSDictionary d) throws IOException {
            byte[] b = d.toXMLPropertyList().getBytes(StandardCharsets.UTF_8);
            // Android's DataOutputStream.writeInt writes four individual bytes.
            // On an unbuffered mux channel those became four tiny USB messages;
            // the device log shows lockdown resetting during this length prefix.
            // Pre-encode the whole plist frame; Mux handles larger payloads/windowing.
            byte[] frame = ByteBuffer.allocate(4 + b.length).putInt(b.length).put(b).array();
            out.write(frame); out.flush();
        }
        NSDictionary receive() throws IOException {
            int size = new DataInputStream(in).readInt();
            return parse(exact(in, size));
        }
        NSDictionary request(NSDictionary d) throws IOException { send(d); return receive(); }
    }
}
