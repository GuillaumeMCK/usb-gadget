import 'dart:async';
import 'dart:io';

import '/src/logger/logger.dart';
import '/usb_gadget.dart';
import 'fs.dart';

/// A complete USB device definition.
///
/// Call [register] to create the configfs structure, then [RegGadget.bind] to
/// attach to a UDC. Fields left at their defaults use the kernel's built-in values.
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
  /// or [RegGadget.bind]. If [name] is omitted, one is auto-generated (e.g.
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

  /// USB configurations. At least one is required before calling [register] or [RegGadget.bind].
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

  /// Removes all configfs registrations that match this gadget's [name].
  ///
  /// Finds every [RegGadget] in configfs whose name equals [name] and calls
  /// [RegGadget.remove] on each one. Useful when you no longer hold a
  /// reference to the original [RegGadget] handles.
  ///
  /// Throws a [FileSystemException] if any configfs operation fails.
  Future<void> remove() async {
    final gadgets = RegGadget.all().where((g) => g.name == name);
    for (final reg in gadgets) {
      await reg.remove();
    }
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
      if (dir.existsSync()) continue; // skip occupied auto-numbered slots
      try {
        dir.createSync();
        return dir;
      } on FileSystemException catch (e) {
        if (e.osError?.errorCode != eexist) rethrow;
      }
    }
  }

  static Future<RegGadget> _register(Gadget gadget, Directory dir) async {
    writeAttr('${dir.path}/bDeviceClass', gadget.class_.code.toHex());
    writeAttr('${dir.path}/bDeviceSubClass', gadget.class_.subClass.toHex());
    writeAttr('${dir.path}/bDeviceProtocol', gadget.class_.protocol.toHex());
    writeAttr('${dir.path}/idVendor', gadget.id.vendor.toHex());
    writeAttr('${dir.path}/idProduct', gadget.id.product.toHex());
    writeAttr('${dir.path}/bcdDevice', gadget.deviceRelease.toHex());
    writeAttr('${dir.path}/bcdUSB', gadget.usbVersion.value.toHex());

    for (final MapEntry(:key, :value) in gadget.strings.entries) {
      final langPath = '${dir.path}/strings/${key.value.toHex()}';
      Directory(langPath).createSync();
      writeAttr('$langPath/serialnumber', value.serialnumber);
      writeAttr('$langPath/manufacturer', value.manufacturer);
      writeAttr('$langPath/product', value.product);
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
      try {
        Directory(fnPath).createSync();
        await fn.prepare(fnPath);
      } catch (_) {
        await reg._doRemove();
        rethrow;
      }
      fnPaths[fn] = fnPath;
      reg._functions.add(fn);
    }

    // Create configurations and symlink functions.
    try {
      for (final config in gadget.configs) {
        final configPath = '${dir.path}/configs/c.${config.index}';
        Directory(configPath).createSync(recursive: true);

        writeAttr('$configPath/bmAttributes', config.bmAttributes.toHex());
        writeAttr('$configPath/MaxPower', config.maxPower.value.toString());

        // Write default description for default language, then any overrides.
        final allStrings = {
          USBLanguageId.enUS: config.description,
          ...config.strings,
        };
        for (final MapEntry(:key, :value) in allStrings.entries) {
          final langPath = '$configPath/strings/${key.value.toHex()}';
          Directory(langPath).createSync(recursive: true);
          writeAttr('$langPath/configuration', value);
        }

        for (final fn in config.functions) {
          final link = Link('$configPath/${fn.configfsName}');
          if (link.existsSync()) link.deleteSync();
          link.createSync(fnPaths[fn]!);
        }
      }
    } catch (_) {
      await reg._doRemove();
      rethrow;
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

  factory RegFunction.fromName(String name) {
    final list = name.split('.');
    if (list.length != 2) {
      throw Exception('Invalid function name: $name');
    }
    final [driver, instance] = list;
    return RegFunction(driver: driver, instance: instance);
  }

  /// Function driver name (e.g. `acm`, `ecm`, `mass_storage`).
  final String driver;

  /// Instance name (e.g. `usb-gadget0-0`).
  final String instance;

  @override
  String toString() => '$driver.$instance';
}

/// A USB gadget registered with the system.
///
/// Obtained via [Gadget.register] or [RegGadget.bind]. This object owns the
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
  UDC? get udc {
    final f = File('${_dir.path}/UDC');
    if (!f.existsSync()) return null;
    final s = f.readAsStringSync().trim();

    if (s.isEmpty) return null;
    return UDC.fromName(s);
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
  void bind(UDC? udc) {
    log?.debug(
      udc != null ? 'Binding to UDC: ${udc.name}' : 'Unbinding from UDC',
    );
    try {
      File('${_dir.path}/UDC').writeAsStringSync(udc?.name ?? '');
    } catch (err) {
      throw FileSystemException('Failed to bind gadget to UDC: $err');
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
        if (e case Directory(:final path)) .fromName(path.split('/').last),
    ];
  }

  /// Relinquishes ownership of the gadget, making [remove] a no-op.
  void detach() => isAttached = false;

  /// Unbinds and removes this gadget from configfs.
  ///
  /// Releases all functions, deletes all symlinks, subdirectories, and the
  /// gadget directory itself. Does nothing if [isAttached] is `false`.
  Future<void> remove() async {
    if (isAttached == false) return;
    await _doRemove();
  }

  final List<GadgetFunction> _functions = [];

  Future<void> _doRemove() async {
    try {
      File('${_dir.path}/UDC').writeAsStringSync('');
    } catch (_) {}
    for (final fn in _functions) {
      try {
        await fn.release();
      } catch (err) {
        log?.warn('Failed to release ${fn.name}:', err);
      }
    }
    // The kernel may still be cleaning up pseudo-dirs (e.g. os_desc, lun.0)
    // asynchronously after UDC unbind. Retry removeAt a few times with a
    // short delay so those entries disappear before we attempt rmdir.
    for (var attempt = 0; attempt < 5; attempt++) {
      removeAt(_dir);
      if (!_dir.existsSync()) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    detach();
  }

  @override
  String toString() => 'RegGadget($name, udc: $udc)';
}
