package ru.ipadesk.usb;

import java.io.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.function.LongConsumer;

final class Afc {
    private final InputStream in;
    private final OutputStream out;
    private long sequence;
    static final byte[] MAGIC = "CFA6LPAA".getBytes(StandardCharsets.US_ASCII);
    Afc(Plists.Channel stream) { in = stream.in; out = stream.out; }
    static ByteBuffer le(byte[] b) { return ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN); }
    static byte[] value(long n) { return ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(n).array(); }
    static byte[] path(String path) { return (path + "\0").getBytes(StandardCharsets.UTF_8); }
    static class Status extends IOException {
        final long code;
        Status(long code) { super("AFC: ошибка " + code); this.code = code; }
    }
    static final class Reply {
        final long op; final byte[] data;
        Reply(long op, byte[] data) { this.op = op; this.data = data; }
    }
    private Reply request(long operation, byte[] headerData, byte[] payload) throws IOException {
        long id = ++sequence;
        ByteBuffer header = ByteBuffer.allocate(40).order(ByteOrder.LITTLE_ENDIAN);
        header.put(MAGIC).putLong(40L + headerData.length + payload.length).putLong(40L + headerData.length).putLong(id).putLong(operation);
        out.write(header.array()); out.write(headerData); out.write(payload); out.flush();
        ByteBuffer response = le(Plists.exact(in, 40));
        byte[] magic = new byte[8]; response.get(magic);
        long entire = response.getLong(), first = response.getLong(), responseId = response.getLong(), op = response.getLong();
        if (!Arrays.equals(magic, MAGIC) || entire < 40 || entire > 1024 * 1024 || first < 40 || first > entire || responseId != id)
            throw new IOException("AFC: неверный ответ устройства.");
        byte[] data = Plists.exact(in, (int)entire - 40);
        if (op == 1) {
            if (data.length != 8) throw new IOException("AFC: неполный статус.");
            long code = le(data).getLong(); if (code != 0) throw new Status(code);
        }
        return new Reply(op, data);
    }
    private void status(long op, byte[] header, byte[] payload) throws IOException {
        if (request(op, header, payload).op != 1) throw new IOException("AFC: отсутствует подтверждение операции.");
    }
    void mkdir(String remote) throws IOException {
        try { status(9, path(remote), new byte[0]); } catch (Status e) { if (e.code != 16) throw e; }
    }
    boolean removeIfExists(String remote) throws IOException {
        try { status(8, path(remote), new byte[0]); return true; }
        catch (Status e) {
            // AFC_E_OBJECT_NOT_FOUND: the staging archive is already absent.
            if (e.code == 8) return false;
            throw e;
        }
    }
    void upload(String remote, File file, LongConsumer progress) throws IOException {
        byte[] name = path(remote);
        byte[] open = ByteBuffer.allocate(8 + name.length).order(ByteOrder.LITTLE_ENDIAN).putLong(3).put(name).array();
        Reply reply = request(13, open, new byte[0]);
        if (reply.op != 14 || reply.data.length != 8) throw new IOException("AFC: не удалось открыть файл.");
        byte[] handle = reply.data;
        long size = file.length(), total = 0;
        IOException failed = null;
        try (InputStream source = new FileInputStream(file)) {
            byte[] chunk = new byte[65536]; int n;
            while ((n = source.read(chunk)) != -1) {
                if (Thread.currentThread().isInterrupted()) throw new IOException("Передача остановлена.");
                status(16, handle, n == chunk.length ? chunk : Arrays.copyOf(chunk, n));
                total += n; progress.accept(total);
            }
            if (total != size) throw new IOException("Размер IPA изменился во время передачи.");
        } catch (IOException e) { failed = e; throw e; }
        finally {
            try { status(20, handle, new byte[0]); }
            catch (IOException e) { if (failed == null) throw e; }
        }
    }
}
