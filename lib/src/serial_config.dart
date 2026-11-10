// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import 'package:meta/meta.dart';
import 'package:serial_port_core/serial_port_core.dart';

/// The parity bit sent after the data bits of each byte.
enum Parity {
  /// No parity bit.
  none,

  /// The parity bit makes the number of ones odd.
  odd,

  /// The parity bit makes the number of ones even.
  even,

  /// The parity bit is always 1.
  mark,

  /// The parity bit is always 0.
  space,
}

/// How long the stop signal after each byte lasts, in bit times.
enum StopBits {
  /// One stop bit, the usual setting.
  one,

  /// One and a half stop bits; not every chip supports it.
  onePointFive,

  /// Two stop bits.
  two,
}

/// How the two sides pause each other when a buffer is full.
enum FlowControl {
  /// No flow control: data is sent whenever there is some.
  none,

  /// Hardware, with the RTS and CTS lines.
  rtsCts,

  /// Hardware, with the DTR and DSR lines.
  dtrDsr,

  /// Software, with XON/XOFF characters handled by the chip (CP210x).
  xonXoff,

  /// Software, with XON/XOFF characters left in the received data (FTDI,
  /// PL2303).
  xonXoffInline,
}

/// Line settings of a serial port. The default is 115200 baud, 8N1, no flow
/// control.
///
/// CDC-ACM and CH34x chips support [FlowControl.none] only; CP210x, FTDI and
/// PL2303 know some of the others (see the README). Asking for one the chip
/// lacks fails with [SerialError.unsupportedOperation].
@immutable
class SerialConfig {
  /// Creates line settings; values are checked by [validate] when the port
  /// opens or is reconfigured.
  const SerialConfig({
    this.baudRate = 115200,
    this.dataBits = 8,
    this.stopBits = StopBits.one,
    this.parity = Parity.none,
    this.flowControl = FlowControl.none,
    this.dtr,
    this.rts,
  });

  /// Speed in bits per second, such as 9600 or 115200.
  final int baudRate;

  /// 5 to 8.
  final int dataBits;

  /// Stop bits after each byte.
  final StopBits stopBits;

  /// Parity bit after the data bits.
  final Parity parity;

  /// How the sides pause each other; see [FlowControl].
  final FlowControl flowControl;

  /// DTR to set when the port opens; null leaves it as the adapter has it.
  ///
  /// Many boards react to it. Native USB boards (Arduino Leonardo, RP2040,
  /// ESP32-S2/S3) often send nothing until DTR is on, while an Arduino Uno
  /// restarts when DTR goes on.
  final bool? dtr;

  /// RTS to set when the port opens; null leaves it as the adapter has it.
  final bool? rts;

  /// Bits on the wire per byte: start bit, data, parity and stop bits.
  double get bitsPerByte =>
      1 +
      dataBits +
      (parity == Parity.none ? 0 : 1) +
      switch (stopBits) {
        StopBits.one => 1,
        StopBits.onePointFive => 1.5,
        StopBits.two => 2,
      };

  /// Throws [SerialException] with [SerialError.invalidArgument] if a value
  /// is out of range.
  void validate() {
    if (baudRate <= 0 || baudRate > 0x7fffffff) {
      throw SerialException(SerialError.invalidArgument,
          'Baud rate must be positive, got $baudRate');
    }
    if (dataBits < 5 || dataBits > 8) {
      throw SerialException(SerialError.invalidArgument,
          'Data bits must be 5 to 8, got $dataBits');
    }
  }

  /// A copy with the given values replaced.
  ///
  /// A null argument keeps the current value, so [dtr] and [rts] cannot be
  /// set back to null this way; create a new [SerialConfig] for that.
  SerialConfig copyWith({
    int? baudRate,
    int? dataBits,
    StopBits? stopBits,
    Parity? parity,
    FlowControl? flowControl,
    bool? dtr,
    bool? rts,
  }) =>
      SerialConfig(
        baudRate: baudRate ?? this.baudRate,
        dataBits: dataBits ?? this.dataBits,
        stopBits: stopBits ?? this.stopBits,
        parity: parity ?? this.parity,
        flowControl: flowControl ?? this.flowControl,
        dtr: dtr ?? this.dtr,
        rts: rts ?? this.rts,
      );

  @override
  bool operator ==(Object other) =>
      other is SerialConfig &&
      other.baudRate == baudRate &&
      other.dataBits == dataBits &&
      other.stopBits == stopBits &&
      other.parity == parity &&
      other.flowControl == flowControl &&
      other.dtr == dtr &&
      other.rts == rts;

  @override
  int get hashCode =>
      Object.hash(baudRate, dataBits, stopBits, parity, flowControl, dtr, rts);

  /// Like "115200 8N1".
  @override
  String toString() {
    final parityLetter = switch (parity) {
      Parity.none => 'N',
      Parity.odd => 'O',
      Parity.even => 'E',
      Parity.mark => 'M',
      Parity.space => 'S',
    };
    final stop = switch (stopBits) {
      StopBits.one => '1',
      StopBits.onePointFive => '1.5',
      StopBits.two => '2',
    };
    final flow = flowControl == FlowControl.none ? '' : ' ${flowControl.name}';
    return '$baudRate $dataBits$parityLetter$stop$flow';
  }
}
