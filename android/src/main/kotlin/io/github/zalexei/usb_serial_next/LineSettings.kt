// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
package io.github.zalexei.usb_serial_next

import io.github.zalexei.usb_serial_next.usbserial.driver.UsbSerialPort

/** A port configuration in the terms of usb-serial-for-android. */
internal data class LineSettings(
    val baudRate: Int,
    val dataBits: Int,
    val stopBits: Int,
    val parity: Int,
    val flowControl: UsbSerialPort.FlowControl,
    val dtr: Boolean?,
    val rts: Boolean?,
)

/** Checks the values Dart sent and converts them. */
internal fun NativePortConfig.toLineSettings(): LineSettings {
    if (baudRate <= 0 || baudRate > Int.MAX_VALUE) {
        throw FlutterError(SerialErrors.INVALID_ARGUMENT, "Baud rate must be positive, got $baudRate")
    }
    if (dataBits !in 5L..8L) {
        throw FlutterError(SerialErrors.INVALID_ARGUMENT, "Data bits must be 5 to 8, got $dataBits")
    }
    return LineSettings(
        baudRate = baudRate.toInt(),
        dataBits = dataBits.toInt(),
        stopBits = when (stopBits) {
            NativeStopBits.ONE -> UsbSerialPort.STOPBITS_1
            NativeStopBits.ONE_POINT_FIVE -> UsbSerialPort.STOPBITS_1_5
            NativeStopBits.TWO -> UsbSerialPort.STOPBITS_2
        },
        parity = when (parity) {
            NativeParity.NONE -> UsbSerialPort.PARITY_NONE
            NativeParity.ODD -> UsbSerialPort.PARITY_ODD
            NativeParity.EVEN -> UsbSerialPort.PARITY_EVEN
            NativeParity.MARK -> UsbSerialPort.PARITY_MARK
            NativeParity.SPACE -> UsbSerialPort.PARITY_SPACE
        },
        flowControl = when (flowControl) {
            NativeFlowControl.NONE -> UsbSerialPort.FlowControl.NONE
            NativeFlowControl.RTS_CTS -> UsbSerialPort.FlowControl.RTS_CTS
            NativeFlowControl.DTR_DSR -> UsbSerialPort.FlowControl.DTR_DSR
            NativeFlowControl.XON_XOFF -> UsbSerialPort.FlowControl.XON_XOFF
            NativeFlowControl.XON_XOFF_INLINE -> UsbSerialPort.FlowControl.XON_XOFF_INLINE
        },
        dtr = dtr,
        rts = rts,
    )
}
