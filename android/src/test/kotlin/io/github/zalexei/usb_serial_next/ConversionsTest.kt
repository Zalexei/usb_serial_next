package io.github.zalexei.usb_serial_next

import io.github.zalexei.usb_serial_next.usbserial.driver.SerialTimeoutException
import io.github.zalexei.usb_serial_next.usbserial.driver.UsbSerialPort
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

class ConversionsTest {
    @Test
    fun configMapsToDriverConstants() {
        val settings = NativePortConfig(
            baudRate = 9600,
            dataBits = 7,
            stopBits = NativeStopBits.ONE_POINT_FIVE,
            parity = NativeParity.EVEN,
            flowControl = NativeFlowControl.XON_XOFF,
            dtr = true,
        ).toLineSettings()

        assertEquals(9600, settings.baudRate)
        assertEquals(UsbSerialPort.DATABITS_7, settings.dataBits)
        assertEquals(UsbSerialPort.STOPBITS_1_5, settings.stopBits)
        assertEquals(UsbSerialPort.PARITY_EVEN, settings.parity)
        assertEquals(UsbSerialPort.FlowControl.XON_XOFF, settings.flowControl)
        assertEquals(true, settings.dtr)
        assertNull(settings.rts)
    }

    @Test
    fun everyParityAndStopBitsValueMaps() {
        val parities = NativeParity.values().map {
            NativePortConfig(115200, 8, NativeStopBits.ONE, it, NativeFlowControl.NONE).toLineSettings().parity
        }
        val stopBits = NativeStopBits.values().map {
            NativePortConfig(115200, 8, it, NativeParity.NONE, NativeFlowControl.NONE).toLineSettings().stopBits
        }

        assertEquals(
            listOf(
                UsbSerialPort.PARITY_NONE,
                UsbSerialPort.PARITY_ODD,
                UsbSerialPort.PARITY_EVEN,
                UsbSerialPort.PARITY_MARK,
                UsbSerialPort.PARITY_SPACE,
            ),
            parities,
        )
        assertEquals(listOf(UsbSerialPort.STOPBITS_1, UsbSerialPort.STOPBITS_1_5, UsbSerialPort.STOPBITS_2), stopBits)
    }

    @Test
    fun badConfigIsAnInvalidArgument() {
        for (bad in listOf(config(baudRate = 0), config(baudRate = 1L shl 32), config(dataBits = 9), config(dataBits = 4))) {
            val error = assertFailsWith<FlutterError> { bad.toLineSettings() }
            assertEquals(SerialErrors.INVALID_ARGUMENT, error.code)
        }
    }

    @Test
    fun driverExceptionsMapToCodes() {
        assertEquals(SerialErrors.TIMEOUT, SerialErrors.from(SerialTimeoutException("slow", 3)).code)
        assertEquals(SerialErrors.PERMISSION_DENIED, SerialErrors.from(SecurityException("no")).code)
        assertEquals(SerialErrors.UNSUPPORTED_OPERATION, SerialErrors.from(UnsupportedOperationException()).code)
        assertEquals(SerialErrors.INVALID_ARGUMENT, SerialErrors.from(IllegalArgumentException("bad")).code)
        assertEquals(SerialErrors.BUSY, SerialErrors.from(IOException("Could not claim data interface")).code)
        assertEquals(SerialErrors.IO_ERROR, SerialErrors.from(IOException("Error setting baud rate")).code)
        assertEquals(SerialErrors.IO_ERROR, SerialErrors.from(IllegalStateException("odd")).code)
        val own = FlutterError(SerialErrors.DEVICE_NOT_FOUND, "gone")
        assertEquals(own, SerialErrors.from(own))
    }
}
