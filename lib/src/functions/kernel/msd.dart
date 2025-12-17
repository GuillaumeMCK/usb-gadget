import 'dart:io';

import 'base.dart';

/// Mass storage function (USB flash drive emulation).
class MassStorageFunction extends KernelFunction {
  MassStorageFunction({
    required super.name,
    required this.luns,
    this.stall = true,
  }) : super(kernelType: .massStorage);

  /// Logical Unit Numbers (LUNs) configuration
  final List<LunConfig> luns;

  /// Whether to support STALL (halt bulk endpoints on errors)
  final bool stall;

  @override
  bool validate() {
    if (luns.isEmpty) {
      log?.warn('No LUNs configured');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() => {'stall': stall ? '1' : '0'};

  @override
  Future<void> prepare(String path) async {
    await super.prepare(path);
    for (var i = 0; i < luns.length; i++) {
      final lun = luns[i];
      final lunPath = '$functionPath/lun.$i';
      log?.info('Configuring LUN $i');
      Directory(lunPath).createSync(recursive: true);
      if (lun.path != null) {
        _writeLunAttribute(lunPath, 'file', lun.path!);
      }
      if (lun.cdrom) {
        _writeLunAttribute(lunPath, 'cdrom', '1');
      }
      if (lun.ro) {
        _writeLunAttribute(lunPath, 'ro', '1');
      }
      if (lun.removable) {
        _writeLunAttribute(lunPath, 'removable', '1');
      }
      if (lun.nofua) {
        _writeLunAttribute(lunPath, 'nofua', '1');
      }
    }
  }

  void _writeLunAttribute(String lunPath, String name, String value) {
    final attrPath = '$lunPath/$name';
    log?.debug('Setting LUN attribute: $name=$value');
    try {
      File(attrPath).writeAsStringSync(value);
    } on FileSystemException catch (e) {
      throw FileSystemException(
        'Failed to write LUN attribute "$name": ${e.message}',
        attrPath,
        e.osError,
      );
    }
  }

  /// Updates the backing file for a specific LUN.
  void updateLunFile(int lunIndex, String? filePath) {
    if (!prepared) {
      log?.error('Function not prepared');
      throw StateError('Function not prepared yet');
    }
    if (lunIndex >= luns.length) {
      log?.error('LUN index out of range: $lunIndex');
      throw RangeError('LUN index out of range: $lunIndex >= ${luns.length}');
    }
    final lunPath = '$functionPath/lun.$lunIndex';
    _writeLunAttribute(lunPath, 'file', filePath ?? '');
  }

  /// Forces ejection of a LUN (simulates media removal).
  void ejectLun(int lunIndex) {
    if (!prepared) {
      throw StateError('Function not prepared yet');
    }
    if (lunIndex >= luns.length) {
      throw RangeError('LUN index out of range: $lunIndex >= ${luns.length}');
    }
    final lunPath = '$functionPath/lun.$lunIndex';
    _writeLunAttribute(lunPath, 'forced_eject', '');
  }

  /// Gets the current file path for a LUN.
  String? getLunFile(int lunIndex) {
    if (!prepared || lunIndex >= luns.length) {
      return null;
    }
    try {
      final lunPath = '$functionPath/lun.$lunIndex';
      return File('$lunPath/file').readAsStringSync().trim();
    } catch (_) {
      return null;
    }
  }
}

/// Configuration for a mass storage LUN (Logical Unit Number).
class LunConfig {
  const LunConfig({
    this.path,
    this.cdrom = false,
    this.ro = false,
    this.removable = false,
    this.nofua = false,
  });

  /// Path to the backing file or block device (e.g., /dev/sda, disk.img)
  final String? path;

  /// Whether this LUN should appear as a CD-ROM drive
  final bool cdrom;

  /// Whether this LUN is read-only
  final bool ro;

  /// Whether this LUN should report as removable media
  final bool removable;

  /// Whether to disable Force Unit Access (improves performance but may risk data loss)
  final bool nofua;
}
