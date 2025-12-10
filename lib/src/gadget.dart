/// USB Gadget management through configfs.
///
/// This library provides a high-level interface for creating and managing USB
/// gadgets on Linux systems using the configfs filesystem. It handles the
/// complete lifecycle of USB device emulation, from descriptor setup to UDC
/// binding and cleanup.
///
/// ## Core Concepts
///
/// - **Gadget**: A complete USB device definition with vendor/product IDs,
///   configurations, and functions.
/// - **Configuration**: A set of functions that can be selected by the host.
/// - **Function**: An individual USB capability (e.g., mass storage, ADB).
/// - **UDC**: USB Device Controller, the hardware that implements the device.
///
/// ## Usage Example
///
/// ```dart
/// final gadget = Gadget(
///   name: 'my_device',
///   idVendor: 0x1234,
///   idProduct: 0x5678,
///   config: GadgetConfiguration(
///     functions: [myFunction],
///   ),
/// );
///
/// await gadget.bind();
/// // Device is now active
/// gadget.unbind();
/// ```
library;

import 'dart:async';
import 'dart:io';

import '/usb_gadget.dart';
import 'core/utils.dart';

/// String descriptors for a gadget.
///
/// Provides human-readable information about the device in various languages.
/// All fields are optional; the USB spec only requires the serial number for
/// certain device classes.
///
/// Example:
/// ```dart
/// const strings = GadgetStrings(
///   manufacturer: 'ACME Corp',
///   product: 'Rocket Sled',
///   serialnumber: 'RS-42-2024',
/// );
/// ```
class GadgetStrings {
  /// Creates string descriptors with optional values.
  const GadgetStrings({this.serialnumber, this.manufacturer, this.product});

  /// Serial number string (e.g., "123456789ABC").
  ///
  /// Should be unique per device. Required for mass storage devices.
  final String? serialnumber;

  /// Manufacturer string (e.g., "ACME Corporation").
  final String? manufacturer;

  /// Product string (e.g., "Rocket Sled 3000").
  final String? product;
}

/// A gadget configuration containing functions and attributes.
///
/// A configuration is a set of functions that can be selected by the USB host.
/// Most gadgets have a single configuration (index 1), but multiple
/// configurations allow the host to choose between different sets of functions.
///
/// Example:
/// ```dart
/// final config = GadgetConfiguration(
///   functions: [massStorageFunction, adbFunction],
///   attributes: GadgetAttributes.selfPowered,
///   maxPower: GadgetMaxPower.fromMilliAmps(500),
///   strings: {
///     USBLanguageId.en_US: 'My Configuration',
///   },
/// );
/// ```
final class GadgetConfiguration {
  /// Creates a gadget configuration.
  ///
  /// Parameters:
  /// - [functions]: List of functions in this configuration
  /// - [attributes]: Power and wakeup attributes
  /// - [maxPower]: Maximum power consumption
  /// - [strings]: Configuration name per language
  /// - [index]: Configuration number (1-based, must be positive)
  const GadgetConfiguration({
    required this.functions,
    this.attributes,
    this.maxPower,
    this.strings = const {},
    this.index = 1,
  }) : assert(index > 0, 'Configuration index must be positive');

  /// Functions available in this configuration.
  final List<GadgetFunction> functions;

  /// Power attributes (bus-powered, self-powered, remote wakeup).
  final GadgetAttributes? attributes;

  /// Maximum power consumption from the USB bus.
  final GadgetMaxPower? maxPower;

  /// Configuration name strings per language.
  final Map<USBLanguageId, String> strings;

  /// Configuration index (1-based).
  ///
  /// Multiple configurations allow the host to choose between different
  /// function sets. Most devices use a single configuration (index 1).
  final int index;
}

/// Type of gadget function.
///
/// - **FFS (FunctionFS)**: Userspace-implemented functions that require
///   descriptor setup and endpoint handling in userspace (e.g., ADB, MTP).
/// - **Kernel**: Kernel-implemented functions that only require configuration
///   attributes (e.g., mass storage, serial port).
enum GadgetFunctionType { ffs, kernel }

/// USB configuration attributes (bmAttributes field).
///
/// Specifies power source and wakeup capability of the device.
enum GadgetAttributes {
  /// Device is powered from the USB bus only (default).
  ///
  /// Maximum power draw is limited by bMaxPower (typically 500 mA for USB 2.0).
  busPowered(0x80),

  /// Device has an external power source.
  ///
  /// Can draw more power than USB provides. The device may or may not also
  /// draw power from the bus.
  selfPowered(0xC0),

  /// Device supports remote wakeup.
  ///
  /// Can signal the host to exit suspend mode. Requires host approval.
  remoteWakeup(0xA0);

  const GadgetAttributes(this.value);

  /// Raw bmAttributes byte value.
  final int value;
}

/// Handles USB bMaxPower values for gadget configurations.
///
/// bMaxPower specifies the maximum power consumption of the device from the
/// USB bus. The value is stored in USB units (2 mA per unit) in the range 0-255.
///
/// ## Examples
///
/// ```dart
/// // Create from raw USB value (0-255)
/// final maxPower1 = GadgetMaxPower(250);  // 500 mA
///
/// // Create from milliamps (preferred)
/// final maxPower2 = GadgetMaxPower.fromMilliAmps(500);
///
/// // Convert to milliamps
/// print(maxPower2.toMilliAmps());  // 500
/// ```
///
/// ## USB Power Limits
///
/// - USB 2.0 Low-power: 100 mA
/// - USB 2.0 High-power: 500 mA
/// - USB 3.0: 900 mA
/// - USB BC 1.2: 1500 mA (negotiated)
final class GadgetMaxPower {
  /// Creates a MaxPower value from a raw USB bMaxPower value (0-255).
  ///
  /// The raw value represents units of 2 mA each. For example:
  /// - 0 = 0 mA
  /// - 50 = 100 mA
  /// - 250 = 500 mA
  ///
  /// Most users should prefer [fromMilliAmps] for clarity.
  ///
  /// Throws [ArgumentError] if value is outside the 0-255 range.
  GadgetMaxPower(this.value) {
    if (value < 0 || value > 0xFF) {
      throw ArgumentError(
        'Raw USB bMaxPower value must be in 0–255 range (was $value).',
      );
    }
  }

  /// Creates a MaxPower value from milliamps.
  ///
  /// The USB spec uses 2 mA units, so values are rounded down if not aligned.
  /// For example:
  /// - 100 mA → value 50
  /// - 101 mA → value 50 (rounded down)
  /// - 500 mA → value 250
  ///
  /// Maximum supported value is 510 mA (255 * 2 mA).
  ///
  /// Example:
  /// ```dart
  /// final power = GadgetMaxPower.fromMilliAmps(500);  // USB 2.0 high-power
  /// print(power.toMilliAmps());  // 500
  /// ```
  ///
  /// Throws:
  /// - [ArgumentError] if mA is negative
  /// - [ArgumentError] if mA exceeds 510 (USB limit)
  factory GadgetMaxPower.fromMilliAmps(int mA) {
    if (mA < 0) {
      throw ArgumentError('Milliamp value must be >= 0 (was $mA).');
    }

    final value = mA ~/ _unitMilliAmps; // integer division (truncate)

    if (value > 0xFF) {
      throw ArgumentError(
        'Requested $mA mA exceeds USB limit (${0xFF * _unitMilliAmps} mA).',
      );
    }

    return GadgetMaxPower(value);
  }

  /// Raw USB bMaxPower value (0–255).
  ///
  /// This is the value written to the USB configuration descriptor.
  /// Each unit represents 2 mA of power consumption.
  final int value;

  /// USB 2.x power unit in milliamps.
  ///
  /// The USB specification defines power in units of 2 mA for USB 2.0 and
  /// earlier. USB 3.0 uses 8 mA units, but this library currently only
  /// supports USB 2.0 power units.
  static const int _unitMilliAmps = 2;

  /// Converts the raw USB value to milliamps.
  ///
  /// Returns the actual power consumption represented by this bMaxPower value.
  ///
  /// Example:
  /// ```dart
  /// final power = GadgetMaxPower(250);
  /// print(power.toMilliAmps());  // 500
  /// ```
  int toMilliAmps() => value * _unitMilliAmps;

  /// Returns a human-readable representation of the power value.
  ///
  /// Shows both the raw USB value and the milliamp equivalent.
  ///
  /// Example: `GadgetMaxPower(value=250, mA=500)`
  @override
  String toString() => 'GadgetMaxPower(value=$value, mA=${toMilliAmps()})';
}

/// Core abstraction for all USB gadget functions.
///
/// A function represents a specific USB capability that can be exposed to
/// the host (e.g., mass storage, serial port, ADB). Functions follow a
/// three-phase lifecycle to ensure proper initialization before the gadget
/// is bound to hardware.
///
/// ## Lifecycle Phases
///
/// 1. **prepare()**: Initialize resources asynchronously (mount filesystems,
///    write configuration attributes, open files).
/// 2. **waitState()**: Wait until the function is ready for UDC binding.
///    This ensures all setup is complete before hardware activation.
/// 3. **dispose()**: Clean up resources when the gadget is unbound (close
///    files, unmount filesystems, release handles).
///
/// ## Implementation Guidelines
///
/// Subclasses must implement:
/// - [type]: The function type (FFS or kernel-based).
/// - [getConfigfsInstanceName]: The configfs directory name (e.g.,
///   "ffs.myfunction" or "mass_storage.storage").
/// - [prepare]: Setup logic specific to the function type.
/// - [waitState]: Ready-state detection logic.
/// - [dispose]: Cleanup logic for all acquired resources.
///
/// ## Example Implementation
///
/// ```dart
/// class MyFunction extends GadgetFunction {
///   MyFunction() : super(name: 'myfunction');
///
///   @override
///   GadgetFunctionType get type => GadgetFunctionType.ffs;
///
///   @override
///   String getConfigfsInstanceName() => 'ffs.$name';
///
///   @override
///   void prepare(String path) {
///     // Mount FunctionFS, write descriptors
///   }
///
///   @override
///   Future<void> waitState(FunctionFsState state) async {
///     // Wait for descriptors to be written
///   }
///
///   @override
///   void dispose() {
///     // Unmount, close files
///   }
/// }
/// ```
abstract class GadgetFunction {
  /// Creates a gadget function with the specified name.
  ///
  /// Parameters:
  /// - [name]: Unique identifier for this function instance. Must be non-empty.
  /// - [debug]: Enable verbose logging for troubleshooting.
  GadgetFunction({required this.name, this.debug = false})
    : assert(name.isNotEmpty, 'Name cannot be empty');

  /// Unique identifier for this function instance.
  ///
  /// Used to create the configfs directory and identify the function in logs.
  final String name;

  /// Whether to enable debug logging for this function.
  final bool debug;

  /// Type of this function (FFS or kernel-based).
  ///
  /// FunctionFS functions require userspace descriptors and endpoint handling.
  /// Kernel functions are implemented entirely in the kernel and only require
  /// configuration attribute setup.
  GadgetFunctionType get type;

  /// Returns the configfs instance name for this function.
  ///
  /// The format depends on the function type:
  /// - FFS functions: "ffs.{name}" (e.g., "ffs.adb")
  /// - Kernel functions: "{type}.{name}" (e.g., "mass_storage.storage")
  ///
  /// This name is used to create the function directory under
  /// `/sys/kernel/config/usb_gadget/{gadget}/functions/`.
  String getConfigfsInstanceName();

  /// Phase 1: Initialize function resources at the given configfs path.
  ///
  /// This method is called after the function directory is created but before
  /// it's linked to a configuration. It should perform all necessary setup:
  ///
  /// **For FunctionFS functions:**
  /// - Mount the functionfs filesystem
  /// - Write USB descriptors (device, endpoint, string descriptors)
  /// - Open endpoint files for I/O
  ///
  /// **For kernel functions:**
  /// - Write configuration attributes (LUN paths, serial numbers, etc.)
  /// - Validate configuration parameters
  ///
  /// The [path] parameter is the full configfs path where the function should
  /// write its attributes (e.g., `/sys/kernel/config/usb_gadget/g1/functions/ffs.adb`).
  ///
  /// **Important:** This method must be synchronous in execution but can
  /// initiate asynchronous operations. Use [waitState] to wait for completion.
  ///
  /// Throws:
  /// - [FileSystemException] if configuration files cannot be written
  /// - [ArgumentError] if invalid configuration is provided
  void prepare(String path);

  /// Phase 2: Wait until function is ready for UDC binding.
  ///
  /// This method blocks until the function has reached the specified [state].
  /// The gadget will only bind to the UDC after ALL functions signal ready.
  ///
  /// **For FunctionFS functions:**
  /// - Wait for [FunctionFsState.ready]: descriptors written, endpoints opened
  /// - This ensures the kernel has parsed descriptors before UDC binding
  ///
  /// **For kernel functions:**
  /// - Return immediately (always ready after [prepare])
  ///
  /// The [state] parameter specifies the target state. Common states:
  /// - [FunctionFsState.ready]: Function is fully initialized and ready
  ///
  /// Throws:
  /// - [StateError] if the function enters an error state
  /// - [TimeoutException] if the state is not reached within a reasonable time
  Future<void> waitState(FunctionFsState state);

  /// Phase 3: Clean up function resources.
  ///
  /// Called during gadget unbind to release all resources acquired during
  /// [prepare]. This method should never throw exceptions; log warnings
  /// instead.
  ///
  /// **Cleanup tasks:**
  /// - Close all open file descriptors (endpoint files, control socket)
  /// - Unmount functionfs filesystems
  /// - Stop any background threads or async operations
  /// - Release any allocated memory or buffers
  ///
  /// After this method completes, the function should be in a clean state
  /// and ready for garbage collection.
  void dispose();

  /// Logs a debug message if debugging is enabled.
  ///
  /// Messages are prefixed with the function type and name for easy filtering.
  /// Use this for troubleshooting initialization, state transitions, and I/O.
  void log(String message) {
    if (debug) {
      stdout.writeln('[${type.name}:$name] $message');
    }
  }
}

/// Creates and manages a USB gadget with the specified configuration.
///
/// A Gadget represents a complete USB device that can be bound to a USB Device
/// Controller (UDC) to emulate a physical USB device. It handles:
///
/// - Creating the configfs directory structure
/// - Writing device descriptors (vendor/product IDs, strings, etc.)
/// - Preparing and linking functions
/// - Binding to the UDC hardware
/// - Cleanup and unbinding
///
/// ## Lifecycle
///
/// 1. Create the gadget with configuration
/// 2. Call [bind] to activate the device
/// 3. Device is now visible to USB hosts
/// 4. Call [unbind] to deactivate and clean up
///
/// ## Example
///
/// ```dart
/// final gadget = Gadget(
///   name: 'my_device',
///   idVendor: 0x1234,
///   idProduct: 0x5678,
///   bcdDevice: 0x0100,  // Device version 1.0
///   bcdUSB: 0x0200,     // USB 2.0
///   strings: {
///     USBLanguageId.en_US: GadgetStrings(
///       manufacturer: 'My Company',
///       product: 'My Device',
///       serialnumber: '123456',
///     ),
///   },
///   config: GadgetConfiguration(
///     functions: [myFunction],
///     attributes: GadgetAttributes.selfPowered,
///     maxPower: GadgetMaxPower.fromMilliAmps(500),
///   ),
/// );
///
/// try {
///   await gadget.bind();
///   // Device is active
/// } finally {
///   gadget.unbind();
/// }
/// ```
class Gadget {
  /// Creates a new USB gadget with the specified configuration.
  ///
  /// Parameters:
  /// - [name]: Unique name for this gadget (used in configfs path)
  /// - [idVendor]: USB Vendor ID (assigned by USB-IF)
  /// - [idProduct]: USB Product ID (assigned by vendor)
  /// - [config]: Configuration containing functions and attributes
  /// - [bcdDevice]: Device version in BCD format (default: 0x0100 = v1.0)
  /// - [bcdUSB]: USB version in BCD format (default: 0x0200 = USB 2.0)
  /// - [deviceClass]: USB device class (null = composite device)
  /// - [deviceSubClass]: USB device subclass
  /// - [deviceProtocol]: USB device protocol
  /// - [udc]: Specific UDC to bind to (null = auto-detect)
  /// - [debug]: Enable verbose logging
  /// - [strings]: String descriptors per language
  Gadget({
    required this.name,
    required this.idVendor,
    required this.idProduct,
    required this.config,
    this.bcdDevice = 0x0100,
    this.bcdUSB = 0x0200,
    this.deviceClass,
    this.deviceSubClass,
    this.deviceProtocol,
    this.udc,
    this.debug = false,
    Map<USBLanguageId, GadgetStrings>? strings,
  }) : strings = {...?strings},
       assert(name.isNotEmpty, 'Gadget name cannot be empty'),
       _gadgetPath = '/sys/kernel/config/usb_gadget/$name';

  /// Unique name for this gadget instance.
  final String name;

  /// USB Vendor ID (VID) - identifies the device manufacturer.
  ///
  /// Official VIDs are assigned by the USB Implementers Forum (USB-IF).
  /// For testing, use 0x1234 (reserved for vendor-specific use).
  final int idVendor;

  /// USB Product ID (PID) - identifies the specific device.
  ///
  /// Assigned by the vendor. Should be unique within the vendor's product line.
  final int idProduct;

  /// Device version in Binary Coded Decimal format.
  ///
  /// Format: 0xJJMN where JJ=major, M=minor, N=sub-minor
  /// Examples: 0x0100 = v1.0, 0x0210 = v2.1.0
  final int bcdDevice;

  /// USB specification version in Binary Coded Decimal format.
  ///
  /// Common values:
  /// - 0x0200: USB 2.0
  /// - 0x0210: USB 2.1
  /// - 0x0300: USB 3.0
  final int bcdUSB;

  /// USB device class code.
  ///
  /// Defines the general device category. If null, the device is a composite
  /// device where each interface defines its own class.
  final DeviceClass? deviceClass;

  /// USB device subclass code.
  ///
  /// Further categorizes the device within its class.
  final DeviceSubClass? deviceSubClass;

  /// USB device protocol code.
  ///
  /// Specifies the protocol used by the device.
  final DeviceProtocol? deviceProtocol;

  /// String descriptors for various languages.
  ///
  /// Maps language IDs to gadget strings (manufacturer, product, serial).
  final Map<USBLanguageId, GadgetStrings> strings;

  /// Configuration containing functions and attributes.
  final GadgetConfiguration config;

  /// Enable verbose logging for troubleshooting.
  final bool debug;

  /// Full path to the gadget in configfs.
  final String _gadgetPath;

  /// Specific UDC to bind to, or null for auto-detection.
  String? udc;

  /// The UDC this gadget is currently bound to, or null if unbound.
  String? _boundUdc;

  /// Track created directories in order for proper cleanup.
  ///
  /// Directories are removed in reverse order during unbind to avoid
  /// "directory not empty" errors.
  final List<String> _createdDirs = [];

  /// Track created symlinks in order for proper cleanup.
  ///
  /// Symlinks are removed before directories during unbind.
  final List<String> _createdSymlinks = [];

  /// Logs a debug message if debugging is enabled.
  void _log(String message) {
    if (debug) {
      stdout.writeln('[gadget:$name] $message');
    }
  }

  /// Whether this gadget is currently bound to a UDC.
  bool get isBound => _boundUdc != null;

  /// Binds the gadget to an available UDC, activating the USB device.
  ///
  /// This method performs the complete gadget setup sequence:
  /// 1. Create configfs directory structure
  /// 2. Write device descriptors and attributes
  /// 3. Prepare all functions
  /// 4. Wait for all functions to be ready
  /// 5. Bind to the UDC hardware
  ///
  /// If [udc] is specified, binds to that specific UDC. Otherwise, auto-selects
  /// the only available UDC (throws if multiple UDCs are present).
  ///
  /// After successful binding, the device is visible to USB hosts and will
  /// respond to enumeration.
  ///
  /// Example:
  /// ```dart
  /// final gadget = Gadget(...);
  /// await gadget.bind();  // Device is now active
  /// ```
  ///
  /// Throws:
  /// - [StateError] if already bound or no UDC available
  /// - [FileSystemException] if configfs operations fail
  /// - [TimeoutException] if functions don't become ready
  Future<void> bind() async {
    if (isBound) {
      throw StateError('Gadget is already bound to UDC $_boundUdc');
    }

    _log('Starting bind process');
    final targetUdc = udc ?? _findUdc();
    _log('Target UDC: $targetUdc');

    try {
      _createGadget();
      await _waitFunctionsState(.ready);
      _log('All functions are ready, binding to UDC...');
      _bindToUdc(targetUdc);
      _log('Gadget bound successfully to UDC: $_boundUdc');
    } catch (e) {
      _log('Bind failed: $e');
      unbind();
      rethrow;
    }
  }

  /// Waits for all functions to reach the specified state.
  ///
  /// This ensures synchronized initialization - no function is left behind.
  Future<void> _waitFunctionsState(FunctionFsState state) async {
    await [
      for (final function in config.functions) function.waitState(state),
    ].wait;
    _log('All functions are in state: $state');
  }

  /// Creates the complete configfs gadget structure.
  ///
  /// This method builds the entire gadget hierarchy:
  /// - Device descriptors (VID/PID, class codes, version numbers)
  /// - String descriptors (manufacturer, product, serial per language)
  /// - Configuration (attributes, max power)
  /// - Functions (create directories, prepare, and link)
  ///
  /// Functions are prepared before linking to avoid "Device or resource busy"
  /// errors that occur when trying to write attributes after linking.
  void _createGadget() {
    _log('Creating gadget structure at $_gadgetPath');
    _mkdir(_gadgetPath);

    // Write device descriptor attributes
    if (deviceClass case DeviceClass(:final int value)) {
      _writeAttr('$_gadgetPath/bDeviceClass', value.toHex());
    }
    if (deviceSubClass case DeviceSubClass(:final int value)) {
      _writeAttr('$_gadgetPath/bDeviceSubClass', value.toHex());
    }
    if (deviceProtocol case DeviceProtocol(:final int value)) {
      _writeAttr('$_gadgetPath/bDeviceProtocol', value.toHex());
    }
    _writeAttr('$_gadgetPath/idVendor', idVendor.toHex());
    _writeAttr('$_gadgetPath/idProduct', idProduct.toHex());
    _writeAttr('$_gadgetPath/bcdDevice', bcdDevice.toHex());
    _writeAttr('$_gadgetPath/bcdUSB', bcdUSB.toHex());

    // Create gadget-level string descriptors
    for (final MapEntry(:key, :value) in strings.entries) {
      final langPath = '$_gadgetPath/strings/${key.value.toHex()}';
      _mkdir(langPath);
      if (value case GadgetStrings(serialnumber: final String serialnumber)) {
        _writeAttr('$langPath/serialnumber', serialnumber);
      }
      if (value.manufacturer case final String manufacturer) {
        _writeAttr('$langPath/manufacturer', manufacturer);
      }
      if (value.product case final String product) {
        _writeAttr('$langPath/product', product);
      }
    }

    // Create config and link functions
    final configPath = '$_gadgetPath/configs/c.${config.index}';
    _mkdir(configPath);

    // Write configuration attributes
    if (config.attributes case GadgetAttributes(:final int value)) {
      _writeAttr('$configPath/bmAttributes', value.toHex());
    }
    if (config.maxPower case GadgetMaxPower(:final int value)) {
      _writeAttr('$configPath/MaxPower', value.toString());
    }

    // Create configuration string descriptors
    for (final MapEntry(:key, :value) in config.strings.entries) {
      final langPath = '$configPath/strings/${key.value.toHex()}';
      _mkdir(langPath);
      _writeAttr('$langPath/configuration', value);
    }

    // Create function directories and prepare them (before linking)
    // Attributes must be written before symlinking to avoid "Device or resource busy" errors
    for (final function in config.functions) {
      final configfsName = function.getConfigfsInstanceName();
      final functionPath = '$_gadgetPath/functions/$configfsName';

      _log('Creating function directory: $configfsName');
      _mkdir(functionPath);

      _log('Preparing function: ${function.name}');
      try {
        function.prepare(functionPath);
      } catch (e) {
        _log('Function preparation failed: $e');
        function.dispose();
        rethrow;
      }
    }

    // Create symlinks after all functions are prepared
    for (final function in config.functions) {
      final configfsName = function.getConfigfsInstanceName();
      final functionPath = '$_gadgetPath/functions/$configfsName';

      // Link function to configuration (after preparation)
      _symlink(functionPath, '$configPath/$configfsName');
    }

    _log('Gadget structure created successfully');
  }

  /// Unbinds the gadget from the UDC and cleans up resources.
  ///
  /// This method safely tears down the gadget in reverse order:
  /// 1. Unbind from UDC (deactivate hardware)
  /// 2. Dispose all functions (close files, unmount filesystems)
  /// 3. Remove symlinks (configuration links)
  /// 4. Remove directories (functions, configs, gadget)
  ///
  /// If the gadget is not bound, this is a no-op. This method never throws;
  /// errors are logged as warnings.
  ///
  /// Example:
  /// ```dart
  /// gadget.unbind();  // Safe to call even if not bound
  /// ```
  void unbind() {
    if (_boundUdc != null) {
      _log('Unbinding from UDC: $_boundUdc');
      try {
        _writeAttr('$_gadgetPath/UDC', '');
      } catch (e) {
        _log('Warning: Failed to unbind from UDC: $e');
      }
      _boundUdc = null;
    }

    for (final function in config.functions) {
      try {
        function.dispose();
        _log('Disposed function: ${function.name}');
      } catch (e) {
        _log('Warning: Failed to dispose function ${function.name}: $e');
      }
    }

    for (final link in _createdSymlinks.reversed) {
      try {
        Link(link).deleteSync();
      } catch (e) {
        _log('Warning: Failed to remove symlink $link: $e');
      }
    }
    _createdSymlinks.clear();

    for (final dir in _createdDirs.reversed) {
      try {
        Directory(dir).deleteSync();
      } catch (e) {
        _log('Warning: Failed to remove directory $dir: $e');
      }
    }
    _createdDirs.clear();
  }

  /// Binds the gadget to the specified UDC.
  ///
  /// This tells the kernel to activate the USB device controller and
  /// start responding to USB host enumeration.
  void _bindToUdc(String udcName) {
    _ensureUdcAvailable(udcName);
    _writeAttr('$_gadgetPath/UDC', udcName);
    _boundUdc = udcName;
  }

  /// Ensures the UDC is available by unbinding any existing gadget using it.
  ///
  /// Scans all gadgets in configfs and unbinds any that are using the target
  /// UDC. This prevents "device or resource busy" errors.
  void _ensureUdcAvailable(String udcName) {
    final gadgetsDir = Directory('/sys/kernel/config/usb_gadget');
    if (!gadgetsDir.existsSync()) return;

    for (final gadgetEntity in gadgetsDir.listSync()) {
      if (gadgetEntity is! Directory) continue;

      final gadgetPath = gadgetEntity.path;
      final gadgetName = gadgetPath.split('/').last;

      // Skip our own gadget
      if (gadgetName == name) continue;

      final udcFile = File('$gadgetPath/UDC');
      if (!udcFile.existsSync()) continue;

      try {
        final currentUdc = udcFile.readAsStringSync().trim();
        if (currentUdc == udcName) {
          _log('UDC $udcName is bound to gadget "$gadgetName", unbinding...');
          udcFile.writeAsStringSync('');
        }
      } catch (e) {
        _log('Warning: Could not check/unbind gadget "$gadgetName": $e');
      }
    }
  }

  /// Finds an available UDC by scanning /sys/class/udc.
  ///
  /// Returns the UDC name if exactly one is found. Throws if zero or
  /// multiple UDCs are available (ambiguous case requires explicit selection).
  String _findUdc() {
    final udcDir = Directory('/sys/class/udc');
    if (!udcDir.existsSync()) {
      throw StateError(
        'UDC directory not found. Is USB gadget support enabled?',
      );
    }

    final udcs = <String>[];
    for (final entity in udcDir.listSync()) {
      udcs.add(entity.path.split('/').last);
    }

    if (udcs.isEmpty) {
      throw StateError('No UDC available. Is USB device controller enabled?');
    }
    if (udcs.length > 1) {
      throw StateError(
        'Multiple UDCs available, please specify one using setUdc()',
      );
    }
    return udcs.first;
  }

  /// Creates a directory and tracks it for cleanup.
  void _mkdir(String path) {
    Directory(path).createSync(recursive: true);
    _createdDirs.add(path);
  }

  /// Writes a value to a configfs attribute file.
  ///
  /// Provides helpful error messages for common failures (e.g., UDC busy).
  void _writeAttr(String path, String value) {
    try {
      File(path).writeAsStringSync(value);
    } catch (e) {
      if (path.endsWith('/UDC') && e.toString().contains('errno = 16')) {
        throw FileSystemException(
          'Failed to bind to UDC: Device or resource busy. '
          'This usually means a function is not ready yet.',
          path,
        );
      }
      throw FileSystemException('Failed to write attribute: $e', path);
    }
  }

  /// Creates a symbolic link and tracks it for cleanup.
  void _symlink(String target, String link) {
    final linkFile = Link(link);
    if (linkFile.existsSync()) {
      linkFile.deleteSync();
    }
    linkFile.createSync(target);
    _createdSymlinks.add(link);
  }
}
