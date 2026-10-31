# usb_serial_next example

A serial terminal for Android:

- the USB devices, updated when one is plugged in or out;
- line settings before connecting (baud rate, data bits, parity, stop bits,
  flow control, DTR and RTS, the port of a multi-port device, a driver for an
  unknown device);
- received and sent data as text (control characters shown as `\r`, `\n`)
  or hex, sending text with a line ending or raw hex;
- DTR and RTS toggles and the input control lines;
- `android/app/src/main/res/xml/device_filter.xml`: the app offers to open
  when a common adapter or board is plugged in, and then has permission for it.

Run it with a phone that supports USB OTG:

```bash
flutter run
```

`../tool/esp32_echo` is a PlatformIO firmware for ESP32 boards that answers
`ping`, `info`, `burst N` and echoes everything else.
