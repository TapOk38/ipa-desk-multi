package ru.ipadesk.usb;

import android.app.*;
import android.content.*;
import android.database.Cursor;
import android.graphics.*;
import android.hardware.usb.*;
import android.net.Uri;
import android.os.*;
import android.provider.OpenableColumns;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.concurrent.*;

public final class MainActivity extends Activity implements Installer.Listener {
    private static final int PICK_IPA = 11, SAVE_LOG = 12;
    private static final String USB_PERMISSION = "ru.ipadesk.usb.prototype.USB_PERMISSION";
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final StringBuilder journal = new StringBuilder();
    private final StringBuilder usbJournal = new StringBuilder();
    private UsbManager usb;
    private TextView heading, fileLabel, deviceLabel, status, logView;
    private Button pick, connect, install, stop, save;
    private Spinner language;
    private L10n.Key statusKey = L10n.Key.READY, deviceKey = L10n.Key.DISCONNECTED;
    private String deviceInfo = "";
    private ProgressBar progress;
    private ScrollView logScroll;
    private Ipa ipa;
    private volatile Installer engine;
    private volatile Future<?> task;
    private volatile boolean cancelled, destroyed;
    private boolean busy, waitingPermission, connectionVerified;
    private volatile boolean installing;
    private volatile UsbDevice activeDevice;
    private final BroadcastReceiver receiver = new BroadcastReceiver() {
        @Override public void onReceive(Context c, Intent intent) {
            UsbDevice device = Build.VERSION.SDK_INT >= 33 ? intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice.class)
                : intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            if (USB_PERMISSION.equals(intent.getAction())) {
                if (!waitingPermission || device == null || activeDevice == null || device.getDeviceId() != activeDevice.getDeviceId()) return;
                waitingPermission = false;
                captureUsb("permission");
                if (usb.hasPermission(device)) runConnection(false);
                else { setStatus(L10n.Key.USB_DENIED); log(L10n.t(L10n.Key.USB_DENIED_LOG)); refreshButtons(); }
            } else if (UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(intent.getAction())) {
                captureUsb("attached");
                if (!busy && !waitingPermission && device != null && device.getVendorId() == 0x05ac)
                    log(L10n.t(L10n.Key.APPLE_ATTACHED));
            } else if (UsbManager.ACTION_USB_DEVICE_DETACHED.equals(intent.getAction())) {
                captureUsb("detached");
                if (device != null && activeDevice != null && activeDevice.getDeviceId() == device.getDeviceId()) {
                    activeDevice = null; waitingPermission = false; connectionVerified = false;
                    if (!installing) cancelled = true;
                    if (engine != null) engine.close();
                    setDevice(L10n.Key.DISCONNECTED);
                    log(L10n.t(L10n.Key.USB_DETACHED)); refreshButtons();
                }
            }
        }
    };
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        L10n.setLanguage(L10n.resolve(getSharedPreferences("ui", 0).getString("language", null),
            getResources().getConfiguration().getLocales().get(0)));
        usb = (UsbManager)getSystemService(USB_SERVICE);
        getWindow().setStatusBarColor(Color.rgb(245,247,252));
        getWindow().setNavigationBarColor(Color.rgb(245,247,252));
        if (Build.VERSION.SDK_INT >= 30) {
            getWindow().setDecorFitsSystemWindows(false);
            getWindow().getDecorView();
            WindowInsetsController bars = getWindow().getInsetsController();
            if (bars != null) bars.setSystemBarsAppearance(
                WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
                WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);
        } else {
            getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        }
        buildUi();
        IntentFilter filter = new IntentFilter(USB_PERMISSION);
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        filter.addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
        else registerReceiver(receiver, filter);
        // IPA cache is disposable, never part of backups.
        File[] stale = getCacheDir().listFiles((dir, name) -> name.startsWith("selected-") && name.endsWith(".ipa"));
        if (stale != null) for (File f : stale) f.delete();
        log("IPA USB 0.7.0-beta.3 • Android " + Build.VERSION.RELEASE + " • " + Build.MANUFACTURER + " " + Build.MODEL);
        refreshButtons();
    }
    private int dp(int value) { return (int)(value * getResources().getDisplayMetrics().density + 0.5f); }
    private TextView text(String value, int size, int color) {
        TextView t = new TextView(this); t.setText(value); t.setTextSize(size); t.setTextColor(color);
        t.setPadding(0, dp(4), 0, dp(4)); return t;
    }
    private Button button(String value, LinearLayout parent) {
        Button b = new Button(this); b.setText(value); b.setAllCaps(false); b.setTextSize(15);
        parent.addView(b, new LinearLayout.LayoutParams(0, dp(52), 1)); return b;
    }
    private LinearLayout row(LinearLayout root) {
        LinearLayout row = new LinearLayout(this); row.setOrientation(LinearLayout.HORIZONTAL);
        root.addView(row, new LinearLayout.LayoutParams(-1, -2)); return row;
    }
    private void buildUi() {
        LinearLayout root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(18), dp(14), dp(18), dp(12)); root.setBackgroundColor(Color.rgb(245,247,252));
        setContentView(root);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            int left, top, right, bottom;
            if (Build.VERSION.SDK_INT >= 30) {
                Insets safe = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                left = safe.left; top = safe.top; right = safe.right; bottom = safe.bottom;
            } else {
                left = insets.getSystemWindowInsetLeft(); top = insets.getSystemWindowInsetTop();
                right = insets.getSystemWindowInsetRight(); bottom = insets.getSystemWindowInsetBottom();
            }
            view.setPadding(dp(18) + left, dp(14) + top, dp(18) + right, dp(12) + bottom);
            return insets;
        });
        root.requestApplyInsets();
        LinearLayout top = row(root);
        heading = text(L10n.t(L10n.Key.TITLE), 28, Color.rgb(20,40,70)); heading.setTypeface(null, Typeface.BOLD);
        heading.setMaxLines(1); heading.setAutoSizeTextTypeUniformWithConfiguration(18, 28, 1, android.util.TypedValue.COMPLEX_UNIT_SP);
        top.addView(heading, new LinearLayout.LayoutParams(0, dp(48), 1));
        language = new Spinner(this);
        ArrayAdapter<String> languages = new ArrayAdapter<String>(this, android.R.layout.simple_spinner_item, new String[]{"RU", "EN"}) {
            @Override public View getView(int position, View convertView, ViewGroup parent) {
                TextView label = (TextView)super.getView(position, convertView, parent);
                label.setTextSize(14); label.setSingleLine(true); label.setEllipsize(null);
                label.setPadding(dp(8), 0, dp(4), 0); label.setGravity(Gravity.CENTER_VERTICAL);
                return label;
            }
        };
        languages.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        language.setAdapter(languages); language.setSelection("ru".equals(L10n.language()) ? 0 : 1);
        top.addView(language, new LinearLayout.LayoutParams(dp(96), dp(48)));
        fileLabel = text(L10n.t(L10n.Key.IPA_NOT_SELECTED), 15, Color.DKGRAY); fileLabel.setMaxLines(2); root.addView(fileLabel);
        LinearLayout choose = row(root); pick = button(L10n.t(L10n.Key.SELECT_IPA), choose); connect = button(L10n.t(L10n.Key.CONNECT), choose);
        deviceLabel = text(L10n.t(L10n.Key.DISCONNECTED), 16, Color.rgb(20,40,70)); root.addView(deviceLabel);
        LinearLayout actions = row(root); install = button(L10n.t(L10n.Key.INSTALL), actions); stop = button(L10n.t(L10n.Key.STOP), actions);
        int[][] buttonStates = new int[][] { new int[] { -android.R.attr.state_enabled }, new int[0] };
        install.setBackgroundTintList(new android.content.res.ColorStateList(buttonStates,
            new int[] { Color.rgb(222,225,232), Color.rgb(40,90,225) }));
        install.setTextColor(new android.content.res.ColorStateList(buttonStates,
            new int[] { Color.rgb(135,140,150), Color.WHITE }));
        status = text(L10n.t(L10n.Key.READY), 15, Color.DKGRAY); root.addView(status);
        progress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal); progress.setMax(100); root.addView(progress);
        logScroll = new ScrollView(this); logScroll.setFillViewport(true); logScroll.setBackgroundColor(Color.rgb(20,30,48));
        logView = text("", 13, Color.rgb(220,230,245)); logView.setTypeface(Typeface.MONOSPACE); logView.setTextIsSelectable(true); logView.setPadding(dp(10), dp(8), dp(10), dp(8));
        logScroll.addView(logView); root.addView(logScroll, new LinearLayout.LayoutParams(-1, 0, 1));
        LinearLayout bottom = row(root); save = button(L10n.t(L10n.Key.SAVE_LOG), bottom);
        pick.setOnClickListener(v -> {
            Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(Intent.CATEGORY_OPENABLE);
            startActivityForResult(i, PICK_IPA);
        });
        connect.setOnClickListener(v -> requestConnection());
        install.setOnClickListener(v -> {
            if (ipa == null || activeDevice == null || !connectionVerified) return;
            runConnection(true);
        });
        stop.setOnClickListener(v -> {
            if (installing) return;
            cancelled = true;
            if (engine != null) { connectionVerified = false; engine.close(); }
            setStatus(L10n.Key.STOPPING); stop.setEnabled(false);
        });
        save.setOnClickListener(v -> startActivityForResult(new Intent(Intent.ACTION_CREATE_DOCUMENT).setType("text/plain")
            .addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_TITLE, "IPA-USB-log.txt"), SAVE_LOG));
        language.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            public void onNothingSelected(AdapterView<?> parent) {}
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                String selected = position == 0 ? "ru" : "en";
                if (selected.equals(L10n.language())) return;
                if (busy || waitingPermission) { language.setSelection("ru".equals(L10n.language()) ? 0 : 1); return; }
                L10n.setLanguage(selected);
                getSharedPreferences("ui", 0).edit().putString("language", selected).apply();
                // Update views in place: do not recreate the activity, IPA cache or paired USB session.
                applyLanguage();
            }
        });
        applyLanguage();
    }
    private void setStatus(L10n.Key key) { statusKey = key; status.setText(L10n.t(key)); }
    private void setDevice(L10n.Key key) { deviceKey = key; deviceLabel.setText(L10n.t(key)); }
    private void applyLanguage() {
        setTitle(L10n.t(L10n.Key.TITLE)); heading.setText(L10n.t(L10n.Key.TITLE));
        language.setContentDescription(L10n.t(L10n.Key.LANGUAGE));
        pick.setText(L10n.t(L10n.Key.SELECT_IPA)); connect.setText(L10n.t(L10n.Key.CONNECT));
        install.setText(L10n.t(L10n.Key.INSTALL)); stop.setText(L10n.t(L10n.Key.STOP)); save.setText(L10n.t(L10n.Key.SAVE_LOG));
        fileLabel.setText(ipa == null ? L10n.t(L10n.Key.IPA_NOT_SELECTED) : ipa.title + " " + ipa.version);
        deviceLabel.setText(deviceKey == null ? deviceInfo : L10n.t(deviceKey));
        if (statusKey != null) status.setText(L10n.t(statusKey));
    }
    private void refreshButtons() {
        pick.setEnabled(!busy && !waitingPermission); connect.setEnabled(!busy && !waitingPermission);
        install.setEnabled(!busy && !waitingPermission && connectionVerified && ipa != null && activeDevice != null && usb.hasPermission(activeDevice));
        stop.setEnabled(busy && !installing && !cancelled); save.setEnabled(!busy);
        language.setEnabled(!busy && !waitingPermission);
    }
    private void requestConnection() {
        if (connectionVerified && activeDevice != null && engine != null) {
            for (UsbDevice d : captureUsb("connected-check")) {
                if (d.getDeviceId() == activeDevice.getDeviceId() && usb.hasPermission(d)) {
                    setStatus(L10n.Key.CONNECTED); return;
                }
            }
        }
        connectionVerified = false; activeDevice = null;
        setDevice(L10n.Key.DISCONNECTED);
        List<UsbDevice> devices = new ArrayList<>();
        UsbDiscovery discovery = new UsbDiscovery();
        for (UsbDevice d : captureUsb("connect")) {
            boolean phone = UsbWire.isPhone(d);
            discovery.add(d.getVendorId(), phone);
            if (phone) devices.add(d);
        }
        switch (discovery.state()) {
            case EMPTY:
                setStatus(L10n.Key.NO_USB);
                log(L10n.t(L10n.Key.NO_USB_HELP));
                refreshButtons(); return;
            case OTHER:
                setStatus(L10n.Key.NO_IPHONE);
                log(L10n.t(L10n.Key.NO_APPLE_HELP));
                refreshButtons(); return;
            case APPLE_NO_MUX:
                setDevice(L10n.Key.APPLE_FOUND);
                setStatus(L10n.Key.NO_INTERFACE);
                log(L10n.t(L10n.Key.NO_INTERFACE_HELP));
                refreshButtons(); return;
            case MULTIPLE:
                setStatus(L10n.Key.MULTIPLE_APPLE);
                log(L10n.t(L10n.Key.ONE_IPHONE)); refreshButtons(); return;
            default: break;
        }
        activeDevice = devices.get(0);
        if (usb.hasPermission(activeDevice)) runConnection(false);
        else {
            waitingPermission = true; setStatus(L10n.Key.USB_ALLOW); refreshButtons();
            int flags = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 31 ? PendingIntent.FLAG_MUTABLE : 0);
            // Mutable is required so UsbManager can append the result and device extras.
            PendingIntent pending = PendingIntent.getBroadcast(this, 0, new Intent(USB_PERMISSION).setPackage(getPackageName()), flags);
            try { usb.requestPermission(activeDevice, pending); }
            catch (RuntimeException e) { waitingPermission = false; failure(e); refreshButtons(); }
        }
    }
    // Capture only USB topology and interface types, never serial numbers, UDID or pair data.
    // Technical details are exported on demand rather than filling the main screen.
    private List<UsbDevice> captureUsb(String event) {
        List<UsbDevice> devices = new ArrayList<>(usb.getDeviceList().values());
        devices.sort(Comparator.comparingInt(UsbDevice::getDeviceId));
        StringBuilder s = new StringBuilder();
        s.append('[').append(new SimpleDateFormat("HH:mm:ss", Locale.ROOT).format(new Date()))
            .append("] ").append(event).append(" hostFeature=")
            .append(getPackageManager().hasSystemFeature("android.hardware.usb.host"))
            .append(" devices=").append(devices.size()).append('\n');
        try {
            Intent state = registerReceiver(null, new IntentFilter("android.hardware.usb.action.USB_STATE"));
            if (state != null) {
                s.append("usbState:");
                for (String key : new String[] { "connected", "configured", "host_connected", "mtp", "ptp", "adb" })
                    if (state.hasExtra(key)) s.append(' ').append(key).append('=').append(state.getBooleanExtra(key, false));
                s.append('\n');
            }
        } catch (RuntimeException e) { s.append("usbState unavailable\n"); }
        for (UsbDevice d : devices) {
            s.append(String.format(Locale.ROOT, "device vid=%04x pid=%04x class=%d/%d/%d permission=%s configs=%d\n",
                d.getVendorId(), d.getProductId(), d.getDeviceClass(), d.getDeviceSubclass(),
                d.getDeviceProtocol(), usb.hasPermission(d), d.getConfigurationCount()));
            for (int c = 0; c < d.getConfigurationCount(); c++) {
                UsbConfiguration config = d.getConfiguration(c);
                s.append(" config=").append(config.getId()).append(" interfaces=").append(config.getInterfaceCount()).append('\n');
                for (int n = 0; n < config.getInterfaceCount(); n++) {
                    UsbInterface i = config.getInterface(n);
                    s.append("  interface=").append(i.getId()).append(" alt=").append(i.getAlternateSetting())
                        .append(" class=").append(i.getInterfaceClass()).append('/').append(i.getInterfaceSubclass())
                        .append('/').append(i.getInterfaceProtocol()).append(" mux=").append(UsbWire.isMux(i)).append('\n');
                    for (int e = 0; e < i.getEndpointCount(); e++) {
                        UsbEndpoint ep = i.getEndpoint(e);
                        s.append("   endpoint=").append(ep.getAddress()).append(" type=").append(ep.getType())
                            .append(" direction=").append(ep.getDirection() == UsbConstants.USB_DIR_IN ? "in" : "out")
                            .append(" packet=").append(ep.getMaxPacketSize()).append('\n');
                    }
                }
            }
        }
        usbJournal.append(s);
        if (usbJournal.length() > 60000) usbJournal.delete(0, usbJournal.indexOf("\n", usbJournal.length() - 45000) + 1);
        return devices;
    }
    @Override protected void onResume() {
        super.onResume();
        List<UsbDevice> devices = captureUsb("resume");
        if (activeDevice != null) {
            boolean present = false;
            for (UsbDevice d : devices) if (d.getDeviceId() == activeDevice.getDeviceId()) present = true;
            if (!present) {
                activeDevice = null; connectionVerified = false; waitingPermission = false;
                if (!installing) cancelled = true;
                if (engine != null) engine.close();
                setDevice(L10n.Key.DISCONNECTED);
            }
        }
        refreshButtons();
    }
    private void begin() {
        busy = true; cancelled = false; installing = false; progress.setIndeterminate(true);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); refreshButtons();
    }
    private void end() {
        if (destroyed) return;
        busy = false; installing = false; progress.setIndeterminate(false);
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); refreshButtons();
    }
    private void runConnection(boolean shouldInstall) {
        UsbDevice device = activeDevice;
        if (shouldInstall && (!connectionVerified || engine == null)) { log(L10n.t(L10n.Key.CONNECT_FIRST)); return; }
        connectionVerified = false;
        if (device == null || !usb.hasPermission(device)) { log(L10n.t(L10n.Key.CONNECT_FIRST)); refreshButtons(); return; }
        begin(); setStatus(shouldInstall ? L10n.Key.PREPARING : L10n.Key.CONNECTING);
        task = worker.submit(() -> {
            boolean success = false;
            try {
                if (!shouldInstall) {
                    if (engine != null) engine.close();
                    engine = null;
                    UsbWire wire = new UsbWire(usb, device);
                    engine = new Installer(getApplicationContext(), wire, this);
                }
                if (cancelled) throw new IOException(L10n.t(L10n.Key.CANCELLED));
                if (shouldInstall) engine.install(ipa); else engine.connect();
                success = true;
                ui(() -> {
                    if (cancelled || activeDevice == null || activeDevice.getDeviceId() != device.getDeviceId()) return;
                    connectionVerified = true;
                    setStatus(shouldInstall ? L10n.Key.INSTALLED : L10n.Key.CONNECTED);
                    progress.setProgress(shouldInstall ? 100 : 0);
                });
            } catch (Exception e) { failure(e); }
            finally {
                // Keep USB mux, lockdown and the trusted session for installation.
                // Reopening and renegotiating after a successful probe left replies queued.
                if (!success || cancelled || destroyed) { if (engine != null) engine.close(); engine = null; }
                ui(this::end);
            }
        });
    }
    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (result != RESULT_OK || data == null || data.getData() == null) return;
        Uri uri = data.getData();
        if (request == SAVE_LOG) {
            try (OutputStream out = getContentResolver().openOutputStream(uri, "wt")) {
                if (out == null) throw new IOException(L10n.t(L10n.Key.OPEN_FILE_FAILED));
                captureUsb("export");
                out.write((journal.toString() + "\n--- USB diagnostics (IPA USB 0.7.0-beta.3) ---\n" + usbJournal).getBytes(StandardCharsets.UTF_8));
                Toast.makeText(this, L10n.t(L10n.Key.LOG_SAVED), Toast.LENGTH_SHORT).show();
            } catch (Exception e) { failure(e); }
        } else if (request == PICK_IPA) {
            // A failed new selection must not silently leave the previous IPA installable.
            if (ipa != null) ipa.file.delete();
            ipa = null; fileLabel.setText(L10n.t(L10n.Key.IPA_NOT_SELECTED));
            begin(); setStatus(L10n.Key.CHECKING_IPA);
            task = worker.submit(() -> {
                File cache = new File(getCacheDir(), "selected-" + UUID.randomUUID() + ".ipa");
                try {
                    String name = L10n.t(L10n.Key.DEFAULT_FILE);
                    try (Cursor c = getContentResolver().query(uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
                        if (c != null && c.moveToFirst()) name = c.getString(0);
                    }
                    log(L10n.t(L10n.Key.FILE_SELECTED, name));
                    try (InputStream in = getContentResolver().openInputStream(uri); OutputStream out = new FileOutputStream(cache)) {
                        if (in == null) throw new IOException(L10n.t(L10n.Key.IPA_READ_FAILED));
                        byte[] chunk = new byte[65536]; int n;
                        while ((n = in.read(chunk)) != -1) {
                            if (cancelled || Thread.currentThread().isInterrupted()) throw new IOException(L10n.t(L10n.Key.CANCELLED));
                            out.write(chunk, 0, n);
                        }
                    }
                    Ipa selected = Ipa.open(cache);
                    if (cancelled || Thread.currentThread().isInterrupted() || destroyed) throw new IOException(L10n.t(L10n.Key.CANCELLED));
                    ui(() -> {
                        ipa = selected;
                        fileLabel.setText(selected.title + " " + selected.version);
                        setStatus(L10n.Key.IPA_SELECTED);
                    });
                } catch (Exception e) {
                    cache.delete(); failure(e);
                    if (e.getCause() != null) diagnostic("IPA read cause=" + e.getCause().getClass().getSimpleName());
                }
                finally { ui(this::end); }
            });
        }
    }
    private void ui(Runnable action) { if (!destroyed) runOnUiThread(() -> { if (!destroyed) action.run(); }); }
    public void diagnostic(String message) {
        ui(() -> {
            usbJournal.append('[').append(new SimpleDateFormat("HH:mm:ss", Locale.ROOT).format(new Date()))
                .append("] ").append(message).append('\n');
            if (usbJournal.length() > 60000) usbJournal.delete(0, usbJournal.indexOf("\n", usbJournal.length() - 45000) + 1);
        });
    }
    public void log(String message) {
        ui(() -> {
            String time = new SimpleDateFormat("HH:mm:ss", Locale.ROOT).format(new Date());
            String clean = message.replace('\r', ' ').replace('\n', ' ');
            if (clean.length() > 1200) clean = clean.substring(0,1200);
            journal.append('[').append(time).append("] ").append(clean).append('\n');
            if (journal.length() > 40000) journal.delete(0, journal.indexOf("\n", journal.length() - 30000) + 1);
            logView.setText(journal.toString()); logScroll.post(() -> logScroll.fullScroll(View.FOCUS_DOWN));
        });
    }
    public void device(String description) { ui(() -> { deviceKey = null; deviceInfo = description; deviceLabel.setText(description); }); }
    private int lastProgress = -2; private String lastStage = "";
    public void progress(String stage, int value) {
        if (value == lastProgress && stage.equals(lastStage)) return;
        lastProgress = value; lastStage = stage;
        ui(() -> { statusKey = null; status.setText(stage + (value >= 0 ? " " + value + "%" : "…")); progress.setIndeterminate(value < 0); if (value >= 0) progress.setProgress(value); });
    }
    public void installing() { installing = true; ui(this::refreshButtons); }
    private void failure(Exception e) {
        String message = e.getMessage(); if (message == null || message.isEmpty()) message = e.getClass().getSimpleName();
        if (cancelled || e instanceof InterruptedException) message = L10n.t(L10n.Key.CANCELLED);
        if (e instanceof Installer.DeviceError) {
            String code = ((Installer.DeviceError)e).code;
            if (code.equals("UserDeniedPairing")) message = L10n.t(L10n.Key.TRUST_DENIED);
            else if (code.equals("PasswordProtected")) message = L10n.t(L10n.Key.UNLOCK_RETRY);
            else message = "iPhone: " + code;
        }
        log(message);
        ui(() -> setStatus(cancelled ? L10n.Key.STOPPED : L10n.Key.FAILED));
    }
    @Override public void onBackPressed() {
        if (busy) { Toast.makeText(this, L10n.t(L10n.Key.WAIT_OR_STOP), Toast.LENGTH_SHORT).show(); return; }
        super.onBackPressed();
    }
    @Override protected void onDestroy() {
        destroyed = true; cancelled = true;
        if (engine != null) engine.close(); if (task != null) task.cancel(true); worker.shutdownNow();
        unregisterReceiver(receiver); if (ipa != null) ipa.file.delete();
        super.onDestroy();
    }
}
