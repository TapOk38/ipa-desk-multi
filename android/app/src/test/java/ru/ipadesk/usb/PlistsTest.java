package ru.ipadesk.usb;

import com.dd.plist.NSDictionary;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.junit.Test;
import static org.junit.Assert.*;

public class PlistsTest {
    private static NSDictionary decodeFrame(byte[] frame) throws Exception {
        assertTrue(frame.length >= 4);
        assertEquals(frame.length - 4, ByteBuffer.wrap(frame).getInt());
        return Plists.parse(Arrays.copyOfRange(frame, 4, frame.length));
    }
    private static List<byte[]> payloads(MuxTest.Peer peer) {
        List<byte[]> result = new ArrayList<>();
        for (byte[] packet : peer.sent)
            if (packet.length > 36 && ByteBuffer.wrap(packet).getInt() == 6)
                result.add(Arrays.copyOfRange(packet, 36, packet.length));
        return result;
    }
    @Test public void sendsLengthAndUtf8BodyInOneStreamWrite() throws Exception {
        List<byte[]> writes = new ArrayList<>();
        OutputStream out = new OutputStream() {
            public void write(int b) { fail("Plist framing must not depend on bytewise DataOutputStream.writeInt"); }
            public void write(byte[] b, int offset, int length) {
                writes.add(Arrays.copyOfRange(b, offset, offset + length));
            }
        };
        new Plists.Channel(new ByteArrayInputStream(new byte[0]), out)
            .send(Plists.dict("Request", "QueryType", "Label", "Проверка 🔌"));
        // Desktop JDK and Android implement writeInt differently. A complete frame
        // in one array write makes packetization independent of that implementation.
        assertEquals("One pre-encoded frame, without a separately fragmented prefix", 1, writes.size());
        NSDictionary message = decodeFrame(writes.get(0));
        assertEquals("QueryType", Plists.str(message, "Request"));
        assertEquals("Проверка 🔌", Plists.str(message, "Label"));
    }
    @Test public void queryTypeRoundTripUsesOneMuxPayloadAndAcceptsSplitReply() throws Exception {
        MuxTest.Peer peer = new MuxTest.Peer();
        Mux mux = new Mux(peer); mux.start(); Mux.Channel transport = mux.connect(62078);
        byte[] reply = ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<plist version=\"1.0\"><dict><key>Type</key><string>com.apple.mobile.lockdown</string></dict></plist>")
            .getBytes(StandardCharsets.UTF_8);
        byte[] frame = ByteBuffer.allocate(4 + reply.length).putInt(reply.length).put(reply).array();
        // Incoming data may still arrive fragmented; the peer also splits USB reads.
        peer.tcp(62078, 1, 1, 1, 16, 512, Arrays.copyOfRange(frame, 0, 2));
        peer.tcp(62078, 1, 3, 1, 16, 512, Arrays.copyOfRange(frame, 2, frame.length));
        NSDictionary result = new Plists.Channel(transport.input, transport.output)
            .request(Plists.dict("Request", "QueryType", "Label", "IPA-USB"));
        assertEquals("com.apple.mobile.lockdown", Plists.str(result, "Type"));
        List<byte[]> sent = payloads(peer);
        assertEquals("Small lockdown request must leave as one mux payload", 1, sent.size());
        assertEquals("QueryType", Plists.str(decodeFrame(sent.get(0)), "Request"));
    }
    @Test public void largeUtf8FrameRespectsMuxWindowAndReassemblesExactly() throws Exception {
        MuxTest.Peer peer = new MuxTest.Peer(); peer.smallWindow = true;
        Mux mux = new Mux(peer); mux.start(); Mux.Channel transport = mux.connect(62078);
        String text = String.join("", Collections.nCopies(12000, "данные"));
        new Plists.Channel(transport.input, transport.output).send(Plists.dict("Value", text));
        ByteArrayOutputStream joined = new ByteArrayOutputStream();
        List<byte[]> sent = payloads(peer);
        assertTrue(sent.size() > 100);
        assertTrue(sent.get(0).length >= 4);
        for (byte[] payload : sent) { assertTrue(payload.length <= 256); joined.write(payload); }
        assertEquals(text, Plists.str(decodeFrame(joined.toByteArray()), "Value"));
    }
}
