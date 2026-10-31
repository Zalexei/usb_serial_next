import 'package:flutter/material.dart';
import 'package:usb_serial_next/usb_serial_next.dart';

import 'devices_page.dart';

void main() => runApp(TerminalApp(usb: UsbSerial.instance));

class TerminalApp extends StatelessWidget {
  const TerminalApp({super.key, required this.usb});

  final UsbSerial usb;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'USB serial terminal',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: DevicesPage(usb: usb),
    );
  }
}
