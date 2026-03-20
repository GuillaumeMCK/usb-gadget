import '/src/gadget/fs.dart';
import 'base.dart';

/// Mass storage function (USB flash drive emulation).
class MassStorageFunction extends KernelFunction {
  MassStorageFunction({
    required super.name,
    required this.luns,
    this.stall = true,
  }) : super(kernelType: .massStorage);

  /// Logical Unit Numbers (LUNs) configuration.
  final List<LunConfig> luns;

  /// Whether to support STALL (halt bulk endpoints on errors).
  final bool stall;

  /// Tracks lun.1+ dirs created in [prepare] so [release] can sweep them.
  /// lun.0 is kernel-default and must not be removed.
  ConfigFsTree? _lunTree;

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
    _lunTree = ConfigFsTree();
    for (var i = 0; i < luns.length; i++) {
      final lun = luns[i];
      final lunPath = '$functionPath/lun.$i';
      log?.info('Configuring LUN $i');
      // lun.0 is kernel-default; only track dirs we actually create.
      if (i > 0) _lunTree!.mkdirp(lunPath);
      if (lun.path != null) writeAttribute('file', lun.path!, path: lunPath);
      if (lun.cdrom) writeAttribute('cdrom', '1', path: lunPath);
      if (lun.ro) writeAttribute('ro', '1', path: lunPath);
      if (lun.removable) writeAttribute('removable', '1', path: lunPath);
      if (lun.nofua) writeAttribute('nofua', '1', path: lunPath);
    }
  }

  /// Updates the backing file for a specific LUN.
  void updateLunFile(int lunIndex, String? filePath) {
    _assertPrepared(lunIndex);
    writeAttribute('file', filePath ?? '', path: '$functionPath/lun.$lunIndex');
  }

  /// Forces ejection of a LUN (simulates media removal).
  void ejectLun(int lunIndex) {
    _assertPrepared(lunIndex);
    writeAttribute('forced_eject', '', path: '$functionPath/lun.$lunIndex');
  }

  /// Gets the current backing file path for a LUN.
  String? getLunFile(int lunIndex) {
    if (!prepared || lunIndex >= luns.length) return null;
    return readAttribute('file', path: '$functionPath/lun.$lunIndex');
  }

  @override
  Future<void> release() async {
    if (isReleased) return;
    _lunTree?.sweep();
    _lunTree = null;
    await super.release();
  }

  void _assertPrepared(int lunIndex) {
    if (!prepared) throw StateError('Function not prepared yet');
    if (lunIndex >= luns.length) {
      throw RangeError('LUN index out of range: $lunIndex >= ${luns.length}');
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

  /// Path to the backing file or block device (e.g., /dev/sda, disk.img).
  final String? path;

  /// Whether this LUN should appear as a CD-ROM drive.
  final bool cdrom;

  /// Whether this LUN is read-only.
  final bool ro;

  /// Whether this LUN should report as removable media.
  final bool removable;

  /// Whether to disable Force Unit Access (improves performance but may risk data loss).
  final bool nofua;
}
