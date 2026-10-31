## 0.1.0

* First release: USB serial on Android with usb-serial-for-android 3.11.0
  inside the plugin (no JitPack). FTDI, CP210x, CH34x, PL2303 and CDC-ACM
  devices; device list, permission dialog, line settings and flow control,
  DTR/RTS and the other control lines, break, buffer purge, received data as
  a stream, plug and unplug events, the device that started the app, and
  `SerialException` with a `SerialError` for every failure.
