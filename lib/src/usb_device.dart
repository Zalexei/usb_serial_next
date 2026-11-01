// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import 'package:meta/meta.dart';
import 'package:serial_port_core/serial_port_core.dart';

/// Driver families, from usb-serial-for-android.
enum UsbSerialDriver {
  /// The standard USB serial class: Arduino boards with native USB, ESP32-S2
  /// and S3, RP2040, STM32, CH343, CH9102 and most modems.
  cdcAcm,

  /// FTDI FT232R, FT232H, FT2232H, FT4232H, FT230X, FT231X, FT234XD.
  ftdi,

  /// Silicon Labs CP2102, CP2104, CP2105, CP2108 and others of the family.
  cp21xx,

  /// WCH CH340 and CH341A.
  ch34x,

  /// Prolific PL2303, including the newer G and HXN chips.
  prolific,

  /// Modems with bare bulk endpoints, such as Unisoc based Fibocom.
  gsmModem,

  /// The debug port of Chromebooks (Closed Case Debugging).
  chromeCcd,
}

/// A device on the USB bus, serial or not.
@immutable
class UsbDevice {
  const UsbDevice({
    required this.deviceName,
    required this.deviceId,
    required this.vendorId,
    required this.productId,
    this.manufacturerName,
    this.productName,
    this.serialNumber,
    this.driver,
    this.portCount = 0,
    this.hasPermission = false,
  });

  /// Identifies the device while it stays plugged in, like
  /// "/dev/bus/usb/001/002". It changes when the device is plugged in again.
  final String deviceName;
  final int deviceId;
  final int vendorId;
  final int productId;
  final String? manufacturerName;
  final String? productName;

  /// Null until the app has permission for the device (Android 10+), and for
  /// devices without one. Use it to find "the same" device after a replug.
  final String? serialNumber;

  /// The driver that would open the device; null if none knows it.
  final UsbSerialDriver? driver;

  /// How many serial ports the device has (FT2232H and CP2105 have two,
  /// FT4232H four); 0 when [driver] is null.
  final int portCount;

  /// Whether the app had permission when this object was made.
  final bool hasPermission;

  /// Whether a driver knows the device.
  bool get isSerial => driver != null;

  /// Like "1a86:7523".
  String get vidPid => '${_hex4(vendorId)}:${_hex4(productId)}';

  static String _hex4(int value) => value.toRadixString(16).padLeft(4, '0');

  @override
  bool operator ==(Object other) =>
      other is UsbDevice &&
      other.deviceName == deviceName &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(deviceName, deviceId);

  @override
  String toString() =>
      'UsbDevice($vidPid ${productName ?? ''} at $deviceName, ${driver?.name ?? 'no driver'})';
}

/// A device was plugged in or out.
sealed class UsbDeviceEvent {
  const UsbDeviceEvent(this.device);

  final UsbDevice device;
}

final class UsbDeviceAttached extends UsbDeviceEvent {
  const UsbDeviceAttached(super.device);

  @override
  String toString() => 'UsbDeviceAttached($device)';
}

/// Ports of the device were closed already; their [SerialPort.input]
/// streams end with [SerialError.disconnected].
final class UsbDeviceDetached extends UsbDeviceEvent {
  const UsbDeviceDetached(super.device);

  @override
  String toString() => 'UsbDeviceDetached($device)';
}
