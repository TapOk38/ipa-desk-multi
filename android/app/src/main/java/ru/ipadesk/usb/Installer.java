package ru.ipadesk.usb;

import com.dd.plist.*;
import android.content.Context;
import java.io.*;
import java.util.*;

final class Installer implements Closeable {
    interface Listener {
        void log(String message);
        void device(String description);
        void progress(String stage, int value);
        void installing();
        void diagnostic(String message);
    }
    private final Context context;
    private final Mux mux;
    private final Listener listener;
    private final PairStore store;
    private final List<Mux.Channel> serviceChannels = new ArrayList<>();
    private Plists.Channel lockdown;
    private Pairing pair;
    private String ios = "";
    private volatile boolean closed;
    Installer(Context context, PacketIO wire, Listener listener) {
        this.context = context; this.mux = new Mux(wire, listener::diagnostic); this.listener = listener; store = new PairStore(context);
    }
    private NSDictionary request(String verb, Object... arguments) throws IOException {
        NSDictionary d = Plists.dict(arguments); d.put("Request", verb); d.put("Label", "IPA-USB");
        // Only our fixed request names and outcomes, never argument/response values.
        listener.diagnostic("lockdown begin request=" + verb);
        NSDictionary result;
        try { result = lockdown.request(d); }
        catch (IOException e) { listener.diagnostic("lockdown failed request=" + verb); throw e; }
        String error = Plists.str(result, "Error");
        listener.diagnostic("lockdown reply request=" + verb + " error=" + !error.isEmpty());
        if (!error.isEmpty()) throw new DeviceError(error);
        return result;
    }
    static class DeviceError extends IOException {
        final String code;
        DeviceError(String code) { super(code); this.code = code; }
    }
    private NSObject value(String key) throws IOException { return request("GetValue", "Key", key).objectForKey("Value"); }
    private String string(String key) throws IOException {
        NSObject v = value(key); if (!(v instanceof NSString)) throw new IOException(L10n.t(L10n.Key.MISSING_VALUE, key));
        return ((NSString)v).getContent();
    }
    void connect() throws Exception {
        listener.log(L10n.t(L10n.Key.CONNECTING_IPHONE));
        mux.start();
        Mux.Channel transport = mux.connect(62078);
        lockdown = new Plists.Channel(transport.input, transport.output);
        if (!"com.apple.mobile.lockdown".equals(Plists.str(request("QueryType"), "Type"))) throw new IOException(L10n.t(L10n.Key.UNKNOWN_REPLY));
        String udid = string("UniqueDeviceID");
        ios = string("ProductVersion"); String model = string("ProductType");
        listener.device(model + " • iOS " + ios);
        listener.log(model + " • iOS " + ios);
        try { pair = store.load(udid); }
        catch (Exception e) { listener.log(L10n.t(L10n.Key.TRUST_AGAIN)); pair = null; }
        if (pair != null) {
            try { session(transport); listener.log(L10n.t(L10n.Key.CONNECTED_LOG)); return; }
            catch (DeviceError e) {
                if (!Arrays.asList("InvalidHostID", "InvalidPairRecord", "MissingPairRecord").contains(e.code)) throw e;
                store.remove(udid); pair = null;
            }
        }
        NSObject key = value("DevicePublicKey");
        if (!(key instanceof NSData)) throw new IOException(L10n.t(L10n.Key.TRUST_KEY_MISSING));
        String buid = context.getSharedPreferences("usb", 0).getString("buid", null);
        if (buid == null) {
            buid = UUID.randomUUID().toString().toUpperCase(Locale.ROOT);
            context.getSharedPreferences("usb", 0).edit().putString("buid", buid).apply();
        }
        pair = Pairing.create(((NSData)key).bytes(), buid);
        listener.log(L10n.t(L10n.Key.TRUST_PROMPT));
        long deadline = Mux.now() + 120000;
        transport.timeout(15000);
        while (true) {
            if (closed || Thread.currentThread().isInterrupted()) throw new IOException(L10n.t(L10n.Key.CANCELLED));
            if (Mux.now() > deadline) throw new IOException(L10n.t(L10n.Key.TRUST_TIMEOUT));
            try {
                NSDictionary response = request("Pair", "PairRecord", pair.publicRecord(), "ProtocolVersion", "2",
                    "PairingOptions", Plists.dict("ExtendedPairingErrors", true));
                if (response.objectForKey("EscrowBag") instanceof NSData) pair.escrow = Plists.data(response, "EscrowBag");
                break;
            } catch (DeviceError e) {
                if (!e.code.equals("PairingDialogResponsePending")) throw e;
                Thread.sleep(750);
            }
        }
        store.save(udid, pair);
        transport.timeout(30000); session(transport);
        listener.log(L10n.t(L10n.Key.CONNECTED_LOG));
    }
    private void session(Mux.Channel transport) throws IOException {
        NSDictionary response = request("StartSession", "HostID", pair.hostId, "SystemBUID", pair.systemBuid);
        if (Plists.str(response, "SessionID").isEmpty()) throw new IOException(L10n.t(L10n.Key.SESSION_FAILED));
        if (Plists.yes(response, "EnableSessionSSL")) {
            transport.timeout(15000);
            listener.log(L10n.t(L10n.Key.SECURING));
            listener.diagnostic("lockdown TLS begin");
            pair.tls(lockdown);
            listener.diagnostic("lockdown TLS complete");
            transport.timeout(30000);
        }
    }
    private Plists.Channel service(String name, int timeout) throws IOException {
        NSDictionary response = request("StartService", "Service", name);
        int port = (int)Plists.number(response, "Port", 0);
        Mux.Channel channel = mux.connect(port); channel.timeout(timeout);
        serviceChannels.add(channel);
        Plists.Channel result = new Plists.Channel(channel.input, channel.output);
        if (Plists.yes(response, "EnableServiceSSL")) pair.tls(result);
        return result;
    }
    void install(Ipa ipa) throws Exception {
        if (!ipa.minimum.isEmpty() && Ipa.compareVersions(ios, ipa.minimum) < 0)
            throw new IOException(L10n.t(L10n.Key.IOS_REQUIRED, ipa.minimum));
        String remote = "PublicStaging/ipa-usb-" + UUID.randomUUID() + ".ipa";
        Afc afc = new Afc(service("com.apple.afc", 30000));
        boolean submitted = false, complete = false, failedByDevice = false;
        try {
            afc.mkdir("PublicStaging");
            listener.log(L10n.t(L10n.Key.TRANSFERRING_LOG));
            afc.upload(remote, ipa.file, n -> listener.progress(L10n.t(L10n.Key.TRANSFERRING), (int)(100 * n / Math.max(1, ipa.file.length()))));
            Plists.Channel install = service("com.apple.mobile.installation_proxy", 90000);
            if (closed || Thread.currentThread().isInterrupted()) throw new IOException(L10n.t(L10n.Key.CANCELLED));
            listener.installing();
            listener.log(L10n.t(L10n.Key.INSTALLING_LOG));
            submitted = true;
            install.send(Plists.dict("Command", "Install", "PackagePath", remote, "ClientOptions", ipa.options()));
            long deadline = Mux.now() + 15 * 60000;
            while (Mux.now() < deadline) {
                NSDictionary response = install.receive();
                if (!Plists.str(response, "Error").isEmpty()) failedByDevice = true;
                String status = installStatus(response);
                int percent = (int)Plists.number(response, "PercentComplete", -1);
                listener.progress(L10n.t(L10n.Key.INSTALLING), percent);
                if (status.equals("Complete")) { complete = true; listener.log(L10n.t(L10n.Key.INSTALLED_LOG)); return; }
            }
            throw new IOException(L10n.t(L10n.Key.INSTALL_TIMEOUT));
        } finally {
            // Never remove an archive while installation_proxy might still be using it.
            if (!submitted || complete || failedByDevice) {
                try {
                    boolean removed = afc.removeIfExists(remote);
                    listener.diagnostic("staging cleanup " + (removed ? "removed" : "already absent"));
                } catch (Afc.Status e) { listener.diagnostic("staging cleanup failed afcStatus=" + e.code); }
                catch (IOException e) { listener.diagnostic("staging cleanup unconfirmed type=" + e.getClass().getSimpleName()); }
            } else listener.log(L10n.t(L10n.Key.INSTALL_UNCONFIRMED));
            for (Mux.Channel channel : serviceChannels) {
                try { channel.close(); }
                catch (IOException e) { listener.diagnostic("service channel close failed"); }
            }
            serviceChannels.clear();
        }
    }
    static String installStatus(NSDictionary response) throws IOException {
        String error = Plists.str(response, "Error");
        if (!error.isEmpty()) throw new IOException(L10n.t(L10n.Key.INSTALL_REJECTED, error, Plists.str(response, "ErrorDescription")));
        String status = Plists.str(response, "Status");
        if (status.isEmpty()) throw new IOException(L10n.t(L10n.Key.INSTALL_STATUS_MISSING));
        return status;
    }
    public void close() { closed = true; try { mux.close(); } catch (IOException ignored) {} }
}
