import 'dart:async';
import 'dart:io';

import '/usb_gadget.dart';

/// USB Device Controller (UDC) states.
///
/// Represents the lifecycle states of a USB device as reported by the
/// Linux USB Gadget framework through sysfs (`/sys/class/udc/{udc}/state`).
///
/// Common lifecycle:
/// - [notAttached]: No USB cable connected.
/// - [attached]: USB cable connected, but not enumerated.
/// - [powered]: Host is providing power.
/// - [default_]: Device is being enumerated (handshake phase).
/// - [addressed]: Device has been assigned a USB address.
/// - [configured]: Device is fully configured and ready for data transfer.
/// - [suspended]: Device has been suspended by the host to save power.
enum USBDeviceState {
  /// No USB cable connected to the device.
  notAttached('not-attached'),

  /// USB cable is connected but device has not been enumerated by the host.
  attached('attached'),

  /// Host is providing power to the device.
  powered('powered'),

  /// Device is being enumerated by the host (initial handshake phase).
  default_('default'),

  /// Device has been assigned a USB address by the host.
  addressed('addressed'),

  /// Device is fully configured and ready for data transfer.
  /// This is the state you typically wait for before sending/receiving data.
  configured('configured'),

  /// Device has been suspended by the host to save power.
  suspended('suspended');

  const USBDeviceState(this.value);

  /// The string value as it appears in the UDC state file.
  final String value;

  /// Parses a string value into a [USBDeviceState].
  /// If the string does not match any state, returns [defaultValue].
  static USBDeviceState fromString(
    String state, {
    USBDeviceState defaultValue = .notAttached,
  }) => USBDeviceState.values.firstWhere(
    (e) => e.value == state,
    orElse: () => defaultValue,
  );
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
class Gadget with USBGadgetLogger {
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
  /// - [logLevel]: Logging verbosity level
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
    LogLevel? logLevel,
    Map<USBLanguageId, GadgetStrings>? strings,
  }) : strings = {...?strings},
       assert(name.isNotEmpty, 'Gadget name cannot be empty'),
       _gadgetPath = '/sys/kernel/config/usb_gadget/$name' {
    Logger.init(level: logLevel);
  }

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

    log?.debug('Starting bind process');
    final targetUdc = udc ?? _findUdc();
    log?.debug('Using UDC: $targetUdc');

    try {
      _createGadget();
      await _setupFunctions();
      log?.info('All functions are ready, binding to UDC...');
      _bindToUdc(targetUdc);
      log?.success('Gadget bound to UDC: $_boundUdc');
    } catch (err, st) {
      log?.error('Bind failed: $err', err, st);
      unbind();
      rethrow;
    }
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
      log?.debug('Unbinding from UDC: $_boundUdc');
      try {
        _writeAttr('$_gadgetPath/UDC', '');
      } catch (err) {
        log?.warn('Failed to unbind from UDC: $err');
      }
      _boundUdc = null;
    }

    for (final function in config.functions) {
      try {
        function.dispose();
        log?.debug('Disposed function: ${function.name}');
      } catch (err) {
        log?.warn('Failed to dispose function ${function.name}: $err');
      }
    }

    for (final link in _createdSymlinks.reversed) {
      try {
        Link(link).deleteSync();
      } catch (err) {
        log?.warn('Failed to remove symlink $link: $err');
      }
    }
    _createdSymlinks.clear();

    for (final dir in _createdDirs.reversed) {
      try {
        Directory(dir).deleteSync();
      } catch (err) {
        log?.warn('Failed to remove directory $dir: $err');
      }
    }
    _createdDirs.clear();
  }

  /// Waits for the USB device to reach the specified state.
  ///
  /// This method monitors the UDC (USB Device Controller) state file to
  /// determine when the device has reached the target state. This is useful
  /// for knowing when the host has fully enumerated and configured the device
  /// before starting data transfers.
  ///
  /// Parameters:
  /// - [targetState]: The USB state to wait for (typically [USBDeviceState.configured])
  /// - [pollInterval]: How often to check the state (default: 100ms)
  /// - [timeout]: Maximum time to wait (default: 5 seconds)
  ///
  /// Returns a Future that completes when the target state is reached.
  ///
  /// Throws:
  /// - [StateError] if the gadget is not bound to a UDC or state file doesn't exist
  /// - [TimeoutException] if the target state is not reached within the timeout
  ///
  /// Example:
  /// ```dart
  /// await gadget.bind();
  /// await gadget.waitForState(USBDeviceState.configured);
  /// // Device is now ready to send/receive data
  /// ```
  Future<void> waitForState(
    USBDeviceState targetState, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_boundUdc == null) {
      throw StateError('Gadget is not bound to any UDC');
    }

    final stateFile = File('/sys/class/udc/$_boundUdc/state');
    if (!stateFile.existsSync()) {
      throw StateError('UDC state file not found: ${stateFile.path}');
    }

    final startTime = DateTime.now();

    while (true) {
      if (DateTime.now().difference(startTime) > timeout) {
        final currentState = getCurrentUsbState();
        throw TimeoutException(
          'Timeout waiting for USB state "${targetState.value}". '
          'Current state: ${currentState.value}',
          timeout,
        );
      }

      // Read current state
      final stateStr = stateFile.readAsStringSync().trim();
      final state = USBDeviceState.fromString(stateStr);

      if (state == targetState) {
        return;
      }

      // Wait before next poll
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Gets the current USB device state.
  ///
  /// Returns the current state or null if the gadget is not bound or
  /// the state cannot be determined.
  USBDeviceState getCurrentUsbState() {
    if (_boundUdc == null) return .notAttached;

    final stateFile = File('/sys/class/udc/$_boundUdc/state');
    if (!stateFile.existsSync()) return .notAttached;

    final stateStr = stateFile.readAsStringSync().trim();
    return USBDeviceState.fromString(stateStr);
  }

  /// Stream of USB device state changes.
  ///
  /// Monitors the UDC state file and emits new states as they change.
  /// The stream completes when the gadget is unbound.
  ///
  /// Parameters:
  /// - [pollInterval]: How often to check for state changes (default: 100ms)
  ///
  /// Example:
  /// ```dart
  /// gadget.stateStream().listen((state) {
  ///   print('USB state changed to: ${state.value}');
  ///   if (state.isConfigured) {
  ///     // Ready to transfer data
  ///   }
  /// });
  /// ```
  Stream<USBDeviceState> stateStream({
    Duration pollInterval = const Duration(milliseconds: 50),
  }) async* {
    if (_boundUdc == null) {
      throw StateError('Gadget is not bound to any UDC');
    }

    USBDeviceState? lastState;

    while (_boundUdc != null) {
      final currentState = getCurrentUsbState();

      if (currentState != lastState) {
        lastState = currentState;
        yield currentState;
      }

      await Future<void>.delayed(pollInterval);
    }
  }

  /// Waits for all functions to reach the specified state.
  ///
  /// This ensures synchronized initialization - no function is left behind.
  Future<void> _setupFunctions() async {
    final stream = stateStream();
    for (final function in config.functions) {
      function.usbDeviceStateStream = stream;
      if (function.type == .ffs) {
        await function.waitState(.ready);
      }
    }
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
    log?.info('Creating gadget structure at $_gadgetPath');
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
      log?.info('Preparing function: ${function.name}');
      final configfsName = function.configfsName;
      final functionPath = '$_gadgetPath/functions/$configfsName';
      _mkdir(functionPath);
      try {
        function.prepare(functionPath);
      } catch (err, st) {
        log?.error('Function preparation failed: $err', err, st);
        function.dispose();
        rethrow;
      }
    }

    // Create symlinks after all functions are prepared
    for (final function in config.functions) {
      final functionPath = '$_gadgetPath/functions/${function.configfsName}';
      // Link function to configuration (after preparation)
      _symlink(functionPath, '$configPath/${function.configfsName}');
    }
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
          log?.debug(
            'UDC $udcName is bound to gadget "$gadgetName", unbinding...',
          );
          udcFile.writeAsStringSync('');
        }
      } catch (err) {
        log?.warn('Could not check/unbind gadget "$gadgetName": $err');
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
    } catch (err) {
      throw FileSystemException(
        'Failed to write attribute at $path with value "$value": $err',
      );
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
