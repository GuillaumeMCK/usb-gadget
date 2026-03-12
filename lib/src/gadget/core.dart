import 'dart:async';
import 'dart:io';

import '/src/logger/logger.dart';
import '/usb_gadget.dart';

part 'fs.dart';

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

/// A complete USB device definition.
///
/// Call [register] to create the configfs structure, or [bind] to register
/// and immediately attach to a UDC. Fields left at their defaults use the
/// kernel's built-in values.
///
/// ```dart
/// final gadget = Gadget(
///   id: Id(0x1234, 0x5678),
///   class_: .interfaceSpecific(),
///   strings: {
///     .enUS: GadgetStrings(
///       manufacturer: 'My Company',
///       product: 'My Device',
///       serialnumber: '123456',
///     ),
///   },
///   configs: [
///     Config('My config', functions: [myFunction]),
///   ],
/// );
///
/// final reg = await gadget.bind(udc);
/// try {
///   // Device is active.
/// } finally {
///   await reg.remove();
/// }
/// ```
final class Gadget with USBGadgetLogger {
  /// Creates a USB gadget definition.
  ///
  /// At least one entry in [configs] is required before calling [register]
  /// or [bind]. If [name] is omitted, one is auto-generated (e.g.
  /// `usb-gadget0`). [logLevel] controls verbosity of the internal logger.
  Gadget({
    required this.id,
    this.class_ = const Class.interfaceSpecific(),
    this.configs = const [],
    Map<USBLanguageId, GadgetStrings>? strings,
    this.name,
    this.deviceRelease = 0x0000,
    this.usbVersion = .v20,
    LogLevel? logLevel,
  }) : strings = {...?strings},
       assert(name == null || name.isNotEmpty, 'name cannot be empty') {
    Logger.init(level: logLevel);
  }

  /// Optional fixed name for this gadget in configfs.
  ///
  /// When `null`, a unique name is generated during [register].
  final String? name;

  /// USB Vendor and Product ID.
  final Id id;

  /// USB device class.
  ///
  /// Use [Class.interfaceSpecific] for composite devices where each interface
  /// defines its own class.
  final Class class_;

  /// Device release number in BCD format (`0xJJMN`: major, minor, sub-minor).
  ///
  /// For example, `0x0100` is v1.0 and `0x0210` is v2.1.0.
  final int deviceRelease;

  /// USB specification version.
  final UsbVersion usbVersion;

  /// String descriptors indexed by language ID.
  final Map<USBLanguageId, GadgetStrings> strings;

  /// USB configurations. At least one is required before calling [register] or [bind].
  final List<Config> configs;

  /// Creates the configfs directory structure and writes all descriptors,
  /// without binding to a UDC.
  ///
  /// Returns a [RegGadget] that owns the created structure. Call
  /// [RegGadget.remove] to unbind and tear it down.
  ///
  /// Throws a [StateError] if [configs] is empty, or a [FileSystemException]
  /// if any configfs operation fails.
  Future<RegGadget> register() async {
    if (configs.isEmpty) {
      throw StateError('USB gadget must have at least one configuration');
    }
    final dir = _resolveGadgetDir(name);
    log?.info('Registering gadget at ${dir.path}');
    return _register(this, dir);
  }

  /// Registers the gadget and immediately binds it to [udc].
  ///
  /// Equivalent to calling [register] then [RegGadget.bind]. If binding
  /// fails, the partially registered gadget is cleaned up before rethrowing.
  ///
  /// Throws a [StateError] if [configs] is empty, or a [FileSystemException]
  /// if any configfs operation fails.
  Future<RegGadget> bind([Udc? udc]) async {
    final reg = await register();
    try {
      await reg.bind(udc);
    } catch (_) {
      await reg.remove();
      rethrow;
    }
    return reg;
  }

  /// Finds or creates the configfs directory for this gadget.
  ///
  /// When [name] is null, increments a counter suffix until a free slot is
  /// found (e.g. `usb-gadget0`, `usb-gadget1`, …).
  static Directory _resolveGadgetDir(String? name) {
    const base = '/sys/kernel/config/usb_gadget';
    if (name != null) {
      final dir = Directory('$base/$name');
      dir.createSync();
      return dir;
    }
    for (var i = 0; ; i++) {
      final dir = Directory('$base/usb-gadget$i');
      try {
        dir.createSync();
        return dir;
      } on FileSystemException catch (e) {
        if (e.osError?.errorCode != Errno.eexist) rethrow;
      }
    }
  }

  static Future<RegGadget> _register(Gadget gadget, Directory dir) async {
    _writeAttr('${dir.path}/bDeviceClass', gadget.class_.classCode.toHex());
    _writeAttr('${dir.path}/bDeviceSubClass', gadget.class_.subClass.toHex());
    _writeAttr('${dir.path}/bDeviceProtocol', gadget.class_.protocol.toHex());
    _writeAttr('${dir.path}/idVendor', gadget.id.vendor.toHex());
    _writeAttr('${dir.path}/idProduct', gadget.id.product.toHex());
    _writeAttr('${dir.path}/bcdDevice', gadget.deviceRelease.toHex());
    _writeAttr('${dir.path}/bcdUSB', gadget.usbVersion.value.toHex());

    for (final MapEntry(:key, :value) in gadget.strings.entries) {
      final langPath = '${dir.path}/strings/${key.value.toHex()}';
      Directory(langPath).createSync();
      _writeAttr('$langPath/serialnumber', value.serialnumber);
      _writeAttr('$langPath/manufacturer', value.manufacturer);
      _writeAttr('$langPath/product', value.product);
    }

    final reg = RegGadget._(dir);

    // Deduplicate functions across configs, preserving order.
    final uniqueFns = <GadgetFunction>[];
    for (final fn in gadget.configs.expand((c) => c.functions)) {
      if (!uniqueFns.contains(fn)) uniqueFns.add(fn);
    }

    // Create and prepare function directories.
    // configfsName is the full directory name, e.g. "ffs.adb" or "mass_storage.storage".
    final fnPaths = <GadgetFunction, String>{};
    for (final fn in uniqueFns) {
      final fnPath = '${dir.path}/functions/${fn.configfsName}';
      Directory(fnPath).createSync();
      try {
        fn.prepare(fnPath);
      } catch (_) {
        await reg._doRemove();
        rethrow;
      }
      fnPaths[fn] = fnPath;
      reg._functions.add(fn);
    }

    // Create configurations and symlink functions.
    for (final config in gadget.configs) {
      final configPath = '${dir.path}/configs/c.${config.index}';
      Directory(configPath).createSync(recursive: true);

      _writeAttr('$configPath/bmAttributes', config.bmAttributes.toHex());
      _writeAttr('$configPath/MaxPower', config.maxPower.toString());

      // Write default description for default language, then any overrides.
      final allStrings = {
        USBLanguageId.enUS: config.description,
        ...config.strings,
      };
      for (final MapEntry(:key, :value) in allStrings.entries) {
        final langPath = '$configPath/strings/${key.value.toHex()}';
        Directory(langPath).createSync(recursive: true);
        _writeAttr('$langPath/configuration', value);
      }

      for (final fn in config.functions) {
        final link = Link('$configPath/${fn.configfsName}');
        if (link.existsSync()) link.deleteSync();
        link.createSync(fnPaths[fn]!);
      }
    }

    // Wait for FFS functions to become ready.
    for (final fn in reg._functions) {
      if (fn.type == .ffs) {
        await fn.awaitState(.ready);
      }
    }
    return reg;
  }
}

/// A registered function instance within a USB gadget.
///
/// Returned by [RegGadget.functions] to describe each entry inside
/// the `functions/` directory in configfs.
class RegFunction {
  const RegFunction({required this.driver, required this.instance});

  /// Function driver name (e.g. `acm`, `ecm`, `mass_storage`).
  final String driver;

  /// Instance name (e.g. `usb-gadget0-0`).
  final String instance;

  @override
  String toString() => '$driver.$instance';
}

/// A USB gadget registered with the system.
///
/// Obtained via [Gadget.register] or [Gadget.bind]. This object owns the
/// configfs structure: call [remove] to unbind and clean up, or [detach] to
/// relinquish ownership and keep the gadget active after this handle is
/// discarded.
///
/// Use [RegGadget.all] to enumerate all gadgets currently on the system.
class RegGadget with USBGadgetLogger {
  RegGadget._(this._dir);

  final Directory _dir;

  /// Whether [remove] will tear down the gadget.
  ///
  /// Starts as `true`; set to `false` by [detach] to keep the gadget alive
  /// after this object is no longer used.
  bool isAttached = true;

  /// Name of this gadget in configfs.
  String get name => _dir.path.split('/').last;

  /// Absolute configfs path of this gadget.
  String get path => _dir.path;

  /// Name of the UDC this gadget is bound to, or `null` if unbound.
  String? get udc {
    final f = File('${_dir.path}/UDC');
    if (!f.existsSync()) return null;
    final s = f.readAsStringSync().trim();
    return s.isEmpty ? null : s;
  }

  /// Returns all USB gadgets currently present in configfs.
  ///
  /// Includes gadgets created outside of this program.
  ///
  /// ```dart
  /// for (final g in RegGadget.all()) {
  ///   print('${g.name}  udc: ${g.udc ?? "(unbound)"}');
  /// }
  /// ```
  static List<RegGadget> all() {
    final dir = Directory('/sys/kernel/config/usb_gadget');
    if (!dir.existsSync()) return [];
    return [
      for (final e in dir.listSync())
        if (e is Directory) RegGadget._(e),
    ];
  }

  /// Binds this gadget to [udc], or unbinds it when [udc] is `null`.
  ///
  /// Throws a [FileSystemException] if writing to the UDC file fails.
  Future<void> bind(Udc? udc) async {
    log?.debug(
      udc != null ? 'Binding to UDC: ${udc.name}' : 'Unbinding from UDC',
    );
    try {
      File('${_dir.path}/UDC').writeAsStringSync(udc?.name ?? '');
    } catch (err) {
      throw FileSystemException('Failed to bind gadget to UDC: $err');
    }
  }

  /// Unbinds every gadget currently present in configfs.
  ///
  /// The configfs structure is left intact; gadgets can be re-bound
  /// afterwards by calling [bind].
  ///
  /// ```dart
  /// await RegGadget.unbindAll();
  /// ```
  static Future<void> unbindAll() async {
    for (final g in all()) {
      try {
        await g.bind(null);
      } catch (_) {}
    }
  }

  /// Polls the UDC state file until the device reaches [target].
  ///
  /// Useful for waiting until the host has fully enumerated the device
  /// before starting data transfers. [pollInterval] controls how often the
  /// state file is read (default: 100 ms) and [timeout] sets the maximum
  /// wait (default: 5 s).
  ///
  /// Throws a [StateError] if the gadget is not bound to a UDC or the state
  /// file is missing, and a [TimeoutException] if [target] is not reached
  /// within [timeout].
  ///
  /// ```dart
  /// await reg.awaitState(DeviceState.configured);
  /// ```
  Future<void> awaitState(
    DeviceState target, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final boundUdc = udc;
    if (boundUdc == null) throw StateError('Gadget is not bound to any UDC');

    final stateFile = File('/sys/class/udc/$boundUdc/state');
    if (!stateFile.existsSync()) {
      throw StateError('UDC state file not found: ${stateFile.path}');
    }

    final deadline = DateTime.now().add(timeout);
    while (true) {
      final state = DeviceState.fromString(stateFile.readAsStringSync().trim());
      if (state == target) return;
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'Timeout waiting for "${target.value}". Current: ${state.value}',
          timeout,
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// The current USB device state.
  ///
  /// Returns [DeviceState.notAttached] when the gadget is unbound or
  /// the state file cannot be read.
  DeviceState get currentState {
    if (udc == null) return .notAttached;
    final f = File('/sys/class/udc/$udc/state');
    if (!f.existsSync()) return .notAttached;
    return .fromString(f.readAsStringSync().trim());
  }

  /// A stream that emits [DeviceState] values as the UDC state changes.
  ///
  /// The stream completes when the gadget is unbound from its UDC.
  /// [pollInterval] controls how often the state file is sampled (default: 50 ms).
  ///
  /// ```dart
  /// reg.stateStream().listen((state) {
  ///   if (state == DeviceState.configured) {
  ///     // Ready to transfer data.
  ///   }
  /// });
  /// ```
  Stream<DeviceState> stateStream({
    Duration pollInterval = const Duration(milliseconds: 50),
  }) async* {
    DeviceState? last;
    while (udc != null) {
      final s = currentState;
      if (s != last) yield last = s;
      await Future<void>.delayed(pollInterval);
    }
  }

  /// All function instances registered in this gadget.
  ///
  /// Scans the `functions/` directory in configfs and parses each entry as
  /// `driver.instance` (e.g. `hid.usb-gadget0-0`).
  List<RegFunction> functions() {
    final dir = Directory('${_dir.path}/functions');
    if (!dir.existsSync()) return [];
    return [
      for (final e in dir.listSync())
        if (e is Directory) ?_parseFunction(e.path.split('/').last),
    ];
  }

  /// Relinquishes ownership of the gadget, making [remove] a no-op.
  ///
  /// The gadget remains registered in configfs until removed by other
  /// means (e.g. [unbindAll]).
  void detach() => isAttached = false;

  /// Unbinds and removes this gadget from configfs.
  ///
  /// Releases all functions, deletes all symlinks, subdirectories, and the
  /// gadget directory itself. Does nothing if [isAttached] is `false`.
  Future<void> remove() async {
    if (!isAttached) return;
    await _doRemove();
  }

  final List<GadgetFunction> _functions = [];

  Future<void> _doRemove() async {
    for (final fn in _functions) {
      try {
        await fn.release();
      } catch (err) {
        log?.warn('Failed to release ${fn.name}:', err);
      }
    }
    try {
      File('${_dir.path}/UDC').writeAsStringSync('');
    } catch (_) {}
    _removeAt(_dir);
    detach();
  }

  @override
  String toString() => 'RegGadget($name, udc: $udc)';
}
