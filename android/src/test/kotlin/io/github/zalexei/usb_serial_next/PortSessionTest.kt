package io.github.zalexei.usb_serial_next

import io.github.zalexei.usb_serial_next.usbserial.driver.SerialTimeoutException
import java.io.IOException
import java.util.concurrent.AbstractExecutorService
import java.util.concurrent.Executor
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** A port whose reads the test feeds; close() makes the blocked read fail like the driver does. */
private class FakeSerialIo : SerialIo {
    private val incoming = LinkedBlockingQueue<Any>()
    val written = mutableListOf<Pair<ByteArray, Int>>()
    var writeError: Throwable? = null
    var closeCount = 0
    var dtr: Boolean? = null

    fun feed(vararg bytes: Int) = incoming.put(ByteArray(bytes.size) { bytes[it].toByte() })

    fun fail(error: Throwable) = incoming.put(error)

    override val readBufferSize = 16

    override fun read(buffer: ByteArray): Int {
        when (val next = incoming.take()) {
            is Throwable -> throw next
            is ByteArray -> {
                next.copyInto(buffer)
                return next.size
            }
        }
        error("unreachable")
    }

    override fun write(data: ByteArray, timeoutMs: Int) {
        writeError?.let { throw it }
        written += data to timeoutMs
    }

    override fun configure(settings: LineSettings) {
        if (settings.flowControl != io.github.zalexei.usb_serial_next.usbserial.driver.UsbSerialPort.FlowControl.NONE) {
            throw UnsupportedOperationException("Flow control not supported")
        }
    }

    override fun setDtr(value: Boolean) {
        dtr = value
    }

    override fun setRts(value: Boolean) = Unit

    override fun controlLines() = NativeControlLines(dtr = dtr)

    override fun setBreak(value: Boolean) = Unit

    override fun purge(output: Boolean, input: Boolean) = Unit

    override fun close() {
        closeCount++
        incoming.put(IOException("Connection closed"))
    }
}

/** Collects what the session reports; the "main thread" is a queue the test drains. */
private class Recorder : PortSession.Listener {
    val mainThread = LinkedBlockingQueue<Runnable>()
    val data = mutableListOf<Byte>()
    val chunks = mutableListOf<Int>()
    val closes = mutableListOf<FlutterError?>()

    override fun onData(session: PortSession, data: ByteArray) {
        this.data += data.toList()
        chunks += data.size
    }

    override fun onClosed(session: PortSession, error: FlutterError?) {
        closes += error
    }

    /** Runs main-thread tasks until [done] or a timeout. */
    fun runUntil(done: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 5000
        while (!done()) {
            val left = deadline - System.currentTimeMillis()
            check(left > 0) { "timed out" }
            mainThread.poll(left, TimeUnit.MILLISECONDS)?.run()
        }
    }

    fun drain() {
        while (true) mainThread.poll()?.run() ?: return
    }
}

/** Runs tasks at once, on the caller's thread. */
private class DirectExecutor : AbstractExecutorService() {
    private var shutdown = false

    override fun execute(command: Runnable) {
        if (shutdown) throw java.util.concurrent.RejectedExecutionException()
        command.run()
    }

    override fun shutdown() {
        shutdown = true
    }

    override fun shutdownNow(): MutableList<Runnable> {
        shutdown = true
        return mutableListOf()
    }

    override fun isShutdown() = shutdown

    override fun isTerminated() = shutdown

    override fun awaitTermination(timeout: Long, unit: TimeUnit) = true
}

class PortSessionTest {
    private val io = FakeSerialIo()
    private val recorder = Recorder()
    private var attached = true
    private val session = PortSession(
        id = 7,
        deviceName = "/dev/bus/usb/001/002",
        portIndex = 0,
        io = io,
        post = { recorder.mainThread.put(it) },
        control = Executor { it.run() },
        isDeviceAttached = { attached },
        listener = recorder,
        writer = DirectExecutor(),
    )

    @AfterTest
    fun closeSession() {
        session.close()
    }

    @Test
    fun deliversReadDataInOrder() {
        session.start()
        io.feed(1, 2)
        io.feed(3)

        recorder.runUntil { recorder.data.size == 3 }

        assertEquals(listOf<Byte>(1, 2, 3), recorder.data)
    }

    @Test
    fun joinsReadsThatArriveWhileASendIsQueued() {
        session.start()
        io.feed(1)
        io.feed(2)
        io.feed(3)
        // Let the reader queue all three before the main thread runs.
        Thread.sleep(200)

        recorder.runUntil { recorder.data.size == 3 }

        assertEquals(listOf(3), recorder.chunks)
    }

    @Test
    fun requestedCloseReportsNoErrorOnceAndClosesThePortOnce() {
        session.start()

        assertTrue(session.close())
        assertFalse(session.close())
        recorder.runUntil { recorder.closes.isNotEmpty() }
        Thread.sleep(100)
        recorder.drain()

        assertEquals(listOf<FlutterError?>(null), recorder.closes)
        assertEquals(1, io.closeCount)
        assertTrue(session.isClosed)
    }

    @Test
    fun dataReadBeforeTheCloseArrivesBeforeIt() {
        session.start()
        io.feed(5)
        Thread.sleep(100)

        session.close()
        recorder.runUntil { recorder.closes.isNotEmpty() }

        assertEquals(listOf<Byte>(5), recorder.data)
    }

    @Test
    fun aFailedReadOfAnUnpluggedDeviceIsDisconnected() {
        session.start()
        attached = false

        io.fail(IOException("USB get_status request failed"))
        recorder.runUntil { recorder.closes.isNotEmpty() }

        assertEquals(SerialErrors.DISCONNECTED, recorder.closes.single()?.code)
        assertEquals(1, io.closeCount)
    }

    @Test
    fun aFailedReadOfAPresentDeviceIsAnIoError() {
        session.start()

        io.fail(IOException("Queueing USB request failed"))
        recorder.runUntil { recorder.closes.isNotEmpty() }

        val error = recorder.closes.single()
        assertEquals(SerialErrors.IO_ERROR, error?.code)
        assertEquals("Queueing USB request failed", error?.message)
    }

    @Test
    fun closeWithAReasonReportsIt() {
        session.start()

        session.close(SerialErrors.disconnected())
        recorder.runUntil { recorder.closes.isNotEmpty() }

        assertEquals(SerialErrors.DISCONNECTED, recorder.closes.single()?.code)
    }

    @Test
    fun writesPassDataAndTimeout() {
        var result: Result<Unit>? = null

        session.write(byteArrayOf(0x41), 500) { result = it }
        recorder.drain()

        assertTrue(result!!.isSuccess)
        assertContentEquals(byteArrayOf(0x41), io.written.single().first)
        assertEquals(500, io.written.single().second)
    }

    @Test
    fun writeTimeoutCarriesTheBytesSent() {
        io.writeError = SerialTimeoutException("Error writing 10 bytes", 4)
        var result: Result<Unit>? = null

        session.write(ByteArray(10), 100) { result = it }
        recorder.drain()

        val error = result!!.exceptionOrNull() as FlutterError
        assertEquals(SerialErrors.TIMEOUT, error.code)
        assertEquals(4L, error.details)
    }

    @Test
    fun writeAfterCloseFailsWithTheCloseReason() {
        session.close(SerialErrors.disconnected())
        var result: Result<Unit>? = null

        session.write(byteArrayOf(1), 100) { result = it }
        recorder.drain()

        assertEquals(SerialErrors.DISCONNECTED, (result!!.exceptionOrNull() as FlutterError).code)
        assertTrue(io.written.isEmpty())
    }

    @Test
    fun writeAfterARequestedCloseIsPortClosed() {
        session.close()
        var result: Result<Unit>? = null

        session.write(byteArrayOf(1), 100) { result = it }
        recorder.drain()

        assertEquals(SerialErrors.PORT_CLOSED, (result!!.exceptionOrNull() as FlutterError).code)
    }

    @Test
    fun controlRequestsRunAndReportErrors() {
        var lines: Result<NativeControlLines>? = null
        var config: Result<Unit>? = null

        session.control({ it.setDtr(true) }) {}
        session.control({ it.controlLines() }) { lines = it }
        session.control({ it.configure(config(NativeFlowControl.RTS_CTS).toLineSettings()) }) { config = it }
        recorder.drain()

        assertEquals(true, lines!!.getOrThrow().dtr)
        assertNull(lines!!.getOrThrow().cts)
        assertEquals(
            SerialErrors.UNSUPPORTED_OPERATION,
            (config!!.exceptionOrNull() as FlutterError).code,
        )
    }

    @Test
    fun controlAfterCloseIsPortClosed() {
        session.close()
        var result: Result<Unit>? = null

        session.control({ it.setDtr(true) }) { result = it }
        recorder.drain()

        assertEquals(SerialErrors.PORT_CLOSED, (result!!.exceptionOrNull() as FlutterError).code)
        assertNull(io.dtr)
    }
}

internal fun config(
    flowControl: NativeFlowControl = NativeFlowControl.NONE,
    baudRate: Long = 115200,
    dataBits: Long = 8,
) = NativePortConfig(
    baudRate = baudRate,
    dataBits = dataBits,
    stopBits = NativeStopBits.ONE,
    parity = NativeParity.NONE,
    flowControl = flowControl,
)
