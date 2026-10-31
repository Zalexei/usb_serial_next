// The fake stands in for the native side, which lives in the plugin's src.
// ignore_for_file: implementation_imports
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usb_serial_next/src/messages.g.dart';
import 'package:usb_serial_next/usb_serial_next.dart';
import 'package:usb_serial_next_example/main.dart';

class _FakeHost extends UsbSerialHostApi {
  final devices = <NativeUsbDevice>[];
  final written = <List<int>>[];
  NativeOpenRequest? opened;

  @override
  Future<void> reset() async {}

  @override
  Future<List<NativeUsbDevice>> listDevices() async => devices;

  @override
  Future<bool> hasPermission(String deviceName) async => true;

  @override
  Future<bool> requestPermission(String deviceName) async => true;

  @override
  Future<NativeUsbDevice?> launchDevice() async => null;

  @override
  Future<int> open(NativeOpenRequest request) async {
    opened = request;
    return 1;
  }

  @override
  Future<void> write(int portId, Uint8List data, int timeoutMs) async =>
      written.add(data);

  @override
  Future<void> close(int portId) async {}
}

NativeUsbDevice _esp32() => NativeUsbDevice(
  deviceName: '/dev/bus/usb/001/002',
  deviceId: 2,
  vendorId: 0x303a,
  productId: 0x1001,
  productName: 'USB JTAG/serial debug unit',
  manufacturerName: 'Espressif',
  driver: NativeDriver.cdcAcm,
  portCount: 1,
  hasPermission: true,
);

void main() {
  late _FakeHost host;
  late UsbSerial usb;

  setUp(() {
    host = _FakeHost();
    usb = UsbSerial.withHostApi(host);
  });

  testWidgets('says so when no device is plugged in', (tester) async {
    await tester.pumpWidget(TerminalApp(usb: usb));
    await tester.pumpAndSettle();

    expect(find.text('No USB devices'), findsOneWidget);
  });

  testWidgets('lists a plugged in device', (tester) async {
    await tester.pumpWidget(TerminalApp(usb: usb));
    await tester.pumpAndSettle();

    host.devices.add(_esp32());
    usb.platformCallbacks.onDeviceAttached(_esp32());
    await tester.pumpAndSettle();

    expect(find.text('USB JTAG/serial debug unit'), findsOneWidget);
    expect(find.textContaining('303a:1001 · cdcAcm'), findsOneWidget);
  });

  testWidgets('connects, shows received data and sends a line', (tester) async {
    host.devices.add(_esp32());
    await tester.pumpWidget(TerminalApp(usb: usb));
    await tester.pumpAndSettle();

    await tester.tap(find.text('USB JTAG/serial debug unit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(host.opened!.config.baudRate, 115200);
    expect(host.opened!.config.dtr, isTrue);
    expect(find.textContaining('Connected, 115200 8N1'), findsOneWidget);

    usb.platformCallbacks.onData(1, Uint8List.fromList('pong\r\n'.codeUnits));
    await tester.pumpAndSettle();
    expect(find.textContaining(r'← pong\r\n'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ping');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(host.written.single, 'ping\n'.codeUnits);

    await tester.tap(find.byTooltip('Show hex'));
    await tester.pumpAndSettle();
    expect(find.textContaining('→ 70 69 6E 67 0A'), findsOneWidget);

    usb.platformCallbacks.onPortClosed(
      1,
      'disconnected',
      'The device was unplugged',
    );
    await tester.pumpAndSettle();
    expect(find.text('The device was unplugged.'), findsOneWidget);
  });
}
