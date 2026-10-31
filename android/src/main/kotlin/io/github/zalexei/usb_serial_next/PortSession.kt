// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
package io.github.zalexei.usb_serial_next

import java.io.ByteArrayOutputStream
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * One open port: a thread that reads, a thread that writes in order, and the
 * close that happens once, whoever starts it.
 *
 * Knows nothing about Android, so the tests run it on a fake [SerialIo].
 */
internal class PortSession(
    val id: Long,
    val deviceName: String,
    val portIndex: Int,
    private val io: SerialIo,
    /** Runs a task on the thread that talks to Flutter (the main thread). */
    private val post: (Runnable) -> Unit,
    /** Runs control requests (DTR, RTS, config) off the main thread. */
    private val control: Executor,
    /** Tells a lost device from a failed read. */
    private val isDeviceAttached: () -> Boolean,
    private val listener: Listener,
    private val writer: ExecutorService =
        Executors.newSingleThreadExecutor { Thread(it, "usb_serial_next write $id") },
) {
    interface Listener {
        /** Called on the main thread. */
        fun onData(session: PortSession, data: ByteArray)

        /** Called once, on the main thread, after the last [onData]. */
        fun onClosed(session: PortSession, error: FlutterError?)
    }

    private val closed = AtomicBoolean(false)

    @Volatile
    private var closeReason: FlutterError? = null

    // Data read but not yet sent to Dart. Reads that come while a send is
    // queued join it, so a fast device does not flood the main thread with
    // tiny messages.
    private val pending = ByteArrayOutputStream()
    private var sendQueued = false

    val isClosed: Boolean
        get() = closed.get()

    fun start() {
        Thread(::readLoop, "usb_serial_next read $id").apply { isDaemon = true }.start()
    }

    fun write(data: ByteArray, timeoutMs: Int, callback: (Result<Unit>) -> Unit) {
        try {
            writer.execute {
                val result = runCatching {
                    if (closed.get()) throw closedError()
                    io.write(data, timeoutMs)
                }.mapFailure()
                post { callback(result) }
            }
        } catch (e: RejectedExecutionException) {
            callback(Result.failure(closedError()))
        }
    }

    /** Runs [op] on the control executor and answers on the main thread. */
    fun <T> control(op: (SerialIo) -> T, callback: (Result<T>) -> Unit) {
        control.execute {
            val result = runCatching {
                if (closed.get()) throw closedError()
                op(io)
            }.mapFailure()
            post { callback(result) }
        }
    }

    /**
     * Closes the port; [reason] is null for a requested close. Returns false
     * if it was already closed. Blocks while the driver closes, so call it off
     * the main thread.
     */
    fun close(reason: FlutterError? = null): Boolean {
        if (!closed.compareAndSet(false, true)) return false
        closeReason = reason
        // Writes already queued still run and fail as closed.
        writer.shutdown()
        runCatching { io.close() }
        post {
            sendPending()
            listener.onClosed(this, reason)
        }
        return true
    }

    private fun readLoop() {
        val buffer = ByteArray(maxOf(io.readBufferSize, MIN_READ_BUFFER))
        try {
            while (!closed.get()) {
                val count = io.read(buffer)
                if (count > 0) queue(buffer.copyOf(count))
            }
        } catch (e: Throwable) {
            if (closed.get()) return
            // A read fails a moment before UsbManager drops an unplugged
            // device, so give it that moment before deciding what happened.
            Thread.sleep(DETACH_SETTLE_MS)
            close(if (isDeviceAttached()) SerialErrors.from(e) else SerialErrors.disconnected())
        }
    }

    private fun queue(data: ByteArray) {
        synchronized(pending) {
            pending.write(data)
            if (sendQueued) return
            sendQueued = true
        }
        post { sendPending() }
    }

    private fun sendPending() {
        val data = synchronized(pending) {
            sendQueued = false
            pending.toByteArray().also { pending.reset() }
        }
        if (data.isNotEmpty()) listener.onData(this, data)
    }

    private fun closedError(): FlutterError = closeReason ?: SerialErrors.portClosed(id)

    // After a close, the driver's own complaint ("Connection closed") says
    // less than why the port was closed.
    private fun <T> Result<T>.mapFailure(): Result<T> = exceptionOrNull()?.let {
        Result.failure(if (closed.get()) closedError() else SerialErrors.from(it))
    } ?: this

    companion object {
        const val MIN_READ_BUFFER = 64
        const val DETACH_SETTLE_MS = 200L
    }
}
