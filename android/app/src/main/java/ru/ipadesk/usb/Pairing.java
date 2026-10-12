package ru.ipadesk.usb;

import com.dd.plist.*;
import java.io.*;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.cert.X509Certificate;
import java.util.*;
import org.bouncycastle.asn1.pkcs.PrivateKeyInfo;
import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x509.*;
import org.bouncycastle.cert.X509CertificateHolder;
import org.bouncycastle.cert.jcajce.*;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.openssl.*;
import org.bouncycastle.openssl.jcajce.*;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;
import org.bouncycastle.crypto.util.PrivateKeyFactory;
import org.bouncycastle.tls.*;
import org.bouncycastle.tls.crypto.*;
import org.bouncycastle.tls.crypto.impl.bc.*;

final class Pairing {
    private static final Provider BC = new BouncyCastleProvider();
    final String hostId, systemBuid;
    final byte[] hostCert, rootCert, deviceCert, hostKey;
    byte[] escrow;
    Pairing(String hostId, String systemBuid, byte[] hostCert, byte[] rootCert, byte[] deviceCert, byte[] hostKey) {
        this.hostId = hostId; this.systemBuid = systemBuid; this.hostCert = hostCert;
        this.rootCert = rootCert; this.deviceCert = deviceCert; this.hostKey = hostKey;
    }
    static Pairing create(byte[] devicePublicKey, String buid) throws Exception {
        KeyPairGenerator gen = KeyPairGenerator.getInstance("RSA"); gen.initialize(2048);
        KeyPair root = gen.generateKeyPair(), host = gen.generateKeyPair();
        PublicKey device;
        try (PEMParser parser = new PEMParser(new StringReader(new String(devicePublicKey, StandardCharsets.US_ASCII)))) {
            Object parsed = parser.readObject();
            if (parsed instanceof SubjectPublicKeyInfo) device = new JcaPEMKeyConverter().setProvider(BC).getPublicKey((SubjectPublicKeyInfo)parsed);
            else throw new IOException(L10n.t(L10n.Key.PAIR_BAD_KEY));
        }
        X509Certificate rootCertificate = certificate(root.getPublic(), root.getPrivate(), true);
        return new Pairing(UUID.randomUUID().toString().toUpperCase(Locale.ROOT), buid,
            pem(certificate(host.getPublic(), root.getPrivate(), false)), pem(rootCertificate),
            pem(certificate(device, root.getPrivate(), false)), host.getPrivate().getEncoded());
    }
    private static X509Certificate certificate(PublicKey publicKey, PrivateKey signer, boolean ca) throws Exception {
        Date before = new Date(System.currentTimeMillis() - 86400000L);
        Date after = new Date(System.currentTimeMillis() + 10L * 365 * 86400000L);
        // Apple pairing certificates use empty subjects/issuers; the root signs all three.
        X500Name empty = new X500Name("");
        JcaX509v3CertificateBuilder builder = new JcaX509v3CertificateBuilder(empty,
            new BigInteger(128, new SecureRandom()).add(BigInteger.ONE), before, after, empty, publicKey);
        builder.addExtension(Extension.basicConstraints, true, new BasicConstraints(ca));
        if (!ca) {
            builder.addExtension(Extension.keyUsage, true, new KeyUsage(KeyUsage.digitalSignature | KeyUsage.keyEncipherment));
            builder.addExtension(Extension.subjectKeyIdentifier, false, new JcaX509ExtensionUtils().createSubjectKeyIdentifier(publicKey));
        }
        return new JcaX509CertificateConverter().setProvider(BC).getCertificate(builder.build(
            new JcaContentSignerBuilder("SHA256withRSA").setProvider(BC).build(signer)));
    }
    private static byte[] pem(Object value) throws IOException {
        StringWriter text = new StringWriter();
        try (JcaPEMWriter writer = new JcaPEMWriter(text)) { writer.writeObject(value); }
        return text.toString().getBytes(StandardCharsets.US_ASCII);
    }
    private static byte[] der(byte[] pem) throws IOException {
        try (PEMParser p = new PEMParser(new StringReader(new String(pem, StandardCharsets.US_ASCII)))) {
            return ((X509CertificateHolder)p.readObject()).getEncoded();
        }
    }
    NSDictionary publicRecord() {
        return Plists.dict("HostID", hostId, "SystemBUID", systemBuid, "HostCertificate", new NSData(hostCert),
            "RootCertificate", new NSData(rootCert), "DeviceCertificate", new NSData(deviceCert));
    }
    NSDictionary savedRecord() {
        NSDictionary d = publicRecord(); d.put("PrivateHostKeyPKCS8", new NSData(hostKey));
        if (escrow != null) d.put("EscrowBag", new NSData(escrow));
        return d;
    }
    static Pairing restore(NSDictionary d) throws IOException {
        Pairing p = new Pairing(Plists.str(d, "HostID"), Plists.str(d, "SystemBUID"), Plists.data(d, "HostCertificate"),
            Plists.data(d, "RootCertificate"), Plists.data(d, "DeviceCertificate"), Plists.data(d, "PrivateHostKeyPKCS8"));
        if (d.objectForKey("EscrowBag") instanceof NSData) p.escrow = Plists.data(d, "EscrowBag");
        return p;
    }
    void tls(Plists.Channel channel) throws IOException {
        BcTlsCrypto crypto = new BcTlsCrypto(new SecureRandom());
        byte[] deviceDer = der(deviceCert);
        SubjectPublicKeyInfo expectedKey = new X509CertificateHolder(deviceDer).getSubjectPublicKeyInfo();
        TlsClientProtocol protocol = new TlsClientProtocol(channel.in, channel.out);
        protocol.connect(new DefaultTlsClient(crypto) {
            @Override protected ProtocolVersion[] getSupportedVersions() { return new ProtocolVersion[]{ProtocolVersion.TLSv12}; }
            @Override protected int[] getSupportedCipherSuites() {
                return new int[]{CipherSuite.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256, CipherSuite.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
                    CipherSuite.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256, CipherSuite.TLS_RSA_WITH_AES_128_GCM_SHA256,
                    CipherSuite.TLS_RSA_WITH_AES_128_CBC_SHA};
            }
            @Override public TlsAuthentication getAuthentication() {
                return new TlsAuthentication() {
                    public void notifyServerCertificate(TlsServerCertificate remote) throws IOException {
                        if (remote.getCertificate().isEmpty()) throw new TlsFatalAlert(AlertDescription.bad_certificate);
                        X509CertificateHolder cert = new X509CertificateHolder(remote.getCertificate().getCertificateAt(0).getEncoded());
                        if (!MessageDigest.isEqual(expectedKey.getEncoded(), cert.getSubjectPublicKeyInfo().getEncoded()))
                            throw new TlsFatalAlert(AlertDescription.bad_certificate);
                    }
                    public TlsCredentials getClientCredentials(CertificateRequest req) throws IOException {
                        SignatureAndHashAlgorithm algorithm = SignatureAndHashAlgorithm.getInstance(HashAlgorithm.sha256, SignatureAlgorithm.rsa);
                        Vector<?> supported = req.getSupportedSignatureAlgorithms();
                        if (supported != null && !supported.contains(algorithm)) {
                            algorithm = SignatureAndHashAlgorithm.rsa_pss_rsae_sha256;
                            if (!supported.contains(algorithm)) throw new TlsFatalAlert(AlertDescription.handshake_failure);
                        }
                        org.bouncycastle.tls.Certificate certs = new org.bouncycastle.tls.Certificate(new TlsCertificate[]{
                            crypto.createCertificate(der(hostCert)), crypto.createCertificate(der(rootCert))});
                        return new BcDefaultTlsCredentialedSigner(new TlsCryptoParameters(context), crypto,
                            PrivateKeyFactory.createKey(PrivateKeyInfo.getInstance(hostKey)), certs, algorithm);
                    }
                };
            }
        });
        channel.in = protocol.getInputStream(); channel.out = protocol.getOutputStream();
    }
}
