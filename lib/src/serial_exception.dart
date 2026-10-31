// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import 'package:flutter/services.dart';

/// Why an operation failed.
enum SerialError {
  /// The app has no permission for the device, or the user said no.
  permissionDenied,

  /// The device is not attached (any more).
  deviceNotFound,

  /// No driver knows the device. If you know the chip, pass a driver to
  /// `UsbSerial.open`.
  unsupportedDevice,

  /// The device was unplugged while the port was open.
  disconnected,

  /// The port was closed before or during the operation.
  portClosed,

  /// The port is already open, here or in another app.
  busy,

  /// A value is out of range: baud rate, data bits, port index.
  invalidArgument,

  /// The chip or platform cannot do this, for example flow control on a
  /// chip without it.
  unsupportedOperation,

  /// A write did not finish in time.
  timeout,

  /// Any other failure; see [SerialException.message].
  io,
}

/// What every call of the plugin throws when it fails, and what [Stream]s of
/// received data end with when a device goes away.
class SerialException implements Exception {
  const SerialException(this.error, [this.message, this.bytesWritten]);

  /// Converts an error code from the platform side.
  factory SerialException.fromCode(String code,
      [String? message, Object? details]) {
    final error = _codes[code];
    if (error == null) {
      // An unknown code is itself the clue (a channel error, an engine that
      // went away), so it stays in the message.
      return SerialException(SerialError.io, '$code: $message');
    }
    return SerialException(error, message, details is int ? details : null);
  }

  factory SerialException.fromPlatform(PlatformException e) =>
      SerialException.fromCode(e.code, e.message, e.details);

  static const _codes = {
    'permission_denied': SerialError.permissionDenied,
    'device_not_found': SerialError.deviceNotFound,
    'unsupported_device': SerialError.unsupportedDevice,
    'disconnected': SerialError.disconnected,
    'port_closed': SerialError.portClosed,
    'busy': SerialError.busy,
    'invalid_argument': SerialError.invalidArgument,
    'unsupported_operation': SerialError.unsupportedOperation,
    'timeout': SerialError.timeout,
    'io_error': SerialError.io,
  };

  /// Why it failed.
  final SerialError error;

  /// Details for logs, in English.
  final String? message;

  /// For [SerialError.timeout]: how many bytes went out before the timeout.
  final int? bytesWritten;

  @override
  String toString() => 'SerialException(${error.name}: $message)';
}
