import 'dart:async';

import 'package:flutter/material.dart';
import 'package:usb_serial_next/usb_serial_next.dart';

import 'connect_sheet.dart';
import 'terminal_page.dart';

/// USB devices, updated as they come and go. Tap one to connect.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.usb});

  final UsbSerial usb;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<UsbDevice>? _devices;
  Object? _error;
  StreamSubscription<UsbDeviceEvent>? _events;

  @override
  void initState() {
    super.initState();
    if (!UsbSerial.isSupported) return;
    _events = widget.usb.deviceEvents.listen((_) => _refresh());
    _refresh();
    _openLaunchDevice();
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final devices = await widget.usb.listDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Plugging in a device listed in device_filter.xml starts the app with
  /// it; go straight to the terminal then.
  Future<void> _openLaunchDevice() async {
    final device = await widget.usb.getLaunchDevice();
    if (device != null && mounted) {
      await _connect(device, const SerialConfig(dtr: true), 0, null);
    }
  }

  Future<void> _onTap(UsbDevice device) async {
    final choice = await showModalBottomSheet<ConnectChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ConnectSheet(device: device),
    );
    if (choice == null || !mounted) return;
    await _connect(device, choice.config, choice.portIndex, choice.driver);
  }

  Future<void> _connect(UsbDevice device, SerialConfig config, int portIndex,
      UsbSerialDriver? driver) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final port = await widget.usb.open(device,
          config: config, portIndex: portIndex, driver: driver);
      if (!mounted) {
        await port.close();
        return;
      }
      await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => TerminalPage(port: port)));
      await port.close();
    } on SerialException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_describe(e))));
    } finally {
      _refresh();
    }
  }

  String _describe(SerialException e) => switch (e.error) {
        SerialError.permissionDenied => 'No permission for the device',
        SerialError.busy => 'The port is already in use',
        SerialError.unsupportedDevice =>
          'No driver for this device. Pick one in "Driver" if you know the chip.',
        SerialError.unsupportedOperation =>
          'The chip does not support these settings',
        _ => '${e.error.name}: ${e.message}',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('USB serial'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: UsbSerial.isSupported ? _refresh : null,
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (!UsbSerial.isSupported) {
      return const _Message(
        icon: Icons.phonelink_off,
        title: 'Android only',
        text: 'USB host access works on Android phones and tablets.',
      );
    }
    final error = _error;
    if (error != null) {
      return _Message(
          icon: Icons.error_outline,
          title: 'Could not list devices',
          text: '$error');
    }
    final devices = _devices;
    if (devices == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (devices.isEmpty) {
      return const _Message(
        icon: Icons.usb_off,
        title: 'No USB devices',
        text: 'Connect an Arduino, ESP32 or USB-UART adapter with an OTG '
            'cable. The list updates by itself.',
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        children: [for (final device in devices) _tile(device)],
      ),
    );
  }

  Widget _tile(UsbDevice device) {
    final details = [
      device.vidPid,
      device.driver?.name ?? 'no serial driver',
      if (device.portCount > 1) '${device.portCount} ports',
      if (device.manufacturerName != null) device.manufacturerName!,
    ].join(' · ');
    return ListTile(
      leading: Icon(device.isSerial ? Icons.usb : Icons.device_unknown),
      title: Text(device.productName ?? 'USB device'),
      subtitle: Text(details),
      trailing: device.hasPermission
          ? null
          : const Tooltip(
              message: 'Will ask for permission', child: Icon(Icons.lock)),
      onTap: () => _onTap(device),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
