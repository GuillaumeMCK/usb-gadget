import 'dart:io';

import '/usb_gadget.dart';

/// A USB Device Controller (UDC) discovered under `/sys/class/udc/`.
class Udc {
  Udc._(this._dir);

  final Directory _dir;

  String get name => _dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);

  Future<bool> get aAltHnpSupport => _readBool('a_alt_hnp_support');

  Future<bool> get aHnpSupport => _readBool('a_hnp_support');

  Future<bool> get bHnpEnable => _readBool('b_hnp_enable');

  Future<bool> get isAPeripheral => _readBool('is_a_peripheral');

  Future<bool> get isOtg => _readBool('is_otg');

  Future<Speed> get currentSpeed =>
      _read('current_speed').then((s) => Speed.fromString(s));

  Future<Speed> get maxSpeed =>
      _read('maximum_speed').then((s) => Speed.fromString(s));

  Future<DeviceState> get state =>
      _read('state').then((s) => DeviceState.fromString(s));

  /// Returns null if no gadget driver is bound.
  Future<String?> get function async {
    final s = await _read('function');
    return s.isEmpty ? null : s;
  }

  /// Kernel driver name (e.g. `dwc2`), or null if unresolvable.
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

  Future<void> startSrp() => _write('srp', '1');

  Future<void> setSoftConnect(bool connect) =>
      _write('soft_connect', connect ? 'connect' : 'disconnect');

  Future<String> _read(String attr) =>
      File('${_dir.path}/$attr').readAsString().then((s) => s.trim());

  Future<bool> _readBool(String attr) => _read(attr).then((s) => s != '0');

  Future<void> _write(String attr, String value) =>
      File('${_dir.path}/$attr').writeAsString(value);

  @override
  String toString() => 'Udc($name)';
}

/// All UDCs available under `/sys/class/udc/`.
List<Udc> listUdcs() {
  final dir = Directory('/sys/class/udc');
  if (!dir.existsSync()) return [];
  return [
    for (final e in dir.listSync())
      if (e is Directory) Udc._(e),
  ];
}

/// The alphabetically first UDC, or null if none exist.
Udc? getDefaultUdc() {
  final udcs = listUdcs()..sort((a, b) => a.name.compareTo(b.name));
  return udcs.firstOrNull;
}
