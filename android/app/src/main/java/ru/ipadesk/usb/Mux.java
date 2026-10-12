package ru.ipadesk.usb;

import java.io.*;
import java.nio.*;
import java.util.*;
import java.util.function.Consumer;

/** Device-side USB mux v1/v2, NOT the localhost usbmuxd plist protocol.
 * Wire format and flow control follow libimobiledevice/usbmuxd src/device.c (GPL-2.0-or-3.0).
 * All I/O is serialized on the worker thread; only close() may run concurrently.
 */
public final class Mux implements Closeable {
    private final PacketIO wire;
    private final Consumer<String> diagnostics;
    private final Map<Integer, Channel> channels = new HashMap<>();
    private final byte[] buffer = new byte[131072], usbRead = new byte[16384];
    private int used, version, tx, rx = 65535, nextPort = 1;
    private volatile boolean closed;
    private int traceCount;
    public Mux(PacketIO wire) { this(wire, message -> {}); }
    public Mux(PacketIO wire, Consumer<String> diagnostics) { this.wire = wire; this.diagnostics = diagnostics; }
    private void trace(String message) {
        // Only numeric protocol metadata, never plist/TLS/IPA or control-message contents.
        if (traceCount < 80) diagnostics.accept("mux " + message);
        else if (traceCount == 80) diagnostics.accept("mux further packet metadata omitted");
        traceCount++;
    }
    static ByteBuffer be(byte[] b) { return ByteBuffer.wrap(b).order(ByteOrder.BIG_ENDIAN); }
    static long now() { return System.nanoTime() / 1_000_000; }
    static long u32(int n) { return Integer.toUnsignedLong(n); }
    static long delta(long a, long b) { return (a - b) & 0xffffffffL; }
    private void check(long deadline) throws IOException {
        if (closed || Thread.currentThread().isInterrupted()) throw new IOException(L10n.t(L10n.Key.CANCELLED));
        if (now() > deadline) throw new IOException(L10n.t(L10n.Key.PHONE_TIMEOUT));
    }
    public void start() throws IOException {
        trace("start");
        send(0, ByteBuffer.allocate(12).putInt(2).putInt(0).putInt(0).array());
        long until = now() + 15000;
        while (version == 0) pump(until);
    }
    private void send(int protocol, byte[] payload) throws IOException {
        check(now() + 5000);
        int header = version >= 2 ? 16 : 8;
        ByteBuffer b = ByteBuffer.allocate(header + payload.length).order(ByteOrder.BIG_ENDIAN);
        b.putInt(protocol).putInt(b.capacity());
        if (version >= 2) b.putInt(0xfeedface).putShort((short) tx++).putShort((short) rx);
        b.put(payload);
        trace("out protocol=" + protocol + " bytes=" + b.capacity() + " version=" + version);
        wire.write(b.array());
    }
    private void pump(long until) throws IOException {
        check(until);
        while (used < 8 || used < be(buffer).getInt(4)) {
            if (used >= 8) {
                int length = be(buffer).getInt(4);
                if (length < 8 || length > 65536) throw new IOException(L10n.t(L10n.Key.MUX_BAD_LENGTH_VALUE, length));
            }
            check(until);
            int n = wire.read(usbRead);
            if (n == 0) continue;
            if (used + n > buffer.length) throw new IOException(L10n.t(L10n.Key.MUX_OVERFLOW));
            System.arraycopy(usbRead, 0, buffer, used, n); used += n;
        }
        int length = be(buffer).getInt(4);
        if (length < 8 || length > 65536) throw new IOException(L10n.t(L10n.Key.MUX_BAD_LENGTH));
        byte[] packet = Arrays.copyOf(buffer, length);
        System.arraycopy(buffer, length, buffer, 0, used - length); used -= length;
        ByteBuffer b = be(packet);
        int protocol = b.getInt(); b.getInt();
        trace("in protocol=" + protocol + " bytes=" + length + " version=" + version);
        // A previous failed attempt may have left v2 TCP replies queued in the USB endpoint.
        // Their header must not be interpreted as v1 before the version reply arrives.
        if (version == 0 && protocol != 0) { trace("discard before version"); return; }
        int header = version >= 2 ? 16 : 8;
        if (length < header) throw new IOException(L10n.t(L10n.Key.MUX_SHORT_HEADER));
        if (version >= 2) { b.getInt(); b.getShort(); rx = b.getShort() & 65535; }
        if (protocol == 0) {
            if (version != 0) { trace("discard duplicate version"); return; }
            if (length < header + 12) throw new IOException(L10n.t(L10n.Key.MUX_BAD_VERSION));
            version = b.getInt();
            if (version != 1 && version != 2) throw new IOException(L10n.t(L10n.Key.MUX_UNSUPPORTED_VERSION, version));
            trace("negotiated version=" + version);
            if (version == 2) { tx = 0; rx = 65535; send(2, new byte[]{7}); }
        } else if (protocol == 6) {
            if (length < header + 20) throw new IOException(L10n.t(L10n.Key.MUX_SHORT_TCP));
            int source = b.getShort() & 65535, dest = b.getShort() & 65535;
            long seq = u32(b.getInt()), ack = u32(b.getInt());
            int offsetByte = b.get() & 255, flags = b.get() & 255;
            int window = (b.getShort() & 65535) << 8;
            // Device USB mux is TCP-like, not IP TCP. Like usbmuxd, consume a fixed
            // 20-byte struct tcphdr; its data-offset/options fields are not used here.
            int tcpHeader = 20;
            trace("tcp source=" + source + " dest=" + dest + " seq=" + seq + " ack=" + ack
                + " offsetByte=" + offsetByte + " flags=" + flags + " payload=" + (length-header-tcpHeader));
            Channel channel = channels.get(dest);
            if (channel == null || channel.port != source) return;
            channel.receive(seq, ack, window, flags, Arrays.copyOfRange(packet, header + tcpHeader, length));
        } else if (protocol == 1) {
            // usbmuxd reports control/error and warning notifications without tearing
            // down the connection. TCP RST and handshake deadlines remain failures.
            trace("control code=" + (length > header ? packet[header] & 255 : -1) + " bytes=" + (length-header));
        }
    }
    public Channel connect(int port) throws IOException {
        if (version == 0 || port < 1 || port > 65535) throw new IOException(L10n.t(L10n.Key.MUX_BAD_PORT));
        Channel channel = new Channel(nextPort++, port);
        channels.put(channel.localPort, channel);
        channel.tcp(2, new byte[0]);
        long until = now() + 15000;
        while (!channel.connected) { channel.checkError(); pump(until); }
        return channel;
    }
    public void close() throws IOException { closed = true; wire.close(); }
    public final class Channel implements Closeable {
        private final int localPort, port;
        private long seq, received, peerAck;
        private int peerWindow = 131072;
        private boolean connected, ended;
        private IOException failure;
        private final ArrayDeque<byte[]> queued = new ArrayDeque<>();
        private int queuedBytes, headOffset;
        private int timeoutMillis = 30000;
        Channel(int localPort, int port) { this.localPort = localPort; this.port = port; }
        public void timeout(int milliseconds) { timeoutMillis = milliseconds; }
        private void checkError() throws IOException {
            if (failure != null) throw failure;
            if (ended || closed) throw new IOException(L10n.t(L10n.Key.CONNECTION_CLOSED));
        }
        private void tcp(int flags, byte[] payload) throws IOException {
            ByteBuffer b = ByteBuffer.allocate(20 + payload.length).order(ByteOrder.BIG_ENDIAN);
            b.putShort((short) localPort).putShort((short) port).putInt((int) seq).putInt((int) received);
            int room = Math.max(0, 262144 - queuedBytes);
            b.put((byte) 0x50).put((byte) flags).putShort((short)(room >> 8)).putShort((short)0).putShort((short)0).put(payload);
            send(6, b.array());
        }
        private void receive(long remoteSeq, long ack, int window, int flags, byte[] payload) throws IOException {
            if ((flags & 4) != 0) {
                // Preserve the failure metadata even after the normal trace limit.
                // The RST payload may contain arbitrary device text; do not log it.
                diagnostics.accept("mux reset port=" + port + " phase=" + (connected ? "open" : "connecting")
                    + " seq=" + remoteSeq + " ack=" + ack + " sent=" + seq + " payload=" + payload.length);
                failure = new IOException(L10n.t(connected ? L10n.Key.MUX_CHANNEL_RESET : L10n.Key.MUX_CHANNEL_REJECTED, port));
                return;
            }
            peerWindow = window;
            if (!connected) {
                if ((flags & 0x12) != 0x12 || ack != 1) throw new IOException(L10n.t(L10n.Key.MUX_BAD_ACK));
                seq = 1; peerAck = ack; received = (remoteSeq + 1) & 0xffffffffL; connected = true;
                tcp(16, new byte[0]); return;
            }
            if ((flags & 16) != 0) {
                if (delta(ack, peerAck) <= delta(seq, peerAck)) peerAck = ack;
            }
            if (payload.length > 0) {
                if (remoteSeq == received) {
                    if (queuedBytes + payload.length > 262144) throw new IOException(L10n.t(L10n.Key.MUX_BUFFER_FULL));
                    queued.add(payload); queuedBytes += payload.length;
                    received = (received + payload.length) & 0xffffffffL;
                } else if (delta(received, remoteSeq) < payload.length) {
                    throw new IOException(L10n.t(L10n.Key.MUX_OUT_OF_ORDER));
                }
                tcp(16, new byte[0]);
            }
            if ((flags & 1) != 0) { ended = true; }
        }
        public final InputStream input = new InputStream() {
            public int read() throws IOException { byte[] b = new byte[1]; return read(b, 0, 1) < 0 ? -1 : b[0] & 255; }
            public int read(byte[] b, int off, int len) throws IOException {
                if (off < 0 || len < 0 || off > b.length - len) throw new IndexOutOfBoundsException();
                if (len == 0) return 0;
                long until = now() + timeoutMillis;
                while (queued.isEmpty()) { checkError(); pump(until); }
                byte[] head = queued.peek();
                int n = Math.min(len, head.length - headOffset);
                System.arraycopy(head, headOffset, b, off, n); headOffset += n; queuedBytes -= n;
                if (headOffset == head.length) { queued.remove(); headOffset = 0; }
                tcp(16, new byte[0]);
                return n;
            }
        };
        public final OutputStream output = new OutputStream() {
            public void write(int b) throws IOException { write(new byte[]{(byte)b}); }
            public void write(byte[] b, int off, int len) throws IOException {
                if (off < 0 || len < 0 || off > b.length - len) throw new IndexOutOfBoundsException();
                while (len > 0) {
                    checkError();
                    long until = now() + timeoutMillis;
                    while (peerWindow <= delta(seq, peerAck)) { checkError(); pump(until); }
                    int n = (int)Math.min(Math.min(len, 16000), peerWindow - delta(seq, peerAck));
                    tcp(16, Arrays.copyOfRange(b, off, off + n));
                    seq = (seq + n) & 0xffffffffL;
                    off += n; len -= n;
                }
            }
        };
        public void close() throws IOException {
            if (!ended && !closed) tcp(4, new byte[0]);
            ended = true; channels.remove(localPort);
        }
    }
}
