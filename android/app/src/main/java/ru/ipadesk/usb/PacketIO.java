package ru.ipadesk.usb;

import java.io.Closeable;
import java.io.IOException;

/** A USB byte stream; reads may split or join mux packets. No daemon protocol. */
public interface PacketIO extends Closeable {
    int read(byte[] buffer) throws IOException;
    void write(byte[] packet) throws IOException;
}
