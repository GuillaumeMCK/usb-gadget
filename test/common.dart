library common;

import 'dart:io';
import 'dart:typed_data';
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
    markTestSkipped('No UDC found — all hardware tests skipped');
    return;
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
    final result = await Process.run('modprobe', [mod]);
    if (result.exitCode != 0) {
      printOnFailure('  [SKIP] modprobe $mod: ${result.stderr}'.trim());
    }
  }
}

/// Skips the current test when no UDC is available.
///
/// Call at the top of any test that touches configfs or a real USB controller.
/// In environments without hardware (CI, dev workstations) the test is skipped
/// gracefully rather than failing.
void requireUDC() {
  if (!hasUDC) {
    markTestSkipped('No UDC found — hardware test skipped');
  }
}

// ---------------------------------------------------------------------------
// Fake / stub implementations for unit tests
// ---------------------------------------------------------------------------

/// A minimal [GadgetFunction] that records lifecycle calls without touching
/// the filesystem.  Used to verify [Gadget] / [Config] wiring in unit tests.
class FakeFunction extends GadgetFunction {
  FakeFunction(String name) : super(name: name);

  bool prepared = false;
  bool released = false;
  String? preparedPath;

  @override
  FunctionType get type => .kernel;

  @override
  String get configfsName => 'fake.$name';

  @override
  Future<void> prepare(String path) async {
    prepared = true;
    preparedPath = path;
  }

  @override
  Future<void> awaitState(FunctionFsState state) => Future.value();

  @override
  Future<void> release() async {
    released = true;
    super.release();
  }
}

/// Builds a minimal [Gadget] whose only config contains [fn].
///
/// All integration fixtures share the same vendor/product ID and string
/// descriptor values; only the name and function differ.
Gadget kernelTestGadget(String name, GadgetFunction fn) => Gadget(
  name: name,
  id: const Id(vendor: 0x1234, product: 0xFFFF),
  strings: {
    USBLanguageId.enUS: const GadgetStrings(
      manufacturer: 'Test',
      product: 'Kernel Function Test',
      serialnumber: 'KFT-001',
    ),
  },
  configs: [
    Config(functions: [fn]),
  ],
);

/// A minimal [KernelFunction] for unit tests that bypasses all filesystem
/// operations.
///
/// Overrides [checkDirectoryExists] as a no-op so that [prepare] can be
/// called with arbitrary (non-existent) paths.  This lets lifecycle tests
/// focus on state-machine behaviour rather than filesystem preconditions.
class MinimalKernelFn extends KernelFunction {
  MinimalKernelFn({required super.name, required super.kernelType});

  @override
  Map<String, String> getConfigAttributes() => {};

  @override
  void checkDirectoryExists(String path) {}
}

// ---------------------------------------------------------------------------
// Byte-level helpers
// ---------------------------------------------------------------------------

/// Builds a 12-byte FunctionFs event buffer with [typeByte] at offset 8
/// and [setupData] at offsets 0–7 (all zeros by default).
Uint8List buildEventBytes(int typeByte, {List<int>? setupData}) {
  final data = Uint8List(12);
  if (setupData != null) {
    for (var i = 0; i < setupData.length && i < 8; i++) {
      data[i] = setupData[i];
    }
  }
  data[8] = typeByte;
  return data;
}

/// Constructs a SETUP packet as a 12-byte event buffer.
Uint8List buildSetupEventBytes({
  required int bmRequestType,
  required int bRequest,
  required int wValue,
  required int wIndex,
  required int wLength,
}) {
  final data = Uint8List(12);
  data[0] = bmRequestType;
  data[1] = bRequest;
  data[2] = wValue & 0xFF;
  data[3] = (wValue >> 8) & 0xFF;
  data[4] = wIndex & 0xFF;
  data[5] = (wIndex >> 8) & 0xFF;
  data[6] = wLength & 0xFF;
  data[7] = (wLength >> 8) & 0xFF;
  data[8] = 4; // FunctionFsEventType.setup
  return data;
}

/// A minimal [DescriptorSet] built from a single bulk IN [EndpointDescriptor],
/// sufficient to satisfy [FunctionFsDescriptorsBuilder] in unit tests.
///
/// Uses [DescriptorGenerator.generateForSpeed], which is the same path the
/// library itself takes inside [FunctionFs.prepare].
DescriptorSet dummyDescriptorSet() {
  final descriptors = [
    EndpointDescriptor(
      address: EndpointAddress.in_(.ep1),
      config: EndpointConfig.bulk(),
    ),
  ];
  return DescriptorGenerator.generateForSpeed(descriptors, Speed.fullSpeed);
}
