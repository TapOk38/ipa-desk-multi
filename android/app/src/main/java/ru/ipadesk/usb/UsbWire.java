package ru.ipadesk.usb;

import android.hardware.usb.*;
import java.io.IOException;

final class UsbWire implements PacketIO {
    private final UsbDeviceConnection connection;
    private final UsbInterface intf;
    private final UsbEndpoint in, out;
    private volatile boolean closed;

    static boolean isMux(UsbInterface i) {
        return i.getInterfaceClass() == 255 && i.getInterfaceSubclass() == 254 && i.getInterfaceProtocol() == 2;
    }
    static boolean isPhone(UsbDevice device) {
        if (device.getVendorId() != 0x05ac) return false;
        for (int c = 0; c < device.getConfigurationCount(); c++)
            for (int i = 0; i < device.getConfiguration(c).getInterfaceCount(); i++)
                if (isMux(device.getConfiguration(c).getInterface(i))) return true;
        return false;
    }
    UsbWire(UsbManager manager, UsbDevice device) throws IOException {
        UsbConfiguration chosen = null;
        UsbInterface face = null;
        for (int c = 0; c < device.getConfigurationCount(); c++) {
            UsbConfiguration config = device.getConfiguration(c);
            for (int i = 0; i < config.getInterfaceCount(); i++) {
                if (isMux(config.getInterface(i))) { chosen = config; face = config.getInterface(i); break; }
            }
            if (face != null) break;
        }
        if (face == null) throw new IOException("USB: интерфейс iPhone недоступен. Разблокируйте iPhone и переподключите кабель.");
        connection = manager.openDevice(device);
        if (connection == null) throw new IOException("USB: не удалось открыть устройство.");
        intf = face;
        UsbEndpoint input = null, output = null;
        for (int i = 0; i < intf.getEndpointCount(); i++) {
            UsbEndpoint ep = intf.getEndpoint(i);
            if (ep.getType() == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                if (ep.getDirection() == UsbConstants.USB_DIR_IN) input = ep; else output = ep;
            }
        }
        in = input; out = output;
        try {
            if (in == null || out == null) throw new IOException("USB: отсутствуют каналы передачи.");
            byte[] current = new byte[1];
            int got = connection.controlTransfer(0x80, 8, 0, 0, current, 1, 2000);
            if ((got != 1 || (current[0] & 255) != chosen.getId()) && !connection.setConfiguration(chosen))
                throw new IOException("USB: не удалось выбрать конфигурацию iPhone.");
            if (!connection.claimInterface(intf, true)) throw new IOException("USB: интерфейс занят.");
        } catch (IOException e) { connection.close(); throw e; }
    }
    public int read(byte[] buffer) throws IOException {
        if (closed || Thread.currentThread().isInterrupted()) throw new IOException("Операция остановлена.");
        int count = connection.bulkTransfer(in, buffer, buffer.length, 500);
        if (closed) throw new IOException("USB: соединение закрыто.");
        // Android reports both timeout and disconnect as -1; Mux supplies an overall deadline.
        return Math.max(0, count);
    }
    public void write(byte[] packet) throws IOException {
        if (closed || Thread.currentThread().isInterrupted()) throw new IOException("Операция остановлена.");
        int offset = 0;
        while (offset < packet.length) {
            int n = connection.bulkTransfer(out, packet, offset, Math.min(16384, packet.length - offset), 5000);
            if (n <= 0) throw new IOException("USB: ошибка отправки. Проверьте кабель.");
            offset += n;
        }
        if (packet.length % out.getMaxPacketSize() == 0) {
            if (connection.bulkTransfer(out, new byte[0], 0, 2000) < 0)
                throw new IOException("USB: ошибка завершения пакета.");
        }
    }
    public void close() {
        closed = true;
        connection.close();
    }
}
