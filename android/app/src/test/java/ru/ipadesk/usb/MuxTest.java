package ru.ipadesk.usb;

import org.junit.Test;
import static org.junit.Assert.*;
import java.io.*;
import java.nio.*;
import java.util.*;

public class MuxTest {
    /** Synthetic peer; wire-regression cases below also inject literal frames independently. */
    static final class Peer implements PacketIO {
        final ArrayDeque<Byte> inbound = new ArrayDeque<>();
        final ArrayList<byte[]> sent = new ArrayList<>();
        int muxVersion, source, dest;
        boolean smallWindow, reset;
        long deviceSeq = 1;
        void enqueue(byte[] b) { for (byte x : b) inbound.add(x); }
        public int read(byte[] b) { int n = 0; while (n < Math.min(7,b.length) && !inbound.isEmpty()) b[n++] = inbound.remove(); return n; }
        public void close() { }
        byte[] mux(int type, byte[] body) {
            ByteBuffer b = ByteBuffer.allocate((muxVersion == 2 ? 16 : 8) + body.length);
            b.putInt(type).putInt(b.capacity());
            if (muxVersion == 2) b.putInt(0xfeedface).putShort((short)1).putShort((short)1);
            return b.put(body).array();
        }
        void tcp(int src, int dst, long seq, long ack, int flags, int window, byte[] payload) {
            ByteBuffer b = ByteBuffer.allocate(20 + payload.length);
            b.putShort((short)src).putShort((short)dst).putInt((int)seq).putInt((int)ack).put((byte)0x50).put((byte)flags);
            b.putShort((short)window).putInt(0).put(payload); enqueue(mux(6,b.array()));
        }
        public void write(byte[] packet) throws IOException {
            sent.add(packet.clone()); ByteBuffer b = ByteBuffer.wrap(packet);
            int proto = b.getInt(); assertEquals(packet.length,b.getInt());
            if (proto == 0) {
                assertEquals(20,packet.length); assertEquals(2,b.getInt());
                enqueue(mux(0,ByteBuffer.allocate(12).putInt(2).putInt(0).putInt(0).array()));
                muxVersion = 2; return;
            }
            assertEquals(0xfeedface,b.getInt()); b.getShort(); b.getShort();
            if (proto == 2) { assertEquals(7,b.get()); return; }
            assertEquals(6,proto);
            int src=b.getShort()&65535,dst=b.getShort()&65535;
            long seq=Integer.toUnsignedLong(b.getInt()); b.getInt(); b.get(); int flags=b.get()&255; b.getShort(); b.getInt();
            if (flags == 2) {
                source=src;dest=dst;
                tcp(dst,src,0,seq+1,reset?4:18,smallWindow?1:512,new byte[0]);
            } else if (packet.length > 36) {
                int n=packet.length-36;
                if (smallWindow) assertTrue("Must respect 256-byte receive window",n<=256);
                tcp(dst,src,deviceSeq,seq+n,16,smallWindow?1:512,new byte[0]);
            }
        }
    }
    @Test public void negotiatesDeviceProtocolAndConnectsLockdown() throws Exception {
        Peer peer=new Peer(); Mux mux=new Mux(peer); mux.start(); mux.connect(62078);
        assertEquals(62078,peer.dest); assertEquals(4,peer.sent.size());
        assertArrayEquals(new byte[]{0,0,0,0,0,0,0,20,0,0,0,2,0,0,0,0,0,0,0,0},peer.sent.get(0));
    }
    @Test public void routesInterleavedServicesAndBuffersData() throws Exception {
        Peer p=new Peer(); Mux m=new Mux(p); m.start(); Mux.Channel a=m.connect(62078),b=m.connect(12345);
        p.tcp(12345,2,1,1,16,512,new byte[]{4,5,6});
        p.tcp(62078,1,1,1,16,512,new byte[]{1,2,3});
        assertArrayEquals(new byte[]{1,2,3},Plists.exact(a.input,3));
        assertArrayEquals(new byte[]{4,5,6},Plists.exact(b.input,3));
    }
    @Test public void respectsReceiveWindowForLargeUpload() throws Exception {
        Peer p=new Peer();p.smallWindow=true;Mux m=new Mux(p);m.start();Mux.Channel c=m.connect(1234);
        c.output.write(new byte[30000]);
        assertTrue(p.sent.size()>100);
    }
    @Test public void ignoresDuplicatePayload() throws Exception {
        Peer p=new Peer();Mux m=new Mux(p);m.start();Mux.Channel c=m.connect(1234);
        p.tcp(1234,1,1,1,16,512,new byte[]{9});
        p.tcp(1234,1,1,1,16,512,new byte[]{9});
        p.tcp(1234,1,2,1,16,512,new byte[]{8});
        assertEquals(9,c.input.read());assertEquals(8,c.input.read());
    }
    @Test public void rejectsResetDuringConnect() throws Exception {
        Peer p=new Peer();p.reset=true;List<String> trace=new ArrayList<>();Mux m=new Mux(p,trace::add);m.start();
        IOException failure=assertThrows(IOException.class,()->m.connect(62078));
        assertTrue(failure.getMessage().contains("отклонил открытие"));
        assertTrue(String.join("\n",trace).contains("phase=connecting"));
    }
    @Test public void resetAfterOpenSurvivesTraceLimitWithoutLoggingPayload() throws Exception {
        Peer p=new Peer();p.smallWindow=true;List<String> trace=new ArrayList<>();
        Mux m=new Mux(p,trace::add);m.start();Mux.Channel c=m.connect(62078);
        c.output.write(new byte[30000]);
        assertTrue(String.join("\n",trace).contains("further packet metadata omitted"));
        p.tcp(62078,1,1,30001,4,0,"private-reset-text".getBytes("UTF-8"));
        IOException failure=assertThrows(IOException.class,()->c.input.read());
        assertTrue(failure.getMessage().contains("прервал обмен"));
        String text=String.join("\n",trace);
        assertTrue(text.contains("mux reset port=62078 phase=open"));
        assertFalse(text.contains("private-reset-text"));
    }
    @Test public void rejectsOversizedFramesBeforeAllocation() {
        Peer p=new Peer();p.enqueue(ByteBuffer.allocate(8).putInt(0).putInt(Integer.MAX_VALUE).array());
        assertThrows(IOException.class,()->new Mux(p).start());
    }
    @Test public void closeUnblocksFutureReads() throws Exception {
        Peer p=new Peer();Mux m=new Mux(p);m.start();Mux.Channel c=m.connect(62078);m.close();
        assertThrows(IOException.class,()->c.input.read());
    }
    static byte[] hex(String value) {
        String s = value.replace(" ", ""); byte[] bytes = new byte[s.length() / 2];
        for (int i = 0; i < bytes.length; i++) bytes[i] = (byte)Integer.parseInt(s.substring(i*2,i*2+2),16);
        return bytes;
    }
    @Test public void notificationDoesNotAbortVersionNegotiation() throws Exception {
        Peer p = new Peer();
        // v1 control/error (3), one opaque text byte. usbmuxd treats it as a notification.
        p.enqueue(hex("00000001 0000000a 03 78"));
        Mux m = new Mux(p); m.start(); m.connect(62078);
        assertEquals(62078, p.dest);
    }
    @Test public void notificationDoesNotAbortActiveChannel() throws Exception {
        Peer p = new Peer(); Mux m = new Mux(p); m.start(); Mux.Channel c = m.connect(62078);
        p.enqueue(hex("00000001 00000012 feedface 0003 0002 03 78"));
        p.tcp(62078,1,1,1,16,512,new byte[]{42});
        assertEquals(42,c.input.read());
    }
    @Test public void priorSessionTcpIsDiscardedUntilVersionReply() throws Exception {
        Peer p = new Peer();
        // A full v2 SYN/ACK left in USB after the previous attempt closed its handle.
        p.enqueue(hex("00000006 00000024 feedface 0001 0001 f27e0001 00000000 00000001 50120200 00000000"));
        Mux m = new Mux(p); m.start(); m.connect(62078);
        assertEquals(62078,p.dest);
    }
    @Test public void deviceUsesFixedTcpLikeHeaderEvenWithZeroOffset() throws Exception {
        Peer p = new Peer(); Mux m = new Mux(p); m.start(); Mux.Channel c = m.connect(62078);
        // usbmuxd uses sizeof(tcphdr)=20, not the unused network TCP data-offset field.
        p.enqueue(hex("00000006 00000027 feedface 0002 0002 f27e0001 00000001 00000001 00100200 00000000 aabbcc"));
        assertArrayEquals(hex("aabbcc"),Plists.exact(c.input,3));
    }
    @Test public void deviceOffsetDoesNotTruncateFixedHeaderPayload() throws Exception {
        Peer p = new Peer(); Mux m = new Mux(p); m.start(); Mux.Channel c = m.connect(62078);
        p.enqueue(hex("00000006 00000029 feedface 0002 0002 f27e0001 00000001 00000001 f0100200 00000000 0102030405"));
        assertArrayEquals(hex("0102030405"),Plists.exact(c.input,5));
    }
    @Test public void truncatedTcpStillFails() throws Exception {
        Peer p = new Peer(); Mux m = new Mux(p); m.start(); Mux.Channel c = m.connect(62078);
        p.enqueue(hex("00000006 00000023 feedface 0002 0002 f27e0001 00000001 00000001 50100200 000000"));
        assertThrows(IOException.class,()->c.input.read());
    }
    @Test public void serviceCleanupKeepsLockdownOnSameMuxSession() throws Exception {
        Peer p = new Peer(); Mux m = new Mux(p); m.start(); Mux.Channel lockdown = m.connect(62078);
        Mux.Channel service = m.connect(12345); service.close();
        m.connect(23456);
        p.tcp(62078,1,1,1,16,512,new byte[]{99});
        assertEquals(99,lockdown.input.read());
        assertEquals(1,p.sent.stream().filter(b -> ByteBuffer.wrap(b).getInt() == 0).count());
        assertThrows(IOException.class,()->service.output.write(1));
    }
    @Test public void diagnosticTraceOmitsAllPayloadContents() throws Exception {
        Peer p = new Peer(); List<String> trace = new ArrayList<>();
        Mux m = new Mux(p,trace::add); m.start(); Mux.Channel c = m.connect(62078);
        byte[] privateBytes = "private-token-not-for-logs".getBytes("UTF-8");
        p.tcp(62078,1,1,1,16,512,privateBytes);
        assertArrayEquals(privateBytes,Plists.exact(c.input,privateBytes.length));
        byte[] control = new byte[privateBytes.length + 1]; control[0] = 3;
        System.arraycopy(privateBytes,0,control,1,privateBytes.length);
        p.enqueue(p.mux(1,control));
        p.tcp(62078,1,1+privateBytes.length,1,16,512,new byte[]{7});
        assertEquals(7,c.input.read());
        String text = String.join("\n",trace);
        assertTrue(text.contains("control code=3"));
        assertTrue(text.contains("payload="));
        assertFalse(text.contains("private-token"));
    }
}
