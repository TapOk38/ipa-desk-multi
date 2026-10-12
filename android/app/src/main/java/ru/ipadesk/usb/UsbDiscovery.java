package ru.ipadesk.usb;

/** Classifies enumeration separately from USB permission and pairing. */
final class UsbDiscovery {
    enum State { EMPTY, OTHER, APPLE_NO_MUX, READY, MULTIPLE }
    private int total, apple, supported;

    void add(int vendor, boolean mux) {
        total++;
        if (vendor == 0x05ac) {
            apple++;
            if (mux) supported++;
        }
    }

    State state() {
        if (supported > 1) return State.MULTIPLE;
        if (supported == 1) return State.READY;
        if (apple > 0) return State.APPLE_NO_MUX;
        return total == 0 ? State.EMPTY : State.OTHER;
    }
}
