// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
package io.github.zalexei.usb_serial_next

import io.github.zalexei.usb_serial_next.usbserial.driver.UsbSerialPort
import io.github.zalexei.usb_serial_next.usbserial.driver.UsbSerialPort.ControlLine

/**
 * What a [PortSession] needs from an open port. The USB implementation is
 * [UsbSerialIo]; tests use a fake, and a Bluetooth transport could be another.
 */
internal interface SerialIo {
    /** Size of the buffer [read] should get. */
    val readBufferSize: Int

    /** Blocks until data arrives. Throws once the port is closed or gone. */
    fun read(buffer: ByteArray): Int

    /** [timeoutMs] 0 waits forever. */
    fun write(data: ByteArray, timeoutMs: Int)

    fun configure(settings: LineSettings)

    fun setDtr(value: Boolean)

    fun setRts(value: Boolean)

    fun controlLines(): NativeControlLines

    fun setBreak(value: Boolean)

    fun purge(output: Boolean, input: Boolean)

    fun close()
}

internal class UsbSerialIo(private val port: UsbSerialPort) : SerialIo {
    override val readBufferSize: Int
        get() = port.readEndpoint.maxPacketSize

    // Timeout 0 reads with a queued UsbRequest, the way usb-serial-for-android
    // recommends for continuous reading; close() cancels it.
    override fun read(buffer: ByteArray): Int = port.read(buffer, 0)

    override fun write(data: ByteArray, timeoutMs: Int) = port.write(data, timeoutMs)

    override fun configure(settings: LineSettings) {
        port.setParameters(settings.baudRate, settings.dataBits, settings.stopBits, settings.parity)
        // Most chips support only NONE; asking for it again would be harmless,
        // but there is nothing to change.
        if (settings.flowControl != port.flowControl) {
            port.setFlowControl(settings.flowControl)
        }
        settings.dtr?.let(port::setDTR)
        settings.rts?.let(port::setRTS)
    }

    override fun setDtr(value: Boolean) {
        port.setDTR(value)
    }

    override fun setRts(value: Boolean) {
        port.setRTS(value)
    }

    override fun controlLines(): NativeControlLines {
        val supported = port.supportedControlLines
        val active = port.controlLines
        fun state(line: ControlLine) = if (line in supported) line in active else null
        return NativeControlLines(
            rts = state(ControlLine.RTS),
            cts = state(ControlLine.CTS),
            dtr = state(ControlLine.DTR),
            dsr = state(ControlLine.DSR),
            cd = state(ControlLine.CD),
            ri = state(ControlLine.RI),
        )
    }

    override fun setBreak(value: Boolean) = port.setBreak(value)

    override fun purge(output: Boolean, input: Boolean) {
        port.purgeHwBuffers(output, input)
    }

    override fun close() {
        if (port.isOpen) port.close()
    }
}
