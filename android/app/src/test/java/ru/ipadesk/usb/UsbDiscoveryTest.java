package ru.ipadesk.usb;

import org.junit.Test;
import static org.junit.Assert.*;

public class UsbDiscoveryTest {
    @Test public void noEnumerationDiffersFromUnsupportedAppleDevice() {
        UsbDiscovery d = new UsbDiscovery();
        assertEquals(UsbDiscovery.State.EMPTY, d.state());
        d.add(0x05ac, false);
        assertEquals(UsbDiscovery.State.APPLE_NO_MUX, d.state());
    }
    @Test public void nonAppleMuxInterfaceIsNotAnIphone() {
        UsbDiscovery d = new UsbDiscovery();
        d.add(0x1234, true);
        assertEquals(UsbDiscovery.State.OTHER, d.state());
    }
    @Test public void hubAndApplePeripheralDoNotHideSupportedPhone() {
        UsbDiscovery d = new UsbDiscovery();
        d.add(0x1234, false);
        d.add(0x05ac, false);
        d.add(0x05ac, true);
        assertEquals(UsbDiscovery.State.READY, d.state());
    }
    @Test public void twoSupportedDevicesRequireDisambiguation() {
        UsbDiscovery d = new UsbDiscovery();
        d.add(0x05ac, true);
        d.add(0x05ac, true);
        assertEquals(UsbDiscovery.State.MULTIPLE, d.state());
    }
}
