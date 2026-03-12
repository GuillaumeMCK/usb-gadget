import 'dart:async';
import 'dart:io';

import '/usb_gadget.dart';

/// The lifecycle states of a USB device as reported by the Linux USB Gadget
/// framework through sysfs (`/sys/class/udc/{udc}/state`).
enum DeviceState {
  /// No USB cable is connected.
  notAttached('not-attached'),

  /// A USB cable is connected but the device has not been enumerated by the host.
  attached('attached'),

  /// The host is providing power to the device.
  powered('powered'),

  /// The device is being enumerated by the host (initial handshake phase).
  default_('default'),

  /// The device has been assigned a USB address by the host.
  addressed('addressed'),

  /// The device is fully configured and ready for data transfer.
  configured('configured'),

  /// The device has been suspended by the host to save power.
  suspended('suspended');

  const DeviceState(this.value);

  /// The string value as it appears in the UDC state file.
  final String value;

  /// Returns the [DeviceState] matching [state], or [defaultValue] if none match.
  static DeviceState fromString(
    String state, {
    DeviceState defaultValue = .notAttached,
  }) => values.firstWhere((e) => e.value == state, orElse: () => defaultValue);
}

/// A USB Device Controller (UDC) discovered under `/sys/class/udc/`.
final class UDC {
  const UDC._(this._dir);

  /// Creates an UDC from its kernel name (e.g. `dwc2`).
  UDC.fromName(String name) : _dir = Directory('/sys/class/udc/$name');

  final Directory _dir;

  /// The kernel name of this UDC (e.g. `dwc2`, `musb-hdrc.0`).
  String get name => _dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);

  /// Whether the A-device supports HNP on an alternate port.
  Future<bool> get aAltHnpSupport => _readBool('a_alt_hnp_support');

  /// Whether the A-device supports HNP.
  Future<bool> get aHnpSupport => _readBool('a_hnp_support');

  /// Whether B-device HNP has been enabled by the host.
  Future<bool> get bHnpEnable => _readBool('b_hnp_enable');

  /// Whether this device is operating as an OTG A-peripheral.
  Future<bool> get isAPeripheral => _readBool('is_a_peripheral');

  /// Whether this controller supports OTG.
  Future<bool> get isOtg => _readBool('is_otg');

  /// The speed currently negotiated with the host.
  Future<Speed> get currentSpeed =>
      _read('current_speed').then(Speed.fromString);

  /// The maximum speed this controller supports.
  Future<Speed> get maxSpeed => _read('maximum_speed').then(Speed.fromString);

  /// The current [DeviceState] as reported by the kernel.
  Future<DeviceState> get state => _read('state').then(DeviceState.fromString);

  /// The gadget driver currently bound to this UDC, or `null` if none.
  Future<String?> get function async {
    final s = await _read('function');
    return s.isEmpty ? null : s;
  }

  /// The kernel driver name (e.g. `dwc2`), or `null` if unresolvable.
  String? get driver {
    try {
      final target = Link(
        '${_dir.path}/device/driver',
      ).resolveSymbolicLinksSync();
      return target.split('/').lastWhere((s) => s.isNotEmpty, orElse: () => '');
    } catch (_) {
      return null;
    }
  }

  /// Initiates a Session Request Protocol (SRP) to wake a suspended host.
  Future<void> startSrp() => _write('srp', '1');

  /// Signals the host that this device is present and ready to enumerate.
  Future<void> connect() => _write('soft_connect', 'connect');

  /// Signals the host that this device has disconnected.
  Future<void> disconnect() => _write('soft_connect', 'disconnect');

  /// Polls the UDC state until it reaches [target].
  ///
  /// [pollInterval] controls how often the state is sampled (default: 100 ms)
  /// and [timeout] sets the maximum wait (default: 5 s).
  ///
  /// Throws a [TimeoutException] if [target] is not reached within [timeout].
  ///
  /// ```dart
  /// await udc.awaitState(DeviceState.configured);
  /// ```
  Future<void> awaitState(
    DeviceState target, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (await state == target) return;
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'Timeout waiting for "${target.value}". Current: ${(await state).value}',
          timeout,
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// A stream that emits each [DeviceState] change on this UDC.
  ///
  /// The stream runs indefinitely; cancel the subscription when done.
  /// [pollInterval] controls how often the state is sampled (default: 50 ms).
  ///
  /// ```dart
  /// udc.stateStream().listen((state) {
  ///   if (state == DeviceState.configured) {
  ///     // Ready to transfer data.
  ///   }
  /// });
  /// ```
  Stream<DeviceState> stateStream({
    Duration pollInterval = const Duration(milliseconds: 50),
  }) async* {
    DeviceState? last;
    while (true) {
      final s = await state;
      if (s != last) yield last = s;
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<String> _read(String attr) =>
      File('${_dir.path}/$attr').readAsString().then((s) => s.trim());

  Future<bool> _readBool(String attr) => _read(attr).then((s) => s != '0');

  Future<void> _write(String attr, String value) =>
      File('${_dir.path}/$attr').writeAsString(value);

  @override
  String toString() => 'Udc($name)';
}

/// Get the default (first) UDC, or throw a StateError
UDC get defaultUDC => UDCs.firstOrNull ?? (throw StateError('No UDCs found'));

/// Returns bool if any UDC is present.
bool get hasUDC => UDCs.isNotEmpty;

/// Returns all UDCs available under `/sys/class/udc/`.
List<UDC> get UDCs {
  final dir = Directory('/sys/class/udc');
  if (!dir.existsSync()) return [];
  return [
    for (final e in dir.listSync())
      if (e is Directory) UDC._(e),
  ];
}
