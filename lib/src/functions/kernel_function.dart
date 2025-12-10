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

/// Base class for kernel-implemented USB gadget functions.
///
/// Kernel functions are implemented in the Linux kernel and configured via
/// configfs. They handle all USB protocol details internally.
///
/// Lifecycle:
/// 1. prepare() - Writes configuration attributes to configfs
/// 2. waitReady() - Returns immediately (kernel functions are always ready)
/// 3. dispose() - Performs any cleanup
abstract class KernelFunction extends GadgetFunction {
  KernelFunction({required super.name, required this.kernelType, super.debug});

  @override
  GadgetFunctionType get type => GadgetFunctionType.kernel;

  /// The type of kernel function (mass_storage, acm, ecm, etc.)
  final KernelFunctionType kernelType;

  /// The function path in configfs
  late String _functionPath;

  /// Whether the function has been prepared
  bool _prepared = false;

  @override
  String getConfigfsInstanceName() => '${kernelType._configfsName}.$name';

  /// Returns the attributes to be written to configfs.
  ///
  /// Subclasses must implement this to provide their specific attributes.
  /// Keys are attribute names, values are attribute values.
  @protected
  Map<String, String> getConfigAttributes();

  /// Validates the function configuration before binding.
  ///
  /// Returns true if configuration is valid, false otherwise.
  /// Override in subclasses for function-specific validation.
  @protected
  bool validate() => true;

  @override
  Future<void> prepare(String path) async {
    if (_prepared) {
      throw StateError('Function already prepared');
    }

    // Validate configuration first
    if (!validate()) {
      throw StateError('Function configuration validation failed');
    }

    _functionPath = path;
    log('Preparing kernel function at: $path');

    // Verify function directory exists
    final functionDir = Directory(_functionPath);
    if (!functionDir.existsSync()) {
      throw FileSystemException(
        'Function directory does not exist. '
        'This likely means the kernel module for ${kernelType._configfsName} '
        'is not loaded.',
        _functionPath,
      );
    }

    // Write configuration attributes
    final attributes = getConfigAttributes();
    if (attributes.isNotEmpty) {
      log('Writing ${attributes.length} attribute(s)...');
      for (final entry in attributes.entries) {
        _writeAttribute(entry.key, entry.value);
      }
    }

    // Call subclass hook
    onPrepare();

    _prepared = true;
    log('Kernel function prepared successfully');
  }

  @override
  Future<void> waitState(FunctionFsState state) => Future.value();

  @override
  @mustCallSuper
  Future<void> dispose() async {
    if (!_prepared) {
      return;
    }

    log('Disposing kernel function');
    onDispose();
    _prepared = false;
  }

  /// Writes a single attribute to the function directory.
  void _writeAttribute(String name, String value) {
    final attrPath = '$_functionPath/$name';
    if (debug) {
      log('  $name = $value');
    }
    try {
      File(attrPath).writeAsStringSync(value);
    } on FileSystemException catch (e) {
      throw FileSystemException(
        'Failed to write attribute "$name" to ${kernelType._configfsName}: ${e.message}',
        attrPath,
        e.osError,
      );
    }
  }

  /// Reads an attribute from the function directory.
  @protected
  String readAttribute(String name) {
    final attrPath = '$_functionPath/$name';
    try {
      return File(attrPath).readAsStringSync().trim();
    } on FileSystemException catch (e) {
      throw FileSystemException(
        'Failed to read attribute "$name" from ${kernelType._configfsName}: ${e.message}',
        attrPath,
        e.osError,
      );
    }
  }

  /// Safely reads an attribute, returning null if it doesn't exist.
  @protected
  String? tryReadAttribute(String name) {
    try {
      return readAttribute(name);
    } catch (_) {
      return null;
    }
  }

  /// Updates an attribute value after initial configuration.
  @protected
  void updateAttribute(String name, String value) {
    _writeAttribute(name, value);
  }

  /// Whether the function is prepared
  bool get isPrepared => _prepared;

  /// The function path in configfs
  String get functionPath => _functionPath;

  /// Called after attributes are written during prepare().
  ///
  /// Subclasses can override this to perform additional setup steps
  /// (e.g., creating subdirectories, writing binary data).
  @protected
  void onPrepare() {}

  /// Called during dispose().
  ///
  /// Subclasses can override this to perform cleanup tasks.
  @protected
  void onDispose() {}
}

/// Mass storage function (USB flash drive emulation).
///
/// Presents backing files or block devices as USB mass storage devices (LUNs).
class MassStorageFunction extends KernelFunction {
  MassStorageFunction({
    required super.name,
    required this.luns,
    this.stall = true,
    super.debug,
  }) : super(kernelType: KernelFunctionType.massStorage);

  /// Logical Unit Numbers (LUNs) configuration
  final List<LunConfig> luns;

  /// Whether to support STALL (halt bulk endpoints on errors)
  final bool stall;

  @override
  bool validate() {
    if (luns.isEmpty) {
      log('Warning: No LUNs configured');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() => {'stall': stall ? '1' : '0'};

  @override
  void onPrepare() {
    // Create and configure LUN subdirectories
    for (var i = 0; i < luns.length; i++) {
      final lun = luns[i];
      final lunPath = '$_functionPath/lun.$i';

      log('Configuring LUN $i...');
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
    if (debug) {
      log('  $name = $value');
    }
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
  ///
  /// Can be called after the gadget is bound to dynamically change
  /// the storage backing. Pass null to disconnect the LUN.
  void updateLunFile(int lunIndex, String? filePath) {
    if (!isPrepared) {
      throw StateError('Function not prepared yet');
    }
    if (lunIndex >= luns.length) {
      throw RangeError('LUN index out of range: $lunIndex >= ${luns.length}');
    }

    final lunPath = '$functionPath/lun.$lunIndex';
    _writeLunAttribute(lunPath, 'file', filePath ?? '');
  }

  /// Forces ejection of a LUN (simulates media removal).
  void ejectLun(int lunIndex) {
    if (!isPrepared) {
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
    if (!isPrepared || lunIndex >= luns.length) {
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

/// Serial (CDC ACM) function (virtual serial port).
///
/// Creates a virtual serial port accessible from the host as /dev/ttyACM*
/// and on the device as /dev/ttyGS*.
class AcmFunction extends KernelFunction {
  AcmFunction({required super.name, super.debug})
    : super(kernelType: KernelFunctionType.acm);

  // ACM function has no configurable attributes
  @override
  Map<String, String> getConfigAttributes() => {};

  /// Gets the TTY device path on the device side (e.g., /dev/ttyGS0).
  ///
  /// This is available after the gadget is bound to a UDC.
  /// Returns null if not yet bound or if the attribute is not available.
  String? getTtyDevice() {
    if (!isPrepared) {
      return null;
    }
    try {
      final portNum = readAttribute('port_num');
      return '/dev/ttyGS$portNum';
    } catch (_) {
      return null;
    }
  }
}

/// Generic serial function (non-CDC).
///
/// Creates a simple serial port without CDC ACM protocol overhead.
/// Accessible on the device side as /dev/ttyGS*.
class GenericSerialFunction extends KernelFunction {
  GenericSerialFunction({required super.name, super.debug})
    : super(kernelType: KernelFunctionType.serial);

  @override
  Map<String, String> getConfigAttributes() => {};

  /// Gets the TTY device path on the device side.
  String? getTtyDevice() {
    if (!isPrepared) {
      return null;
    }
    try {
      final portNum = readAttribute('port_num');
      return '/dev/ttyGS$portNum';
    } catch (_) {
      return null;
    }
  }
}

/// Base class for ethernet functions.
abstract class EthernetFunction extends KernelFunction {
  EthernetFunction({
    required super.name,
    required super.kernelType,
    this.hostAddr,
    this.devAddr,
    super.debug,
  });

  /// MAC address for the host side (e.g., "02:00:00:00:00:01")
  final String? hostAddr;

  /// MAC address for the device side (e.g., "02:00:00:00:00:02")
  final String? devAddr;

  /// Validates MAC address format.
  static bool isValidMacAddress(String? addr) {
    if (addr == null) return true;
    final regex = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
    return regex.hasMatch(addr);
  }

  @override
  bool validate() {
    if (!isValidMacAddress(hostAddr)) {
      log('Invalid host MAC address: $hostAddr');
      return false;
    }
    if (!isValidMacAddress(devAddr)) {
      log('Invalid device MAC address: $devAddr');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() {
    final attrs = <String, String>{};
    if (hostAddr != null) attrs['host_addr'] = hostAddr!;
    if (devAddr != null) attrs['dev_addr'] = devAddr!;
    return attrs;
  }

  /// Gets the network interface name (e.g., "usb0").
  ///
  /// Available after the gadget is bound.
  String? getInterfaceName() {
    return tryReadAttribute('ifname');
  }

  /// Gets the current host MAC address.
  String? getHostAddr() {
    return tryReadAttribute('host_addr');
  }

  /// Gets the current device MAC address.
  String? getDevAddr() {
    return tryReadAttribute('dev_addr');
  }

  /// Updates the host MAC address.
  void setHostAddr(String addr) {
    if (!isValidMacAddress(addr)) {
      throw ArgumentError('Invalid MAC address: $addr');
    }
    updateAttribute('host_addr', addr);
  }

  /// Updates the device MAC address.
  void setDevAddr(String addr) {
    if (!isValidMacAddress(addr)) {
      throw ArgumentError('Invalid MAC address: $addr');
    }
    updateAttribute('dev_addr', addr);
  }
}

/// Ethernet (CDC ECM) function.
///
/// Provides ethernet connectivity over USB using the CDC ECM protocol.
/// Widely supported on Linux, macOS, and some Windows systems.
class EcmFunction extends EthernetFunction {
  EcmFunction({required super.name, super.hostAddr, super.devAddr, super.debug})
    : super(kernelType: KernelFunctionType.ecm);
}

/// Ethernet (CDC ECM Subset) function.
///
/// Simplified version of ECM with reduced protocol overhead.
/// Also known as "geth" (generic ethernet).
class EcmSubsetFunction extends EthernetFunction {
  EcmSubsetFunction({
    required super.name,
    super.hostAddr,
    super.devAddr,
    super.debug,
  }) : super(kernelType: KernelFunctionType.ecmSubset);
}

/// Ethernet (CDC EEM) function.
///
/// Provides ethernet connectivity using the CDC EEM protocol.
/// Simpler than ECM with less overhead.
class EemFunction extends EthernetFunction {
  EemFunction({required super.name, super.hostAddr, super.devAddr, super.debug})
    : super(kernelType: KernelFunctionType.eem);
}

/// Ethernet (CDC NCM) function.
///
/// Provides ethernet connectivity using the CDC NCM protocol.
/// High-performance option with better throughput than ECM.
class NcmFunction extends EthernetFunction {
  NcmFunction({required super.name, super.hostAddr, super.devAddr, super.debug})
    : super(kernelType: KernelFunctionType.ncm);
}

/// RNDIS function (Windows ethernet).
///
/// Provides ethernet connectivity using Microsoft's RNDIS protocol.
/// Best compatibility with Windows systems.
class RndisFunction extends EthernetFunction {
  RndisFunction({
    required super.name,
    super.hostAddr,
    super.devAddr,
    this.wceis = true,
    super.debug,
  }) : super(kernelType: KernelFunctionType.rndis);

  /// Whether to use Windows CE Internet Sharing (WCEIS)
  final bool wceis;

  @override
  Map<String, String> getConfigAttributes() {
    final attrs = super.getConfigAttributes();
    attrs['wceis'] = wceis ? '1' : '0';
    return attrs;
  }
}

/// HID function (keyboard, mouse, gamepad, etc.).
///
/// Implements USB Human Interface Devices using a kernel driver.
/// The report descriptor defines the device type and capabilities.
class HIDFunction extends KernelFunction {
  HIDFunction({
    required super.name,
    required this.reportDescriptor,
    this.protocol = HIDProtocol.none,
    this.subclass = HIDSubclass.none,
    this.reportLength = 64,
    super.debug,
  }) : super(kernelType: KernelFunctionType.hid);

  /// HID report descriptor (defines device type and data format)
  final List<int> reportDescriptor;

  /// HID protocol (0=none, 1=keyboard, 2=mouse)
  final HIDProtocol protocol;

  /// HID subclass (0=none, 1=boot)
  final HIDSubclass subclass;

  /// Maximum report length in bytes
  final int reportLength;

  @override
  bool validate() {
    if (reportDescriptor.isEmpty) {
      log('HID report descriptor cannot be empty');
      return false;
    }
    if (reportLength <= 0 || reportLength > 1024) {
      log('Invalid report length: $reportLength (must be 1-1024)');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() => {
    'protocol': protocol.value.toString(),
    'subclass': subclass.value.toString(),
    'report_length': reportLength.toString(),
  };

  @override
  void onPrepare() {
    // Write binary report descriptor
    final reportDescPath = '$_functionPath/report_desc';
    log('Writing report descriptor (${reportDescriptor.length} bytes)');
    try {
      File(reportDescPath).writeAsBytesSync(reportDescriptor);
    } on FileSystemException catch (e) {
      throw FileSystemException(
        'Failed to write report descriptor: ${e.message}',
        reportDescPath,
        e.osError,
      );
    }
  }

  /// Gets the HID device path (e.g., /dev/hidg0).
  ///
  /// The device number can be read from the 'dev' attribute after binding.
  String? getHIDDevice() {
    if (!isPrepared) {
      return null;
    }
    try {
      // The 'dev' attribute contains device number or may not exist
      // Try reading it, if available parse it, otherwise check common paths
      final devAttr = tryReadAttribute('dev');
      if (devAttr != null) {
        // Parse device number (format may be just "0" or "major:minor")
        final parts = devAttr.split(':');
        final devNum = int.tryParse(parts.isEmpty ? devAttr : parts.last);
        if (devNum != null) {
          return '/dev/hidg$devNum';
        }
      }

      // Fallback: check if hidg0 exists (common case for first HID gadget)
      if (File('/dev/hidg0').existsSync()) {
        return '/dev/hidg0';
      }

      return null;
    } catch (_) {
      return null;
    }
  }
}

/// MIDI function.
///
/// Implements USB MIDI devices for audio/music applications.
class MidiFunction extends KernelFunction {
  MidiFunction({
    required super.name,
    this.id,
    this.inPorts = 1,
    this.outPorts = 1,
    this.buflen = 512,
    this.qlen = 32,
    super.debug,
  }) : super(kernelType: KernelFunctionType.midi);

  /// MIDI device ID string
  final String? id;

  /// Number of MIDI input ports (device to host)
  final int inPorts;

  /// Number of MIDI output ports (host to device)
  final int outPorts;

  /// Buffer length per port
  final int buflen;

  /// Request queue length
  final int qlen;

  @override
  bool validate() {
    if (inPorts < 0 || inPorts > 16) {
      log('Invalid inPorts: $inPorts (must be 0-16)');
      return false;
    }
    if (outPorts < 0 || outPorts > 16) {
      log('Invalid outPorts: $outPorts (must be 0-16)');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() {
    final attrs = <String, String>{
      'in_ports': inPorts.toString(),
      'out_ports': outPorts.toString(),
      'buflen': buflen.toString(),
      'qlen': qlen.toString(),
    };
    if (id != null) attrs['id'] = id!;
    return attrs;
  }
}

/// Audio (UAC1) function.
///
/// Implements USB Audio Class 1.0 devices.
/// Simpler but more widely compatible than UAC2.
class Uac1Function extends KernelFunction {
  Uac1Function({
    required super.name,
    this.cChmask = 3,
    this.pChmask = 3,
    this.reqNumber = 2,
    super.debug,
  }) : super(kernelType: KernelFunctionType.uac1);

  /// Capture channel mask (bitmap: 1=left, 2=right, 3=stereo)
  final int cChmask;

  /// Playback channel mask
  final int pChmask;

  /// Number of pre-allocated requests
  final int reqNumber;

  @override
  Map<String, String> getConfigAttributes() => {
    'c_chmask': cChmask.toString(),
    'p_chmask': pChmask.toString(),
    'req_number': reqNumber.toString(),
  };
}

/// Audio (UAC2) function.
///
/// Implements USB Audio Class 2.0 devices.
/// Provides more features and better quality than UAC1.
class Uac2Function extends KernelFunction {
  Uac2Function({
    required super.name,
    this.cChmask = 3,
    this.pChmask = 3,
    this.cSrate = 48000,
    this.pSrate = 48000,
    this.cSsize = 2,
    this.pSsize = 2,
    this.reqNumber = 2,
    super.debug,
  }) : super(kernelType: KernelFunctionType.uac2);

  /// Capture channel mask (bitmap: 1=left, 2=right, 3=stereo)
  final int cChmask;

  /// Playback channel mask
  final int pChmask;

  /// Capture sample rate (Hz)
  final int cSrate;

  /// Playback sample rate (Hz)
  final int pSrate;

  /// Capture sample size (bytes: 2=16bit, 3=24bit, 4=32bit)
  final int cSsize;

  /// Playback sample size (bytes)
  final int pSsize;

  /// Number of pre-allocated requests
  final int reqNumber;

  @override
  bool validate() {
    if (cSrate <= 0 || cSrate > 192000) {
      log('Invalid capture sample rate: $cSrate');
      return false;
    }
    if (pSrate <= 0 || pSrate > 192000) {
      log('Invalid playback sample rate: $pSrate');
      return false;
    }
    if (![2, 3, 4].contains(cSsize)) {
      log('Invalid capture sample size: $cSsize (must be 2, 3, or 4)');
      return false;
    }
    if (![2, 3, 4].contains(pSsize)) {
      log('Invalid playback sample size: $pSsize (must be 2, 3, or 4)');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() => {
    'c_chmask': cChmask.toString(),
    'p_chmask': pChmask.toString(),
    'c_srate': cSrate.toString(),
    'p_srate': pSrate.toString(),
    'c_ssize': cSsize.toString(),
    'p_ssize': pSsize.toString(),
    'req_number': reqNumber.toString(),
  };
}

/// Video (UVC) function.
///
/// Implements USB Video Class devices (webcams).
class UvcFunction extends KernelFunction {
  UvcFunction({
    required super.name,
    this.streamingMaxpacket = 3072,
    this.streamingMaxburst = 0,
    this.streamingInterval = 1,
    super.debug,
  }) : super(kernelType: KernelFunctionType.uvc);

  /// Maximum packet size for streaming endpoint
  final int streamingMaxpacket;

  /// Maximum burst for super-speed
  final int streamingMaxburst;

  /// Streaming interval (frame rate related)
  final int streamingInterval;

  @override
  Map<String, String> getConfigAttributes() => {
    'streaming_maxpacket': streamingMaxpacket.toString(),
    'streaming_maxburst': streamingMaxburst.toString(),
    'streaming_interval': streamingInterval.toString(),
  };

  /// Gets the video device node (e.g., /dev/video0).
  String? getVideoDevice() {
    // UVC creates a V4L2 device node
    // The exact path depends on system configuration
    // This would need more sophisticated detection in practice
    return tryReadAttribute('function_name');
  }
}

/// Printer function.
///
/// Implements USB printer class devices.
class PrinterFunction extends KernelFunction {
  PrinterFunction({
    required super.name,
    this.pnpString,
    this.qLen = 10,
    super.debug,
  }) : super(kernelType: KernelFunctionType.printer);

  /// IEEE 1284 Device ID string (Plug and Play string)
  final String? pnpString;

  /// Request queue length
  final int qLen;

  @override
  Map<String, String> getConfigAttributes() {
    final attrs = <String, String>{'q_len': qLen.toString()};
    if (pnpString != null) attrs['pnp_string'] = pnpString!;
    return attrs;
  }
}

/// Loopback function (for testing).
///
/// A simple test function that loops back data from OUT to IN endpoints.
/// Useful for USB bandwidth and functionality testing.
class LoopbackFunction extends KernelFunction {
  LoopbackFunction({
    required super.name,
    this.qlen = 32,
    this.bulkBuflen = 4096,
    super.debug,
  }) : super(kernelType: KernelFunctionType.loopback);

  /// Request queue length
  final int qlen;

  /// Bulk endpoint buffer length
  final int bulkBuflen;

  @override
  Map<String, String> getConfigAttributes() => {
    'qlen': qlen.toString(),
    'bulk_buflen': bulkBuflen.toString(),
  };
}

/// Source/Sink function (for testing).
///
/// A test function that:
/// - "Source": continuously generates data on IN endpoints
/// - "Sink": discards data received on OUT endpoints
///
/// Useful for USB performance testing and validation.
class SourceSinkFunction extends KernelFunction {
  SourceSinkFunction({
    required super.name,
    this.pattern = 0,
    this.isocInterval = 4,
    this.isocMaxpacket = 1024,
    this.isocMult = 0,
    this.isocMaxburst = 0,
    this.bulkBuflen = 4096,
    this.qlen = 32,
    super.debug,
  }) : super(kernelType: KernelFunctionType.sourceSink);

  /// Test pattern to use (0-2)
  final int pattern;

  /// Isochronous transfer interval
  final int isocInterval;

  /// Isochronous maximum packet size
  final int isocMaxpacket;

  /// Isochronous multiplier (high-speed/super-speed)
  final int isocMult;

  /// Isochronous maximum burst (super-speed)
  final int isocMaxburst;

  /// Bulk endpoint buffer length
  final int bulkBuflen;

  /// Request queue length
  final int qlen;

  @override
  bool validate() {
    if (pattern < 0 || pattern > 2) {
      log('Invalid pattern: $pattern (must be 0-2)');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() => {
    'pattern': pattern.toString(),
    'isoc_interval': isocInterval.toString(),
    'isoc_maxpacket': isocMaxpacket.toString(),
    'isoc_mult': isocMult.toString(),
    'isoc_maxburst': isocMaxburst.toString(),
    'bulk_buflen': bulkBuflen.toString(),
    'qlen': qlen.toString(),
  };
}
