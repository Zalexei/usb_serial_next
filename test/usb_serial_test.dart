import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usb_serial_next/src/messages.g.dart';
import 'package:usb_serial_next/usb_serial_next.dart';

import 'fake_host_api.dart';

void main() {
  late FakeHostApi host;
  late UsbSerial usb;

  setUp(() {
    host = FakeHostApi();
    usb = UsbSerial.withHostApi(host);
  });

  Future<UsbDevice> plugged(String name, {bool permitted = true}) async {
    host.plug(name, permitted: permitted);
    return (await usb.listDevices()).firstWhere((d) => d.deviceName == name);
  }

  group('devices', () {
    test('lists devices with their driver and ids', () async {
      host.plug('/dev/bus/usb/001/002');
      host.plug('/dev/bus/usb/001/003',
          vendorId: 0x046d, productId: 0xc52b, driver: null, portCount: 0);

      final devices = await usb.listDevices();

      expect(devices, hasLength(2));
      expect(devices[0].vidPid, '1a86:7523');
      expect(devices[0].driver, UsbSerialDriver.ch34x);
      expect(devices[0].isSerial, isTrue);
      expect(devices[1].isSerial, isFalse);
      expect(devices[1].portCount, 0);
    });

    test('closes ports of an earlier run before the first call', () async {
      await usb.listDevices();
      await usb.listDevices();

      expect(host.calls, ['reset', 'listDevices', 'listDevices']);
    });

    test('driver enums match the platform ones', () {
      expect(UsbSerialDriver.values.map((e) => e.name),
          NativeDriver.values.map((e) => e.name));
      expect(Parity.values.map((e) => e.name),
          NativeParity.values.map((e) => e.name));
      expect(StopBits.values.map((e) => e.name),
          NativeStopBits.values.map((e) => e.name));
      expect(FlowControl.values.map((e) => e.name),
          NativeFlowControl.values.map((e) => e.name));
    });

    test('reports plugged and unplugged devices', () async {
      final events = <UsbDeviceEvent>[];
      usb.deviceEvents.listen(events.add);
      final native = host.plug('/dev/bus/usb/001/002');

      usb.platformCallbacks.onDeviceAttached(native);
      usb.platformCallbacks.onDeviceDetached(native);
      await pumpEventQueue();

      expect(events[0], isA<UsbDeviceAttached>());
      expect(events[1], isA<UsbDeviceDetached>());
      expect(events[1].device.deviceName, '/dev/bus/usb/001/002');
    });

    test('returns the device that launched the app', () async {
      expect(await usb.getLaunchDevice(), isNull);
      host.launch = host.plug('/dev/bus/usb/001/002', permitted: true);

      final device = await usb.getLaunchDevice();

      expect(device!.deviceName, '/dev/bus/usb/001/002');
      expect(device.hasPermission, isTrue);
    });
  });

  group('permission', () {
    test('open asks for permission when the app has none', () async {
      final device = await plugged('/dev/bus/usb/001/002', permitted: false);

      final port = await usb.open(device);

      expect(port.isOpen, isTrue);
      expect(host.calls, contains('requestPermission /dev/bus/usb/001/002'));
    });

    test('open fails clearly when the user says no', () async {
      final device = await plugged('/dev/bus/usb/001/002', permitted: false);
      host.permissionAnswer = false;

      await expectLater(
          usb.open(device), throwsSerialError(SerialError.permissionDenied));
      expect(host.openPorts, isEmpty);
    });

    test('open without asking reports the missing permission', () async {
      final device = await plugged('/dev/bus/usb/001/002', permitted: false);

      await expectLater(usb.open(device, requestPermission: false),
          throwsSerialError(SerialError.permissionDenied));
      expect(host.calls, isNot(contains(startsWith('requestPermission'))));
    });

    test('requestPermission waits for the dialog', () async {
      final device = await plugged('/dev/bus/usb/001/002', permitted: false);
      host.permissionAnswer = null;

      final answer = usb.requestPermission(device);
      await pumpEventQueue();
      host.permissionDialog!.complete(true);

      expect(await answer, isTrue);
      expect(await usb.hasPermission(device), isTrue);
    });

    test('a device unplugged before the dialog is not found', () async {
      final device = await plugged('/dev/bus/usb/001/002', permitted: false);
      host.devices.clear();

      await expectLater(usb.requestPermission(device),
          throwsSerialError(SerialError.deviceNotFound));
    });
  });

  group('open', () {
    test('sends the config, port index and forced driver', () async {
      final device = await plugged('/dev/bus/usb/001/002');

      final port = await usb.open(
        device,
        portIndex: 1,
        driver: UsbSerialDriver.cdcAcm,
        config: const SerialConfig(
          baudRate: 9600,
          dataBits: 7,
          parity: Parity.even,
          stopBits: StopBits.two,
          dtr: true,
        ),
      );

      final request = host.openPorts.values.single;
      expect(request.portIndex, 1);
      expect(request.driver, NativeDriver.cdcAcm);
      expect(request.config.baudRate, 9600);
      expect(request.config.dataBits, 7);
      expect(request.config.parity, NativeParity.even);
      expect(request.config.stopBits, NativeStopBits.two);
      expect(request.config.dtr, isTrue);
      expect(request.config.rts, isNull);
      expect(port.config.toString(), '9600 7E2');
    });

    test('rejects bad settings before calling the platform', () async {
      final device = await plugged('/dev/bus/usb/001/002');

      await expectLater(
          usb.open(device, config: const SerialConfig(baudRate: 0)),
          throwsSerialError(SerialError.invalidArgument));
      await expectLater(
          usb.open(device, config: const SerialConfig(dataBits: 9)),
          throwsSerialError(SerialError.invalidArgument));
      await expectLater(usb.open(device, portIndex: -1),
          throwsSerialError(SerialError.invalidArgument));
      expect(host.calls, isNot(contains(startsWith('open'))));
    });

    test('maps platform errors to SerialException', () async {
      final device = await plugged('/dev/bus/usb/001/002');
      host.openError = PlatformException(code: 'busy', message: 'claimed');

      await expectLater(usb.open(device), throwsSerialError(SerialError.busy));
    });

    test('keeps an unknown platform error code in the message', () async {
      final device = await plugged('/dev/bus/usb/001/002');
      host.openError =
          PlatformException(code: 'channel-error', message: 'no handler');

      await expectLater(
        usb.open(device),
        throwsA(isA<SerialException>()
            .having((e) => e.error, 'error', SerialError.io)
            .having((e) => e.message, 'message', contains('channel-error'))),
      );
    });
  });

  group('port', () {
    late UsbSerialPort port;
    late int id;

    setUp(() async {
      final device = await plugged('/dev/bus/usb/001/002');
      port = await usb.open(device, config: const SerialConfig(baudRate: 9600));
      id = host.openPorts.keys.single;
    });

    test('delivers received data in order', () async {
      final received = <int>[];
      port.input.listen(received.addAll);

      usb.platformCallbacks.onData(id, Uint8List.fromList([1, 2]));
      usb.platformCallbacks.onData(id, Uint8List.fromList([3]));
      await pumpEventQueue();

      expect(received, [1, 2, 3]);
    });

    test('keeps data that arrives before anyone listens', () async {
      usb.platformCallbacks.onData(id, Uint8List.fromList([7]));

      expect(await port.input.first, [7]);
    });

    test('writes bytes with a timeout that fits the baud rate', () async {
      await port.write([0x41, 0x42]);
      expect(host.written[id]![0], [0x41, 0x42]);
      // 2 bytes at 9600 baud take about 2 ms: twice that plus a second.
      expect(host.writeTimeouts[id], 1004);

      await port.write(List.filled(960, 0));
      // 960 bytes take a second, so the limit is three.
      expect(host.writeTimeouts[id], 3000);
    });

    test('an explicit write timeout wins', () async {
      await port.write([1], timeout: Duration.zero);

      expect(host.writeTimeouts[id], 0);
    });

    test('an empty write does not reach the platform', () async {
      await port.write([]);

      expect(host.written[id], isEmpty);
    });

    test('a write timeout reports how much went out', () async {
      host.writeError =
          PlatformException(code: 'timeout', message: 'slow', details: 12);

      await expectLater(
        port.write([1, 2, 3]),
        throwsA(isA<SerialException>()
            .having((e) => e.error, 'error', SerialError.timeout)
            .having((e) => e.bytesWritten, 'bytesWritten', 12)),
      );
    });

    test('controls DTR, RTS, break and buffers', () async {
      await port.setDtr(true);
      await port.setRts(false);
      await port.setBreak(true);
      await port.purge(output: false);

      expect(
          host.calls,
          containsAll([
            'setDtr $id true',
            'setRts $id false',
            'setBreak $id true',
            'purge $id false true'
          ]));
    });

    test('reads control lines, null for lines the chip lacks', () async {
      final lines = await port.getControlLines();

      expect(lines.dtr, isTrue);
      expect(lines.cts, isFalse);
      expect(lines.ri, isNull);
    });

    test('changes the config only when the chip accepts it', () async {
      await port.setConfig(const SerialConfig(baudRate: 115200));
      expect(port.config.baudRate, 115200);

      await expectLater(
          port.setConfig(const SerialConfig(flowControl: FlowControl.rtsCts)),
          throwsSerialError(SerialError.unsupportedOperation));
      expect(port.config.flowControl, FlowControl.none);
    });

    test('close ends the stream and later calls fail', () async {
      final done = expectLater(port.input, emitsDone);

      await port.close();
      await port.close();

      await done;
      expect(port.isOpen, isFalse);
      expect(await port.closed, isNull);
      expect(host.calls.where((c) => c == 'close $id'), hasLength(1));
      expect(() => port.write([1]), throwsSerialError(SerialError.portClosed));
      expect(
          () => port.setDtr(true), throwsSerialError(SerialError.portClosed));
    });

    test('unplugging ends the stream with disconnected', () async {
      final ending = expectLater(
          port.input,
          emitsInOrder([
            [9],
            emitsError(isSerialError(SerialError.disconnected)),
            emitsDone,
          ]));

      usb.platformCallbacks.onData(id, Uint8List.fromList([9]));
      usb.platformCallbacks
          .onPortClosed(id, 'disconnected', 'The device was unplugged');

      await ending;
      expect((await port.closed)!.error, SerialError.disconnected);
      expect(
          () => port.write([1]), throwsSerialError(SerialError.disconnected));
    });

    test('data after close is dropped', () async {
      final received = <int>[];
      port.input.listen(received.addAll);
      await port.close();

      usb.platformCallbacks.onData(id, Uint8List.fromList([1]));
      await pumpEventQueue();

      expect(received, isEmpty);
    });

    test('a second port of the same device works on its own', () async {
      final second =
          await usb.open(port.device, portIndex: 1, requestPermission: false);
      final secondId = host.openPorts.keys.last;
      final received = <int>[];
      second.input.listen(received.addAll);

      usb.platformCallbacks.onData(id, Uint8List.fromList([1]));
      usb.platformCallbacks.onData(secondId, Uint8List.fromList([2]));
      await port.close();
      await pumpEventQueue();

      expect(received, [2]);
      expect(second.isOpen, isTrue);
    });
  });

  group('text', () {
    test('lines() splits across chunks and survives bad bytes', () async {
      final device = await plugged('/dev/bus/usb/001/002');
      final port = await usb.open(device);
      final id = host.openPorts.keys.single;
      final lines = port.lines().toList();

      for (final chunk in [
        'temp=2'.codeUnits,
        '1.5\r\nhum'.codeUnits,
        [0xff],
        '=40\nend'.codeUnits,
      ]) {
        usb.platformCallbacks.onData(id, Uint8List.fromList(chunk));
      }
      await port.close();

      expect(await lines, ['temp=21.5', 'hum�=40', 'end']);
    });

    test('writeText encodes UTF-8', () async {
      final device = await plugged('/dev/bus/usb/001/002');
      final port = await usb.open(device);

      await port.writeText('AT+ПРИВЕТ\r\n');

      final bytes = host.written.values.single.single;
      expect(bytes, hasLength(17));
      expect(utf8.decode(bytes), 'AT+ПРИВЕТ\r\n');
    });
  });

  test('throws on platforms other than Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(UsbSerial.isSupported, isFalse);
    await expectLater(
        usb.listDevices(), throwsSerialError(SerialError.unsupportedOperation));
  });

  test('SerialConfig equality and copyWith', () {
    const config = SerialConfig(baudRate: 9600);

    expect(config.copyWith(baudRate: 9600), config);
    expect(config.copyWith(parity: Parity.odd), isNot(config));
    expect(config.bitsPerByte, 10);
    expect(
        const SerialConfig(parity: Parity.even, stopBits: StopBits.two)
            .bitsPerByte,
        12);
    expect(const SerialConfig(flowControl: FlowControl.rtsCts).toString(),
        '115200 8N1 rtsCts');
  });
}

Matcher isSerialError(SerialError error) =>
    isA<SerialException>().having((e) => e.error, 'error', error);

Matcher throwsSerialError(SerialError error) => throwsA(isSerialError(error));
