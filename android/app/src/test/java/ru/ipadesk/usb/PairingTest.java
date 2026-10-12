package ru.ipadesk.usb;

import org.junit.Test;
import static org.junit.Assert.*;
import java.io.*;
import java.security.*;
import java.security.cert.*;
import org.bouncycastle.openssl.jcajce.JcaPEMWriter;

public class PairingTest {
    @Test public void signsDeviceKeyAndKeepsPrivateKeyOutOfPairRequest()throws Exception {
        KeyPairGenerator g=KeyPairGenerator.getInstance("RSA");g.initialize(2048);KeyPair device=g.generateKeyPair();
        StringWriter text=new StringWriter();try(JcaPEMWriter w=new JcaPEMWriter(text)){w.writeObject(device.getPublic());}
        Pairing p=Pairing.create(text.toString().getBytes("US-ASCII"),"BUID");
        CertificateFactory cf=CertificateFactory.getInstance("X.509",new org.bouncycastle.jce.provider.BouncyCastleProvider());
        X509Certificate root=(X509Certificate)cf.generateCertificate(new ByteArrayInputStream(p.rootCert));
        X509Certificate host=(X509Certificate)cf.generateCertificate(new ByteArrayInputStream(p.hostCert));
        X509Certificate dev=(X509Certificate)cf.generateCertificate(new ByteArrayInputStream(p.deviceCert));
        root.verify(root.getPublicKey());host.verify(root.getPublicKey());dev.verify(root.getPublicKey());
        assertArrayEquals(device.getPublic().getEncoded(),dev.getPublicKey().getEncoded());
        assertFalse(p.publicRecord().containsKey("HostPrivateKey"));assertFalse(p.publicRecord().containsKey("RootPrivateKey"));
        assertFalse(p.publicRecord().containsKey("PrivateHostKeyPKCS8"));
        Pairing loaded=Pairing.restore(p.savedRecord());assertEquals(p.hostId,loaded.hostId);assertArrayEquals(p.hostKey,loaded.hostKey);
    }
    @Test public void rejectsInvalidPublicKey() { assertThrows(Exception.class,()->Pairing.create(new byte[]{1,2,3},"BUID")); }
}
