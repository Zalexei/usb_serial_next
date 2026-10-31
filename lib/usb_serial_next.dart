// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.

/// USB serial devices on Android (Arduino, ESP32, FTDI, CP210x, CH34x,
/// PL2303, CDC-ACM) over the USB host API.
library;

export 'src/serial_config.dart';
export 'src/serial_exception.dart';
export 'src/serial_port.dart';
export 'src/usb_device.dart';
export 'src/usb_serial.dart' show ControlLines, UsbSerial, UsbSerialPort;
