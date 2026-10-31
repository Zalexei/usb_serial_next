import 'package:flutter_test/flutter_test.dart';
import 'package:usb_serial_next/usb_serial_next.dart';

void main() {
  // No binding is initialized in this file, as in main() before runApp.
  test('the instance can be read before runApp', () {
    expect(() => UsbSerial.instance, returnsNormally);
    expect(() => UsbSerial.instance.deviceEvents, returnsNormally);
  });
}
