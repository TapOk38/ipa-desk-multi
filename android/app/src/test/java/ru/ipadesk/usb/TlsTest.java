package ru.ipadesk.usb;

import java.io.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.*;
import org.junit.Test;
import static org.junit.Assert.*;
import org.bouncycastle.openssl.jcajce.JcaPEMWriter;
import org.bouncycastle.openssl.PEMParser;
import org.bouncycastle.cert.X509CertificateHolder;
import org.bouncycastle.crypto.util.PrivateKeyFactory;
import org.bouncycastle.tls.*;
import org.bouncycastle.tls.crypto.*;
import org.bouncycastle.tls.crypto.impl.bc.*;

public class TlsTest {
    private static byte[] der(byte[] pem)throws Exception {
        try(PEMParser p=new PEMParser(new StringReader(new String(pem,"US-ASCII")))) {return ((X509CertificateHolder)p.readObject()).getEncoded();}
    }
    private static Pairing pair(KeyPair device)throws Exception {
        StringWriter s=new StringWriter();try(JcaPEMWriter w=new JcaPEMWriter(s)){w.writeObject(device.getPublic());}
        return Pairing.create(s.toString().getBytes("US-ASCII"),"TEST-BUID");
    }
    private void exercise(boolean wrongKey)throws Exception {
        KeyPairGenerator gen=KeyPairGenerator.getInstance("RSA");gen.initialize(2048);
        KeyPair device=gen.generateKeyPair();Pairing identity=pair(device);
        Pairing clientIdentity=wrongKey?pair(gen.generateKeyPair()):identity;
        PipedInputStream clientIn=new PipedInputStream(65536),serverIn=new PipedInputStream(65536);
        PipedOutputStream serverOut=new PipedOutputStream(clientIn),clientOut=new PipedOutputStream(serverIn);
        byte[] serverCert=der(identity.deviceCert);
        ExecutorService thread=Executors.newSingleThreadExecutor();
        Future<Boolean> result=thread.submit(()->{
            BcTlsCrypto crypto=new BcTlsCrypto(new SecureRandom());
            TlsServerProtocol protocol=new TlsServerProtocol(serverIn,serverOut);
            protocol.accept(new DefaultTlsServer(crypto){
                @Override protected ProtocolVersion[] getSupportedVersions(){return new ProtocolVersion[]{ProtocolVersion.TLSv12};}
                @Override protected int[] getSupportedCipherSuites(){return new int[]{CipherSuite.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256};}
                @Override protected TlsCredentialedSigner getRSASignerCredentials()throws IOException {
                    return new BcDefaultTlsCredentialedSigner(new TlsCryptoParameters(context),crypto,
                        PrivateKeyFactory.createKey(device.getPrivate().getEncoded()),
                        new org.bouncycastle.tls.Certificate(new TlsCertificate[]{crypto.createCertificate(serverCert)}),
                        SignatureAndHashAlgorithm.getInstance(HashAlgorithm.sha256,SignatureAlgorithm.rsa));
                }
                @Override public CertificateRequest getCertificateRequest(){
                    Vector<SignatureAndHashAlgorithm> algorithms=new Vector<>();
                    algorithms.add(SignatureAndHashAlgorithm.getInstance(HashAlgorithm.sha256,SignatureAlgorithm.rsa));
                    return new CertificateRequest(new short[]{ClientCertificateType.rsa_sign},algorithms,new Vector<>());
                }
                @Override public void notifyClientCertificate(org.bouncycastle.tls.Certificate cert)throws IOException {
                    assertFalse(cert.isEmpty());
                    try{assertArrayEquals(der(identity.hostCert),cert.getCertificateAt(0).getEncoded());}
                    catch(Exception e){throw new IOException(e);}
                }
            });
            assertEquals(42,protocol.getInputStream().read());
            protocol.getOutputStream().write(24);protocol.getOutputStream().flush();return true;
        });
        try {
            Plists.Channel channel=new Plists.Channel(clientIn,clientOut);
            if(wrongKey) assertThrows(IOException.class,()->clientIdentity.tls(channel));
            else {
                clientIdentity.tls(channel);channel.out.write(42);channel.out.flush();
                assertEquals(24,channel.in.read());assertTrue(result.get(5,TimeUnit.SECONDS));
            }
        } finally {
            clientIn.close();clientOut.close();serverIn.close();serverOut.close();
            result.cancel(true);thread.shutdownNow();
        }
    }
    @Test(timeout=15000) public void performsMutualTlsAndExchangesData()throws Exception {exercise(false);}
    @Test(timeout=15000) public void rejectsDifferentDeviceCertificate()throws Exception {exercise(true);}
}
