// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'serial_exception.dart';

/// An open connection to a serial device: bytes in, bytes out.
///
/// This is the part that does not depend on how the device is attached.
/// `UsbSerialPort` implements it for USB and adds the line settings and
/// control lines; code that only reads and writes can take a [SerialPort]
/// and stay ready for other transports.
abstract class SerialPort {
  /// Bytes from the device, in the chunks they arrived in.
  ///
  /// A single-subscription stream: what arrives before you listen waits for
  /// you. Use [Stream.asBroadcastStream] for several listeners. The stream
  /// ends when the port closes; if the device was unplugged, it first emits a
  /// [SerialException] with [SerialError.disconnected].
  Stream<Uint8List> get input;

  /// Sends [data] and completes once the driver has handed all of it to the
  /// device.
  Future<void> write(List<int> data);

  /// Whether the port is still open.
  bool get isOpen;

  /// Completes when the port closes, with null after [close] and with the
  /// reason otherwise (an unplugged device, for example).
  Future<SerialException?> get closed;

  /// Closes the port. Safe to call more than once.
  Future<void> close();
}

/// Text helpers for line-based devices (AT commands, NMEA, Arduino's
/// Serial.println).
extension SerialPortText on SerialPort {
  /// [input] decoded and split into lines; "\n", "\r\n" and "\r" all end a
  /// line, and bytes that are not valid UTF-8 become U+FFFD instead of
  /// failing the stream. Listens to [input], so use one or the other.
  Stream<String> lines({Encoding encoding = utf8}) {
    final decoder = encoding is Utf8Codec
        ? const Utf8Decoder(allowMalformed: true)
        : encoding.decoder;
    return const LineSplitter().bind(decoder.bind(input));
  }

  /// Sends [text] encoded with [encoding]. Add the line ending the device
  /// expects yourself, for example `writeText('AT\r\n')`.
  Future<void> writeText(String text, {Encoding encoding = utf8}) =>
      write(encoding.encode(text));
}
