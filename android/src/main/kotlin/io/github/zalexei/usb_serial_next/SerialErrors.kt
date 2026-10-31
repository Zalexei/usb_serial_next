// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
package io.github.zalexei.usb_serial_next

import io.github.zalexei.usb_serial_next.usbserial.driver.SerialTimeoutException
import java.io.IOException

/** Error codes the Dart side turns into SerialError values. */
internal object SerialErrors {
    const val PERMISSION_DENIED = "permission_denied"
    const val DEVICE_NOT_FOUND = "device_not_found"
    const val UNSUPPORTED_DEVICE = "unsupported_device"
    const val DISCONNECTED = "disconnected"
    const val PORT_CLOSED = "port_closed"
    const val BUSY = "busy"
    const val INVALID_ARGUMENT = "invalid_argument"
    const val UNSUPPORTED_OPERATION = "unsupported_operation"
    const val TIMEOUT = "timeout"
    const val IO_ERROR = "io_error"

    fun portClosed(portId: Long) = FlutterError(PORT_CLOSED, "Port $portId is closed")

    fun disconnected() = FlutterError(DISCONNECTED, "The device was unplugged")

    /** Turns what a driver or UsbManager threw into an error Dart understands. */
    fun from(e: Throwable): FlutterError = when (e) {
        is FlutterError -> e
        // Before IOException: it is one.
        is SerialTimeoutException ->
            FlutterError(TIMEOUT, e.message ?: "Write timed out", e.bytesTransferred.toLong())
        is SecurityException -> FlutterError(PERMISSION_DENIED, e.message)
        is UnsupportedOperationException ->
            FlutterError(UNSUPPORTED_OPERATION, e.message ?: "The chip does not support this")
        is IllegalArgumentException -> FlutterError(INVALID_ARGUMENT, e.message)
        is IOException ->
            // usb-serial-for-android says "Could not claim ... interface" when
            // another app or a kernel driver holds the device.
            if (e.message?.contains("claim", ignoreCase = true) == true) {
                FlutterError(BUSY, e.message)
            } else {
                FlutterError(IO_ERROR, e.message ?: e.toString())
            }
        else -> FlutterError(IO_ERROR, e.toString())
    }
}
