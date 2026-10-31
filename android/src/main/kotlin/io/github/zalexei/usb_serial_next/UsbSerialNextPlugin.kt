// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
package io.github.zalexei.usb_serial_next

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class UsbSerialNextPlugin : FlutterPlugin, ActivityAware, UsbSerialHostApi {
    private var usbManager: UsbManager? = null
    private var context: Context? = null
    private var flutterApi: UsbSerialFlutterApi? = null
    private var permissions: UsbPermissions? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Opens, closes and control requests, one at a time: a port being closed
    // is released before the next open of the same device starts.
    private lateinit var background: ExecutorService

    // Main thread only.
    private val sessions = mutableMapOf<Long, PortSession>()
    private val opening = mutableSetOf<String>()
    private var nextPortId = 1L

    private var activityBinding: ActivityPluginBinding? = null
    private var launchDevice: UsbDevice? = null
    private val newIntentListener = PluginRegistry.NewIntentListener { intent ->
        rememberLaunchDevice(intent)
        false
    }

    private val hotplugReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val device = intent.usbDevice() ?: return
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> flutterApi?.onDeviceAttached(describe(device)) {}
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    permissions?.cancel(device.deviceName)
                    sessions.values.filter { it.deviceName == device.deviceName }
                        .forEach { closeSession(it, SerialErrors.disconnected()) }
                    flutterApi?.onDeviceDetached(describe(device)) {}
                }
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        this.context = context
        this.usbManager = usbManager
        flutterApi = UsbSerialFlutterApi(binding.binaryMessenger)
        background = Executors.newSingleThreadExecutor { Thread(it, "usb_serial_next") }
        permissions = UsbPermissions(context, usbManager).also { it.register() }
        context.registerReceiverCompat(
            hotplugReceiver,
            IntentFilter().apply {
                addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
                addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            },
        )
        UsbSerialHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        UsbSerialHostApi.setUp(binding.binaryMessenger, null)
        flutterApi = null
        context?.unregisterReceiver(hotplugReceiver)
        permissions?.unregister()
        permissions = null
        closeAllSessions()
        background.shutdown()
        usbManager = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(newIntentListener)
        rememberLaunchDevice(binding.activity.intent)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(newIntentListener)
        activityBinding = null
    }

    private fun rememberLaunchDevice(intent: Intent?) {
        if (intent?.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) {
            intent.usbDevice()?.let { launchDevice = it }
        }
    }

    // UsbSerialHostApi

    override fun reset() {
        closeAllSessions()
    }

    override fun listDevices(): List<NativeUsbDevice> =
        requireUsbManager().deviceList.values.sortedBy { it.deviceId }.map(::describe)

    override fun hasPermission(deviceName: String): Boolean {
        val manager = requireUsbManager()
        val device = manager.deviceList[deviceName] ?: return false
        return manager.hasPermission(device)
    }

    override fun requestPermission(deviceName: String, callback: (Result<Boolean>) -> Unit) = guarded(callback) {
        val device = requireUsbManager().deviceList[deviceName]
        val permissions = permissions
        if (device == null || permissions == null) {
            callback(Result.failure(deviceNotFound(deviceName)))
            return@guarded
        }
        permissions.request(device) { callback(Result.success(it)) }
    }

    override fun launchDevice(): NativeUsbDevice? {
        val device = launchDevice ?: return null
        // Still plugged in?
        return requireUsbManager().deviceList[device.deviceName]?.let(::describe)
    }

    override fun open(request: NativeOpenRequest, callback: (Result<Long>) -> Unit) = guarded(callback) {
        val manager = requireUsbManager()
        val key = "${request.deviceName}#${request.portIndex}"
        if (key in opening || sessions.values.any { "${it.deviceName}#${it.portIndex}" == key }) {
            callback(
                Result.failure(
                    FlutterError(SerialErrors.BUSY, "Port ${request.portIndex} of ${request.deviceName} is already open"),
                ),
            )
            return@guarded
        }
        opening += key
        background.execute {
            val result = runCatching { openPort(manager, request) }
            mainHandler.post {
                opening -= key
                result.onFailure { callback(Result.failure(SerialErrors.from(it))) }
                result.onSuccess { io -> startSession(manager, request, io, callback) }
            }
        }
    }

    override fun write(portId: Long, data: ByteArray, timeoutMs: Long, callback: (Result<Unit>) -> Unit) =
        guarded(callback) {
            val session = sessions[portId] ?: return@guarded callback(Result.failure(SerialErrors.portClosed(portId)))
            session.write(data, timeoutMs.coerceIn(0, Int.MAX_VALUE.toLong()).toInt(), callback)
        }

    override fun setConfig(portId: Long, config: NativePortConfig, callback: (Result<Unit>) -> Unit) =
        control(portId, callback) { it.configure(config.toLineSettings()) }

    override fun setDtr(portId: Long, value: Boolean, callback: (Result<Unit>) -> Unit) =
        control(portId, callback) { it.setDtr(value) }

    override fun setRts(portId: Long, value: Boolean, callback: (Result<Unit>) -> Unit) =
        control(portId, callback) { it.setRts(value) }

    override fun getControlLines(portId: Long, callback: (Result<NativeControlLines>) -> Unit) =
        control(portId, callback) { it.controlLines() }

    override fun setBreak(portId: Long, value: Boolean, callback: (Result<Unit>) -> Unit) =
        control(portId, callback) { it.setBreak(value) }

    override fun purge(portId: Long, output: Boolean, input: Boolean, callback: (Result<Unit>) -> Unit) =
        control(portId, callback) { it.purge(output, input) }

    override fun close(portId: Long, callback: (Result<Unit>) -> Unit) = guarded(callback) {
        val session = sessions[portId] ?: return@guarded callback(Result.success(Unit))
        closeSession(session, null) { callback(Result.success(Unit)) }
    }

    private val sessionListener = object : PortSession.Listener {
        override fun onData(session: PortSession, data: ByteArray) {
            flutterApi?.onData(session.id, data) {}
        }

        override fun onClosed(session: PortSession, error: FlutterError?) {
            sessions.remove(session.id)
            flutterApi?.onPortClosed(session.id, error?.code, error?.message) {}
        }
    }

    // Helpers

    private fun openPort(manager: UsbManager, request: NativeOpenRequest): SerialIo {
        val settings = request.config.toLineSettings()
        val device = manager.deviceList[request.deviceName] ?: throw deviceNotFound(request.deviceName)
        if (!manager.hasPermission(device)) {
            throw FlutterError(
                SerialErrors.PERMISSION_DENIED,
                "No permission for ${request.deviceName}; call requestPermission first",
            )
        }
        val driver = Drivers.find(device, request.driver)
            ?: throw FlutterError(
                SerialErrors.UNSUPPORTED_DEVICE,
                "No serial driver for %04x:%04x; pass a driver to open() if you know the chip"
                    .format(device.vendorId, device.productId),
            )
        val port = driver.ports.getOrNull(request.portIndex.toInt())
            ?: throw FlutterError(
                SerialErrors.INVALID_ARGUMENT,
                "Port ${request.portIndex} does not exist; the device has ${driver.ports.size}",
            )
        val connection = manager.openDevice(device)
            ?: throw FlutterError(SerialErrors.IO_ERROR, "UsbManager.openDevice failed for ${request.deviceName}")
        try {
            port.open(connection)
        } catch (e: Throwable) {
            runCatching { connection.close() }
            throw e
        }
        val io = UsbSerialIo(port)
        try {
            io.configure(settings)
        } catch (e: Throwable) {
            runCatching { io.close() }
            throw e
        }
        return io
    }

    private fun startSession(
        manager: UsbManager,
        request: NativeOpenRequest,
        io: SerialIo,
        callback: (Result<Long>) -> Unit,
    ) {
        if (flutterApi == null) {
            // The engine went away while the port was opening.
            background.execute { runCatching { io.close() } }
            return
        }
        val session = PortSession(
            id = nextPortId++,
            deviceName = request.deviceName,
            portIndex = request.portIndex.toInt(),
            io = io,
            post = { mainHandler.post(it) },
            control = background,
            isDeviceAttached = { manager.deviceList.containsKey(request.deviceName) },
            listener = sessionListener,
        )
        sessions[session.id] = session
        session.start()
        callback(Result.success(session.id))
    }

    private fun <T> control(portId: Long, callback: (Result<T>) -> Unit, op: (SerialIo) -> T) = guarded(callback) {
        val session = sessions[portId] ?: return@guarded callback(Result.failure(SerialErrors.portClosed(portId)))
        session.control(op, callback)
    }

    /**
     * Pigeon does not catch what an async handler throws before it calls
     * back, and Dart would wait forever; answer with the error instead. Some
     * vendor ROMs throw from UsbManager.requestPermission, for example.
     */
    private inline fun <T> guarded(callback: (Result<T>) -> Unit, body: () -> Unit) {
        try {
            body()
        } catch (e: Throwable) {
            callback(Result.failure(SerialErrors.from(e)))
        }
    }

    /** Forgets the session now and closes it in the background. */
    private fun closeSession(session: PortSession, reason: FlutterError?, done: (() -> Unit)? = null) {
        sessions.remove(session.id)
        background.execute {
            session.close(reason)
            done?.let { mainHandler.post(it) }
        }
    }

    private fun closeAllSessions() {
        sessions.values.toList().forEach { closeSession(it, null) }
    }

    private fun describe(device: UsbDevice): NativeUsbDevice {
        val manager = requireUsbManager()
        val driver = runCatching { Drivers.find(device) }.getOrNull()
        val hasPermission = manager.hasPermission(device)
        return NativeUsbDevice(
            deviceName = device.deviceName,
            deviceId = device.deviceId.toLong(),
            vendorId = device.vendorId.toLong(),
            productId = device.productId.toLong(),
            // Reading these can fail on some devices, and the serial number
            // needs permission on Android 10+.
            manufacturerName = runCatching { device.manufacturerName }.getOrNull(),
            productName = runCatching { device.productName }.getOrNull(),
            serialNumber = if (hasPermission) runCatching { device.serialNumber }.getOrNull() else null,
            driver = driver?.let(Drivers::typeOf),
            portCount = driver?.ports?.size?.toLong() ?: 0,
            hasPermission = hasPermission,
        )
    }

    private fun deviceNotFound(deviceName: String) =
        FlutterError(SerialErrors.DEVICE_NOT_FOUND, "$deviceName is not attached")

    private fun requireUsbManager(): UsbManager =
        usbManager ?: throw FlutterError(SerialErrors.IO_ERROR, "The plugin is not attached to an engine")
}
