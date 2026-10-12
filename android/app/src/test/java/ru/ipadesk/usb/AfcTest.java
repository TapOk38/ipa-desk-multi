package ru.ipadesk.usb;

import org.junit.Test;
import static org.junit.Assert.*;
import java.io.*;
import java.nio.*;

public class AfcTest {
    private byte[] reply(long sequence,long op,long value) {
        return ByteBuffer.allocate(48).order(ByteOrder.LITTLE_ENDIAN).put(Afc.MAGIC).putLong(48).putLong(40)
            .putLong(sequence).putLong(op).putLong(value).array();
    }
    @Test public void handlesStatusDataInPayload()throws Exception {
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        new Afc(new Plists.Channel(new ByteArrayInputStream(reply(1,1,0)),out)).mkdir("PublicStaging");
        assertEquals(9,Afc.le(out.toByteArray()).getLong(32));
    }
    @Test public void rejectsWrongResponseSequence() {
        Afc a=new Afc(new Plists.Channel(new ByteArrayInputStream(reply(5,1,0)),new ByteArrayOutputStream()));
        assertThrows(IOException.class,()->a.mkdir("PublicStaging"));
    }
    @Test public void doesNotTreatDeviceFailureAsSuccess() {
        Afc a=new Afc(new Plists.Channel(new ByteArrayInputStream(reply(1,1,10)),new ByteArrayOutputStream()));
        Afc.Status e=assertThrows(Afc.Status.class,()->a.removeIfExists("PublicStaging/test.ipa"));assertEquals(10,e.code);
    }
    @Test public void cleanupAcceptsArchiveAlreadyAbsent() throws Exception {
        Afc a=new Afc(new Plists.Channel(new ByteArrayInputStream(reply(1,1,8)),new ByteArrayOutputStream()));
        assertFalse(a.removeIfExists("PublicStaging/test.ipa"));
    }
    @Test public void cleanupDeletesOnlySpecifiedArchive() throws Exception {
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        Afc a=new Afc(new Plists.Channel(new ByteArrayInputStream(reply(1,1,0)),out));
        assertTrue(a.removeIfExists("PublicStaging/test.ipa"));
        byte[] sent=out.toByteArray();
        assertEquals(8,Afc.le(sent).getLong(32));
        assertArrayEquals("PublicStaging/test.ipa\0".getBytes("UTF-8"),java.util.Arrays.copyOfRange(sent,40,sent.length));
    }
    @Test public void rejectsUnexpectedSuccessMessageType() {
        Afc a=new Afc(new Plists.Channel(new ByteArrayInputStream(reply(1,14,0)),new ByteArrayOutputStream()));
        assertThrows(IOException.class,()->a.mkdir("PublicStaging"));
    }
}
