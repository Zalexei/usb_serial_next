import 'dart:async';

import 'package:flutter/services.dart';
import 'package:usb_serial_next/src/messages.g.dart';

/// Stands in for the native side: a USB bus with devices the test plugs in,
/// a permission dialog the test answers, and ports that record writes.
class FakeHostApi extends UsbSerialHostApi {
  final Map<String, NativeUsbDevice> devices = {};
  final Set<String> permitted = {};
  final List<String> calls = [];

  /// Answers the next permission dialog; null leaves it waiting.
  bool? permissionAnswer = true;
  Completer<bool>? permissionDialog;

  final Map<int, NativeOpenRequest> openPorts = {};
  final Map<int, List<Uint8List>> written = {};
  final Map<int, int> writeTimeouts = {};
  NativeUsbDevice? launch;
  PlatformException? openError;
  PlatformException? writeError;
  NativeControlLines controlLines = NativeControlLines(dtr: true, cts: false);
  int _nextId = 1;

  NativeUsbDevice plug(
    String name, {
    int vendorId = 0x1a86,
    int productId = 0x7523,
    NativeDriver? driver = NativeDriver.ch34x,
    int portCount = 1,
    bool permitted = false,
  }) {
    final device = NativeUsbDevice(
      deviceName: name,
      deviceId: devices.length + 1,
      vendorId: vendorId,
      productId: productId,
      productName: 'USB Serial',
      driver: driver,
      portCount: portCount,
      hasPermission: permitted,
    );
    devices[name] = device;
    if (permitted) this.permitted.add(name);
    return device;
  }

  @override
  Future<void> reset() async => calls.add('reset');

  @override
  Future<List<NativeUsbDevice>> listDevices() async {
    calls.add('listDevices');
    return devices.values.toList();
  }

  @override
  Future<bool> hasPermission(String deviceName) async =>
      permitted.contains(deviceName);

  @override
  Future<bool> requestPermission(String deviceName) async {
    calls.add('requestPermission $deviceName');
    if (!devices.containsKey(deviceName)) {
      throw PlatformException(code: 'device_not_found', message: deviceName);
    }
    if (permitted.contains(deviceName)) return true;
    final answer = permissionAnswer;
    final granted = answer ?? await (permissionDialog = Completer()).future;
    if (granted) permitted.add(deviceName);
    return granted;
  }

  @override
  Future<NativeUsbDevice?> launchDevice() async => launch;

  @override
  Future<int> open(NativeOpenRequest request) async {
    calls.add('open ${request.deviceName}#${request.portIndex}');
    if (openError != null) throw openError!;
    if (!permitted.contains(request.deviceName)) {
      throw PlatformException(code: 'permission_denied', message: 'no');
    }
    final id = _nextId++;
    openPorts[id] = request;
    written[id] = [];
    return id;
  }

  @override
  Future<void> write(int portId, Uint8List data, int timeoutMs) async {
    _checkOpen(portId);
    if (writeError != null) throw writeError!;
    written[portId]!.add(data);
    writeTimeouts[portId] = timeoutMs;
  }

  @override
  Future<void> setConfig(int portId, NativePortConfig config) async {
    _checkOpen(portId);
    if (config.flowControl != NativeFlowControl.none) {
      throw PlatformException(
          code: 'unsupported_operation', message: 'no flow control');
    }
    openPorts[portId]!.config = config;
  }

  @override
  Future<void> setDtr(int portId, bool value) async {
    _checkOpen(portId);
    calls.add('setDtr $portId $value');
  }

  @override
  Future<void> setRts(int portId, bool value) async {
    _checkOpen(portId);
    calls.add('setRts $portId $value');
  }

  @override
  Future<NativeControlLines> getControlLines(int portId) async {
    _checkOpen(portId);
    return controlLines;
  }

  @override
  Future<void> setBreak(int portId, bool value) async {
    _checkOpen(portId);
    calls.add('setBreak $portId $value');
  }

  @override
  Future<void> purge(int portId, bool output, bool input) async {
    _checkOpen(portId);
    calls.add('purge $portId $output $input');
  }

  @override
  Future<void> close(int portId) async {
    calls.add('close $portId');
    openPorts.remove(portId);
  }

  void _checkOpen(int portId) {
    if (!openPorts.containsKey(portId)) {
      throw PlatformException(code: 'port_closed', message: 'closed');
    }
  }
}
