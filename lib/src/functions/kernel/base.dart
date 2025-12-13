import 'dart:io';

import 'package:meta/meta.dart';

import '/usb_gadget.dart';

/// Types of kernel-based USB gadget functions
enum KernelFunctionType {
  /// Mass storage function (USB flash drive emulation)
  massStorage('mass_storage'),

  /// Serial (CDC ACM) function (virtual serial port)
  acm('acm'),

  /// Generic serial function (non-CDC)
  serial('gser'),

  /// Ethernet (CDC ECM) function
  ecm('ecm'),

  /// Ethernet (CDC ECM Subset) function
  ecmSubset('geth'),

  /// Ethernet (CDC EEM) function
  eem('eem'),

  /// Ethernet (CDC NCM) function
  ncm('ncm'),

  /// RNDIS function (Windows ethernet)
  rndis('rndis'),

  /// HID function (keyboard, mouse, etc.)
  hid('hid'),

  /// MIDI function
  midi('midi'),

  /// Audio (UAC1) function
  uac1('uac1'),

  /// Audio (UAC2) function
  uac2('uac2'),

  /// Video (UVC) function
  uvc('uvc'),

  /// Printer function
  printer('printer'),

  /// Loopback function (for testing)
  loopback('loopback'),

  /// Source/Sink function (for testing)
  sourceSink('sourcesink');

  const KernelFunctionType(this._configfsName);

  /// The name used in configfs paths
  final String _configfsName;

  @override
  String toString() => _configfsName;
}

/// Helper mixin for functions that need to resolve device paths.
mixin DevicePathResolver on KernelFunction {
  /// Resolves a device path from the 'dev' attribute.
  ///
  /// Reads the major:minor device numbers and constructs a path using
  /// the provided prefix. Falls back to checking if the default path exists.
  String? getDevicePath(String devicePrefix, {int defaultMinor = 0}) {
    if (!prepared) return null;
    final defaultPath = '/dev/$devicePrefix$defaultMinor';
    try {
      final devAttr = readAttribute('dev');
      if (devAttr != null) {
        // Parse major:minor format (e.g., "240:0" -> minor=0)
        final parts = devAttr.split(':');
        final minor = int.tryParse(parts.length > 1 ? parts[1] : parts[0]);
        if (minor != null) {
          return '/dev/$devicePrefix$minor';
        }
      }
    } catch (_) {
      // Ignore read errors, fall through to default
    }

    if (File(defaultPath).existsSync()) {
      return defaultPath;
    }

    return null;
  }
}

/// Base class for kernel-implemented USB gadget functions.
abstract class KernelFunction extends GadgetFunction with USBGadgetLogger {
  KernelFunction({required super.name, required this.kernelType});

  @override
  GadgetFunctionType get type => .kernel;

  /// The type of kernel function (mass_storage, acm, ecm, etc.)
  final KernelFunctionType kernelType;

  /// The function path in configfs
  String? _functionPath;

  /// The function path in configfs (non-null after preparation)
  String get functionPath => _functionPath!;

  /// Whether the function has been prepared
  bool get prepared => _functionPath != null;

  @override
  String get configfsName => '${kernelType._configfsName}.$name';

  /// Returns the attributes to be written to configfs.
  @protected
  Map<String, String> getConfigAttributes();

  /// Validates the function configuration before binding.
  @protected
  bool validate() => true;

  @override
  Future<void> prepare(String path) async {
    if (prepared) {
      throw StateError('Function already prepared');
    }
    _functionPath = path;
    if (!validate()) {
      throw StateError('Function configuration validation failed');
    }
    log?.info('Preparing kernel function: $path');
    final functionDir = Directory(functionPath);
    if (!functionDir.existsSync()) {
      throw FileSystemException(
        'Function directory does not exist. Kernel module for '
        '${kernelType._configfsName} may not be loaded.',
        _functionPath,
      );
    }
    final attributes = getConfigAttributes();
    if (attributes.isNotEmpty) {
      log?.debug('Writing ${attributes.length} attributes...');
      for (final entry in attributes.entries) {
        writeAttribute(entry.key, entry.value);
      }
    }
  }

  /// Only for FunctionFs-based functions; not needed for kernel functions.
  /// Returns immediately.
  @override
  Future<void> waitState(_) => .value();

  @override
  @mustCallSuper
  Future<void> dispose() async {
    if (!prepared) return;
    log?.info('Disposing kernel function');
    _functionPath = null;
  }

  /// Writes a single attribute to the function directory.
  void writeAttribute(String name, String value, {String? path}) {
    final attrPath = '${path ?? functionPath}/$name';
    log?.debug('Setting attribute: $name=$value');
    try {
      File(attrPath).writeAsStringSync(value);
    } on FileSystemException catch (e) {
      throw FileSystemException(
        'Failed to write attribute "$name": ${e.message}',
        attrPath,
        e.osError,
      );
    }
  }

  /// Reads an attribute from the function directory.
  String? readAttribute(String name, {String? path}) {
    final attrPath = '${path ?? functionPath}/$name';
    try {
      return File(attrPath).readAsStringSync().trim();
    } on FileSystemException catch (e) {
      log?.error('Failed to read attribute: $name (${e.message})');
    }
    return null;
  }
}
