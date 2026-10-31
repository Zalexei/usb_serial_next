// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
package io.github.zalexei.usb_serial_next

import android.hardware.usb.UsbDevice
import io.github.zalexei.usb_serial_next.usbserial.driver.CdcAcmSerialDriver
import io.github.zalexei.usb_serial_next.usbserial.driver.Ch34xSerialDriver
import io.github.zalexei.usb_serial_next.usbserial.driver.ChromeCcdSerialDriver
import io.github.zalexei.usb_serial_next.usbserial.driver.Cp21xxSerialDriver
import io.github.zalexei.usb_serial_next.usbserial.driver.FtdiSerialDriver
import io.github.zalexei.usb_serial_next.usbserial.driver.GsmModemSerialDriver
import io.github.zalexei.usb_serial_next.usbserial.driver.ProlificSerialDriver
import io.github.zalexei.usb_serial_next.usbserial.driver.UsbSerialDriver
import io.github.zalexei.usb_serial_next.usbserial.driver.UsbSerialProber

internal object Drivers {
    /**
     * The driver for [device]: [forced] if given, otherwise the one
     * usb-serial-for-android finds by VID/PID or by CDC-ACM interfaces.
     */
    fun find(device: UsbDevice, forced: NativeDriver? = null): UsbSerialDriver? =
        if (forced != null) create(forced, device) else UsbSerialProber.getDefaultProber().probeDevice(device)

    fun typeOf(driver: UsbSerialDriver): NativeDriver? = when (driver) {
        is CdcAcmSerialDriver -> NativeDriver.CDC_ACM
        is FtdiSerialDriver -> NativeDriver.FTDI
        is Cp21xxSerialDriver -> NativeDriver.CP21XX
        is Ch34xSerialDriver -> NativeDriver.CH34X
        is ProlificSerialDriver -> NativeDriver.PROLIFIC
        is GsmModemSerialDriver -> NativeDriver.GSM_MODEM
        is ChromeCcdSerialDriver -> NativeDriver.CHROME_CCD
        else -> null
    }

    private fun create(type: NativeDriver, device: UsbDevice): UsbSerialDriver = when (type) {
        NativeDriver.CDC_ACM -> CdcAcmSerialDriver(device)
        NativeDriver.FTDI -> FtdiSerialDriver(device)
        NativeDriver.CP21XX -> Cp21xxSerialDriver(device)
        NativeDriver.CH34X -> Ch34xSerialDriver(device)
        NativeDriver.PROLIFIC -> ProlificSerialDriver(device)
        NativeDriver.GSM_MODEM -> GsmModemSerialDriver(device)
        NativeDriver.CHROME_CCD -> ChromeCcdSerialDriver(device)
    }
}
