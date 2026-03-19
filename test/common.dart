library common;

import 'dart:io';
import 'package:test/test.dart';
import 'package:usb_gadget/usb_gadget.dart';

// ---------------------------------------------------------------------------
// Environment helpers
// ---------------------------------------------------------------------------

// final testUDC = UDC.fromName('dummy_udc.0');
final testUDC = defaultUDC;

/// Prepares the USB gadget hardware environment.
///
/// Must be called inside [setUpAll]; skips all tests in the current suite
/// if no UDC is available.
Future<void> ensureHardwareReady() async {
  if (!hasUDC) {
    return markTestSkipped('No UDC found — all hardware tests skipped');
  }
  await _loadModules();
}

// ---------------------------------------------------------------------------
// Kernel module loading
// ---------------------------------------------------------------------------

/// Optional modules to probe before integration tests.
///
/// Missing modules are logged as warnings rather than failures, because not
/// every kernel is compiled with every gadget function.
const _optionalModules = [
  'usb_f_fs',
  'usb_f_hid',
  'usb_f_acm',
  'usb_f_ecm',
  'usb_f_ncm',
  'usb_f_eem',
  'usb_f_rndis',
  'usb_f_mass_storage',
  'usb_f_midi',
  'usb_f_uac1',
  'usb_f_uac2',
  'usb_f_uvc',
  'usb_f_printer',
  'usb_f_loopback',
  'usb_f_ss_lb',
];

Future<void> _loadModules() async {
  for (final mod in _optionalModules) {
    try {
      await Process.run('modprobe', [mod]);
    } catch (_) {
      printOnFailure('  [SKIP] modprobe $mod'.trim());
    }
  }
}
