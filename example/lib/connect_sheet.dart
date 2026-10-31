import 'package:flutter/material.dart';
import 'package:usb_serial_next/usb_serial_next.dart';

/// What the user picked in [ConnectSheet].
class ConnectChoice {
  const ConnectChoice(this.config, this.portIndex, this.driver);

  final SerialConfig config;
  final int portIndex;
  final UsbSerialDriver? driver;
}

/// Line settings before opening a port.
class ConnectSheet extends StatefulWidget {
  const ConnectSheet({super.key, required this.device});

  final UsbDevice device;

  @override
  State<ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<ConnectSheet> {
  static const _baudRates = [
    300, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400, //
    460800, 921600, 1000000, 2000000,
  ];

  var _config = const SerialConfig(dtr: true, rts: false);
  var _portIndex = 0;
  UsbSerialDriver? _driver;

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              device.productName ?? device.vidPid,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _row(
              'Baud rate',
              DropdownButton<int>(
                value: _config.baudRate,
                items: [
                  for (final rate in _baudRates)
                    DropdownMenuItem(value: rate, child: Text('$rate')),
                ],
                onChanged: (rate) =>
                    setState(() => _config = _config.copyWith(baudRate: rate)),
              ),
            ),
            _segments<int>(
              'Data bits',
              {
                for (final bits in [5, 6, 7, 8]) bits: '$bits',
              },
              _config.dataBits,
              (bits) => _config.copyWith(dataBits: bits),
            ),
            _segments<Parity>(
              'Parity',
              {for (final p in Parity.values) p: p.name},
              _config.parity,
              (parity) => _config.copyWith(parity: parity),
            ),
            _segments<StopBits>(
              'Stop bits',
              const {
                StopBits.one: '1',
                StopBits.onePointFive: '1.5',
                StopBits.two: '2',
              },
              _config.stopBits,
              (stopBits) => _config.copyWith(stopBits: stopBits),
            ),
            _row(
              'Flow control',
              DropdownButton<FlowControl>(
                value: _config.flowControl,
                items: [
                  for (final flow in FlowControl.values)
                    DropdownMenuItem(value: flow, child: Text(flow.name)),
                ],
                onChanged: (flow) => setState(
                  () => _config = _config.copyWith(flowControl: flow),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('DTR on open'),
              subtitle: const Text('Native USB boards need it to send'),
              value: _config.dtr ?? false,
              onChanged: (on) =>
                  setState(() => _config = _config.copyWith(dtr: on)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('RTS on open'),
              value: _config.rts ?? false,
              onChanged: (on) =>
                  setState(() => _config = _config.copyWith(rts: on)),
            ),
            if (device.portCount > 1)
              _segments<int>(
                'Port',
                {for (var i = 0; i < device.portCount; i++) i: '$i'},
                _portIndex,
                null,
                onIndex: (i) => setState(() => _portIndex = i),
              ),
            if (!device.isSerial)
              _row(
                'Driver',
                DropdownButton<UsbSerialDriver?>(
                  value: _driver,
                  hint: const Text('pick one'),
                  items: [
                    for (final driver in UsbSerialDriver.values)
                      DropdownMenuItem(value: driver, child: Text(driver.name)),
                  ],
                  onChanged: (driver) => setState(() => _driver = driver),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.cable),
              label: const Text('Connect'),
              onPressed: device.isSerial || _driver != null
                  ? () => Navigator.of(
                      context,
                    ).pop(ConnectChoice(_config, _portIndex, _driver))
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, Widget control) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [Text(label), control],
  );

  Widget _segments<T extends Object>(
    String label,
    Map<T, String> options,
    T selected,
    SerialConfig Function(T value)? update, {
    void Function(T value)? onIndex,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 4),
          SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [
              for (final MapEntry(:key, :value) in options.entries)
                ButtonSegment(value: key, label: Text(value)),
            ],
            selected: {selected},
            onSelectionChanged: (values) => setState(() {
              if (update != null) _config = update(values.single);
              onIndex?.call(values.single);
            }),
          ),
        ],
      ),
    );
  }
}
