import 'dart:io';

import '/src/gadget/fs.dart';
import 'base.dart';

/// Base class for ethernet functions.
abstract class EthernetFunction extends KernelFunction {
  EthernetFunction({
    required super.name,
    required super.kernelType,
    this.hostAddr,
    this.devAddr,
  });

  /// MAC address for the host side (e.g., "02:00:00:00:00:01")
  final String? hostAddr;

  /// MAC address for the device side (e.g., "02:00:00:00:00:02")
  final String? devAddr;

  /// Validates MAC address format.
  static bool isValidMacAddress(String? addr) {
    if (addr == null) return true;
    return RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(addr);
  }

  @override
  bool validate() {
    if (!isValidMacAddress(hostAddr)) {
      log?.error('Invalid host MAC: $hostAddr');
      return false;
    }
    if (!isValidMacAddress(devAddr)) {
      log?.error('Invalid device MAC: $devAddr');
      return false;
    }
    return true;
  }

  @override
  Map<String, String> getConfigAttributes() => {
    if (hostAddr != null) 'host_addr': hostAddr!,
    if (devAddr != null) 'dev_addr': devAddr!,
  };

  /// Gets the network interface name (e.g., "usb0").
  String? getInterfaceName() => readAttribute('ifname');

  /// Gets the current host MAC address.
  String? getHostAddr() => readAttribute('host_addr');

  /// Gets the current device MAC address.
  String? getDevAddr() => readAttribute('dev_addr');

  /// Updates the host MAC address.
  void setHostAddr(String addr) {
    if (!isValidMacAddress(addr))
      throw ArgumentError('Invalid MAC address: $addr');
    writeAttribute('host_addr', addr);
  }

  /// Updates the device MAC address.
  void setDevAddr(String addr) {
    if (!isValidMacAddress(addr))
      throw ArgumentError('Invalid MAC address: $addr');
    writeAttribute('dev_addr', addr);
  }
}

/// Ethernet (CDC ECM) function.
class EcmFunction extends EthernetFunction {
  EcmFunction({required super.name, super.hostAddr, super.devAddr})
    : super(kernelType: .ecm);
}

/// Ethernet (CDC ECM Subset) function.
class EcmSubsetFunction extends EthernetFunction {
  EcmSubsetFunction({required super.name, super.hostAddr, super.devAddr})
    : super(kernelType: .ecmSubset);
}

/// Ethernet (CDC EEM) function.
class EemFunction extends EthernetFunction {
  EemFunction({required super.name, super.hostAddr, super.devAddr})
    : super(kernelType: .eem);
}

/// RNDIS function (Windows ethernet).
class RndisFunction extends EthernetFunction {
  RndisFunction({
    required super.name,
    super.hostAddr,
    super.devAddr,
    this.wceis = true,
  }) : super(kernelType: .rndis);

  /// Whether to use Windows CE Internet Sharing (WCEIS).
  final bool wceis;

  @override
  Future<void> prepare(String path) async {
    await super.prepare(path);
    // wceis is read-only on some kernels (open() returns EPERM).
    try {
      writeAttribute('wceis', wceis ? '1' : '0');
    } catch (_) {}
  }

  @override
  Future<void> release() async {
    if (isReleased) return;
    if (prepared) {
      ConfigFsTree()
        ..absorb(Directory('$functionPath/os_desc'))
        ..sweep();
    }
    await super.release();
  }
}

/// Ethernet (CDC NCM) function.
class NcmFunction extends EthernetFunction {
  NcmFunction({required super.name, super.hostAddr, super.devAddr})
    : super(kernelType: .ncm);

  @override
  Future<void> release() async {
    if (isReleased) return;
    if (prepared) {
      ConfigFsTree()
        ..absorb(Directory('$functionPath/os_desc'))
        ..sweep();
    }
    await super.release();
  }
}
