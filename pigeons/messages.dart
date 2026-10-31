// Contract between Dart and the native side. Regenerate after editing:
//   dart run pigeon --input pigeons/messages.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartPackageName: 'usb_serial_next',
    kotlinOut:
        'android/src/main/kotlin/io/github/zalexei/usb_serial_next/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'io.github.zalexei.usb_serial_next'),
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
/// Driver families of usb-serial-for-android.
enum NativeDriver { cdcAcm, ftdi, cp21xx, ch34x, prolific, gsmModem, chromeCcd }

enum NativeParity { none, odd, even, mark, space }

enum NativeStopBits { one, onePointFive, two }

enum NativeFlowControl { none, rtsCts, dtrDsr, xonXoff, xonXoffInline }

/// A device on the USB bus, serial or not.
class NativeUsbDevice {
  NativeUsbDevice({
    required this.deviceName,
    required this.deviceId,
    required this.vendorId,
    required this.productId,
    required this.portCount,
    required this.hasPermission,
  });

  /// Key of the device while it stays plugged in, like /dev/bus/usb/001/002.
  String deviceName;
  int deviceId;
  int vendorId;
  int productId;
  String? manufacturerName;
  String? productName;

  /// Null until the app has permission for the device (Android 10+).
  String? serialNumber;

  /// Null when no driver knows the device.
  NativeDriver? driver;

  /// Serial ports of the device; 0 when [driver] is null.
  int portCount;
  bool hasPermission;
}

class NativePortConfig {
  NativePortConfig({
    required this.baudRate,
    required this.dataBits,
    required this.stopBits,
    required this.parity,
    required this.flowControl,
  });

  int baudRate;
  int dataBits;
  NativeStopBits stopBits;
  NativeParity parity;
  NativeFlowControl flowControl;

  /// Null leaves the line as the adapter has it.
  bool? dtr;
  bool? rts;
}

class NativeOpenRequest {
  NativeOpenRequest({
    required this.deviceName,
    required this.portIndex,
    required this.config,
  });

  String deviceName;
  int portIndex;

  /// Forces a driver for a device the prober does not know.
  NativeDriver? driver;
  NativePortConfig config;
}

/// State of the modem control lines; null means the chip does not report it.
class NativeControlLines {
  bool? rts;
  bool? cts;
  bool? dtr;
  bool? dsr;
  bool? cd;
  bool? ri;
}

/// Errors come back as PlatformException with one of these codes:
/// permission_denied, device_not_found, unsupported_device, disconnected,
/// port_closed, busy, invalid_argument, unsupported_operation, timeout,
/// io_error.
@HostApi()
abstract class UsbSerialHostApi {
  /// Closes every port this engine opened before: after a hot restart the
  /// Dart side no longer knows about them.
  void reset();

  List<NativeUsbDevice> listDevices();

  bool hasPermission(String deviceName);

  /// Shows the system dialog unless the app already has permission.
  @async
  bool requestPermission(String deviceName);

  /// The device whose USB_DEVICE_ATTACHED intent started the activity.
  NativeUsbDevice? launchDevice();

  /// Returns the id of the opened port.
  @async
  int open(NativeOpenRequest request);

  /// [timeoutMs] 0 waits forever.
  @async
  void write(int portId, Uint8List data, int timeoutMs);

  @async
  void setConfig(int portId, NativePortConfig config);

  @async
  void setDtr(int portId, bool value);

  @async
  void setRts(int portId, bool value);

  @async
  NativeControlLines getControlLines(int portId);

  @async
  void setBreak(int portId, bool value);

  @async
  void purge(int portId, bool output, bool input);

  /// Does nothing if the port is already closed.
  @async
  void close(int portId);
}

@FlutterApi()
abstract class UsbSerialFlutterApi {
  void onData(int portId, Uint8List data);

  /// Sent once per port. [errorCode] is null after a normal close.
  void onPortClosed(int portId, String? errorCode, String? errorMessage);

  void onDeviceAttached(NativeUsbDevice device);

  void onDeviceDetached(NativeUsbDevice device);
}
