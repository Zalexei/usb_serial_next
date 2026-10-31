// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'messages.g.dart';
import 'serial_config.dart';
import 'serial_exception.dart';
import 'serial_port.dart';
import 'usb_device.dart';

/// USB serial devices on Android: find them, ask for access, open ports.
///
/// ```dart
/// final usb = UsbSerial.instance;
/// final device = (await usb.listDevices()).firstWhere((d) => d.isSerial);
/// final port = await usb.open(device, config: const SerialConfig(baudRate: 9600));
/// port.lines().listen(print);
/// await port.writeText('hello\n');
/// ```
class UsbSerial {
  UsbSerial._(this._host) : _listensToPlatform = true;

  /// Uses [host] instead of the platform, and does not listen to the
  /// platform: tests deliver its calls through [platformCallbacks].
  @visibleForTesting
  UsbSerial.withHostApi(UsbSerialHostApi host)
      : _host = host,
        _listensToPlatform = false;

  static UsbSerial? _instance;

  /// The one instance for the app.
  static UsbSerial get instance =>
      _instance ??= UsbSerial._(UsbSerialHostApi());

  /// Whether the plugin works here: on Android only.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final UsbSerialHostApi _host;
  final Map<int, UsbSerialPort> _ports = {};
  late final _events =
      StreamController<UsbDeviceEvent>.broadcast(onListen: _listenToPlatform);
  Future<void>? _ready;

  // The platform's calls are handled from the first use on, not from
  // construction: `UsbSerial.instance` may be read in main() before runApp,
  // when there is no binary messenger yet.
  final bool _listensToPlatform;
  bool _listening = false;

  void _listenToPlatform() {
    if (!_listensToPlatform || _listening) return;
    UsbSerialFlutterApi.setUp(platformCallbacks);
    _listening = true;
  }

  /// The receiving end of the platform's calls, for tests.
  @visibleForTesting
  late final UsbSerialFlutterApi platformCallbacks = _Callbacks(this);

  /// All devices on the USB bus. Serial ones have [UsbDevice.isSerial].
  Future<List<UsbDevice>> listDevices() async {
    final devices = await _call(_host.listDevices);
    return devices.map(_toDevice).toList();
  }

  /// Whether the app may open [device] now.
  Future<bool> hasPermission(UsbDevice device) =>
      _call(() => _host.hasPermission(device.deviceName));

  /// Asks the user for access to [device] with the system dialog, unless the
  /// app already has it, and completes with the answer.
  ///
  /// Access lasts until the device is unplugged. For access that survives a
  /// replug, see "Open the app when a device is plugged in" in the README.
  Future<bool> requestPermission(UsbDevice device) =>
      _call(() => _host.requestPermission(device.deviceName));

  /// The device whose plugging in started the app, if the activity has a
  /// USB_DEVICE_ATTACHED intent filter (see the README) and the device is
  /// still there. The app already has permission for it.
  Future<UsbDevice?> getLaunchDevice() async {
    final device = await _call(_host.launchDevice);
    return device == null ? null : _toDevice(device);
  }

  /// Devices plugged in and out while the app runs.
  ///
  /// When a device goes away, its open ports are already closed by the time
  /// [UsbDeviceDetached] arrives.
  Stream<UsbDeviceEvent> get deviceEvents => _events.stream;

  /// Opens port [portIndex] of [device] with [config].
  ///
  /// Asks for permission first if the app has none, unless
  /// [requestPermission] is false. [driver] forces a driver for a device the
  /// plugin does not recognize, for example a CH340 clone with its own
  /// VID/PID.
  ///
  /// Throws [SerialException]: [SerialError.permissionDenied],
  /// [SerialError.deviceNotFound], [SerialError.unsupportedDevice],
  /// [SerialError.busy] (already open), [SerialError.invalidArgument],
  /// [SerialError.unsupportedOperation] (settings the chip lacks).
  Future<UsbSerialPort> open(
    UsbDevice device, {
    SerialConfig config = const SerialConfig(),
    int portIndex = 0,
    UsbSerialDriver? driver,
    bool requestPermission = true,
  }) async {
    config.validate();
    if (portIndex < 0) {
      throw SerialException(SerialError.invalidArgument,
          'Port index must not be negative, got $portIndex');
    }
    if (requestPermission && !await hasPermission(device)) {
      if (!await this.requestPermission(device)) {
        throw SerialException(
            SerialError.permissionDenied, 'No access to ${device.deviceName}');
      }
    }
    final request = NativeOpenRequest(
      deviceName: device.deviceName,
      portIndex: portIndex,
      driver: driver == null ? null : NativeDriver.values[driver.index],
      config: _toNativeConfig(config),
    );
    final id = await _call(() => _host.open(request));
    final port = UsbSerialPort._(this, id, device, portIndex, config);
    _ports[id] = port;
    return port;
  }

  /// Calls the platform and turns its errors into [SerialException].
  ///
  /// The first call closes ports left open by an earlier run of the Dart
  /// code (a hot restart keeps the native side running).
  Future<T> _call<T>(Future<T> Function() call) async {
    if (!isSupported) {
      throw const SerialException(SerialError.unsupportedOperation,
          'usb_serial_next works on Android only');
    }
    _listenToPlatform();
    try {
      final ready = _ready ??= _host.reset();
      try {
        await ready;
      } catch (_) {
        _ready = null;
        rethrow;
      }
      return await call();
    } on PlatformException catch (e) {
      throw SerialException.fromPlatform(e);
    }
  }

  static UsbDevice _toDevice(NativeUsbDevice d) => UsbDevice(
        deviceName: d.deviceName,
        deviceId: d.deviceId,
        vendorId: d.vendorId,
        productId: d.productId,
        manufacturerName: d.manufacturerName,
        productName: d.productName,
        serialNumber: d.serialNumber,
        driver:
            d.driver == null ? null : UsbSerialDriver.values[d.driver!.index],
        portCount: d.portCount,
        hasPermission: d.hasPermission,
      );

  static NativePortConfig _toNativeConfig(SerialConfig c) => NativePortConfig(
        baudRate: c.baudRate,
        dataBits: c.dataBits,
        stopBits: NativeStopBits.values[c.stopBits.index],
        parity: NativeParity.values[c.parity.index],
        flowControl: NativeFlowControl.values[c.flowControl.index],
        dtr: c.dtr,
        rts: c.rts,
      );
}

/// A port of a USB serial device. Get one from [UsbSerial.open].
class UsbSerialPort implements SerialPort {
  UsbSerialPort._(
      this._owner, this._id, this.device, this.portIndex, this._config);

  final UsbSerial _owner;
  final int _id;

  final UsbDevice device;
  final int portIndex;

  SerialConfig _config;
  SerialException? _closeReason;
  final _input = StreamController<Uint8List>();
  final _closed = Completer<SerialException?>();

  /// The settings the port was opened or last configured with.
  SerialConfig get config => _config;

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  bool get isOpen => !_closed.isCompleted;

  @override
  Future<SerialException?> get closed => _closed.future;

  /// Sends [data]. Fails with [SerialError.timeout] if it takes longer than
  /// [timeout]; the default is twice the time the bytes need on the wire
  /// plus a second. [Duration.zero] waits forever, which can hang on a
  /// device that holds the port with flow control.
  @override
  Future<void> write(List<int> data, {Duration? timeout}) async {
    _checkOpen();
    if (data.isEmpty) return;
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    final wire = Duration(
        microseconds:
            (bytes.length * _config.bitsPerByte * 1e6 / _config.baudRate)
                .ceil());
    final limit = timeout ?? wire * 2 + const Duration(seconds: 1);
    await _owner
        ._call(() => _owner._host.write(_id, bytes, limit.inMilliseconds));
  }

  /// Changes the line settings of the open port.
  Future<void> setConfig(SerialConfig config) async {
    config.validate();
    _checkOpen();
    await _owner._call(
        () => _owner._host.setConfig(_id, UsbSerial._toNativeConfig(config)));
    _config = config;
  }

  /// Sets the DTR (data terminal ready) line.
  Future<void> setDtr(bool value) =>
      _control(() => _owner._host.setDtr(_id, value));

  /// Sets the RTS (request to send) line.
  Future<void> setRts(bool value) =>
      _control(() => _owner._host.setRts(_id, value));

  /// Reads the modem control lines; a line the chip does not report is null.
  Future<ControlLines> getControlLines() async {
    final lines = await _control(() => _owner._host.getControlLines(_id));
    return ControlLines(
      rts: lines.rts,
      cts: lines.cts,
      dtr: lines.dtr,
      dsr: lines.dsr,
      cd: lines.cd,
      ri: lines.ri,
    );
  }

  /// Holds the TX line low (a break) while [value] is true.
  Future<void> setBreak(bool value) =>
      _control(() => _owner._host.setBreak(_id, value));

  /// Drops data waiting in the chip's buffers. Not every chip can.
  Future<void> purge({bool output = true, bool input = true}) =>
      _control(() => _owner._host.purge(_id, output, input));

  @override
  Future<void> close() async {
    if (!isOpen) return;
    _markClosed(null);
    await _owner._call(() => _owner._host.close(_id));
  }

  Future<T> _control<T>(Future<T> Function() call) {
    _checkOpen();
    return _owner._call(call);
  }

  void _checkOpen() {
    if (!isOpen) {
      throw _closeReason ??
          const SerialException(SerialError.portClosed, 'The port is closed');
    }
  }

  void _onData(Uint8List data) {
    if (isOpen) _input.add(data);
  }

  void _markClosed(SerialException? reason) {
    if (!isOpen) return;
    _closeReason = reason;
    _owner._ports.remove(_id);
    if (reason != null) _input.addError(reason);
    _input.close();
    _closed.complete(reason);
  }

  @override
  String toString() =>
      'UsbSerialPort(${device.vidPid} #$portIndex, $_config${isOpen ? '' : ', closed'})';
}

/// State of the modem control lines; null means the chip does not report
/// that line.
@immutable
class ControlLines {
  const ControlLines(
      {this.rts, this.cts, this.dtr, this.dsr, this.cd, this.ri});

  /// Request to send (output).
  final bool? rts;

  /// Clear to send (input).
  final bool? cts;

  /// Data terminal ready (output).
  final bool? dtr;

  /// Data set ready (input).
  final bool? dsr;

  /// Carrier detect (input).
  final bool? cd;

  /// Ring indicator (input).
  final bool? ri;

  @override
  String toString() =>
      'ControlLines(rts: $rts, cts: $cts, dtr: $dtr, dsr: $dsr, cd: $cd, ri: $ri)';
}

class _Callbacks implements UsbSerialFlutterApi {
  _Callbacks(this._owner);

  final UsbSerial _owner;

  @override
  void onData(int portId, Uint8List data) =>
      _owner._ports[portId]?._onData(data);

  @override
  void onPortClosed(int portId, String? errorCode, String? errorMessage) =>
      _owner._ports[portId]?._markClosed(errorCode == null
          ? null
          : SerialException.fromCode(errorCode, errorMessage));

  @override
  void onDeviceAttached(NativeUsbDevice device) =>
      _owner._events.add(UsbDeviceAttached(UsbSerial._toDevice(device)));

  @override
  void onDeviceDetached(NativeUsbDevice device) =>
      _owner._events.add(UsbDeviceDetached(UsbSerial._toDevice(device)));
}
