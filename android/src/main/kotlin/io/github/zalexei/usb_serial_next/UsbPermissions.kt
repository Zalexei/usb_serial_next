// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
package io.github.zalexei.usb_serial_next

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build

/** Asks the user for access to a device, one system dialog per device. */
internal class UsbPermissions(private val context: Context, private val usbManager: UsbManager) {
    private val action = "${context.packageName}.usb_serial_next.USB_PERMISSION"

    // Callbacks waiting for the answer, by device name. Main thread only.
    private val waiting = mutableMapOf<String, MutableList<(Boolean) -> Unit>>()

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != action) return
            val device = intent.usbDevice() ?: return
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false) ||
                usbManager.hasPermission(device)
            waiting.remove(device.deviceName)?.forEach { it(granted) }
        }
    }

    fun register() {
        // The PendingIntent below is ours, so the answer comes from this app
        // and the receiver need not be exported.
        context.registerReceiverCompat(receiver, IntentFilter(action))
    }

    fun unregister() {
        context.unregisterReceiver(receiver)
        waiting.clear()
    }

    fun request(device: UsbDevice, callback: (Boolean) -> Unit) {
        if (usbManager.hasPermission(device)) {
            callback(true)
            return
        }
        val callbacks = waiting.getOrPut(device.deviceName) { mutableListOf() }
        callbacks += callback
        // The dialog is already up for this device.
        if (callbacks.size > 1) return

        // The system adds EXTRA_DEVICE and EXTRA_PERMISSION_GRANTED to this
        // intent, so the PendingIntent must be mutable (Android 12+ wants the
        // flag stated). Android 14+ refuses a mutable PendingIntent with an
        // implicit intent, hence setPackage.
        val intent = Intent(action).setPackage(context.packageName)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        usbManager.requestPermission(device, PendingIntent.getBroadcast(context, 0, intent, flags))
    }

    /** Answers "no" to whoever waits for a device that went away. */
    fun cancel(deviceName: String) {
        waiting.remove(deviceName)?.forEach { it(false) }
    }
}

internal fun Intent.usbDevice(): UsbDevice? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
    } else {
        @Suppress("DEPRECATION")
        getParcelableExtra(UsbManager.EXTRA_DEVICE)
    }

internal fun Context.registerReceiverCompat(receiver: BroadcastReceiver, filter: IntentFilter) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
        registerReceiver(receiver, filter)
    }
}
