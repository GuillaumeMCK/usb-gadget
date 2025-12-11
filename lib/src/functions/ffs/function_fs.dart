import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '/usb_gadget.dart';

/// FunctionFs lifecycle states
enum FunctionFsState {
  /// Initial state, not yet prepared
  uninitialized,

  /// Currently mounting and writing descriptors
  preparing,

  /// Ready for UDC binding
  ready,

  /// Bound to UDC but not yet configured
  bound,

  /// Enabled and actively transferring data
  enabled,

  /// Suspended by host
  suspended,

  /// Disposed and cleaned up
  disposed,
}

/// Configuration for FunctionFs mounting and operation
class FunctionFsConfig {
  const FunctionFsConfig({this.mountPoint, this.autoMount = true});

  /// Custom mount point (default: /dev/ffs/{name})
  final String? mountPoint;

  /// Automatically mount FunctionFs if not mounted
  final bool autoMount;
}

/// User Space FunctionFs Gadget Function.
///
/// Implements USB functions in userspace using the Linux FunctionFs API.
/// This allows full control over USB endpoints and protocol handling from Dart.
class FunctionFs extends GadgetFunction with USBGadgetLogger {
  FunctionFs({
    required super.name,
    this.descriptors = const [],
    this.speeds = const {USBSpeed.fullSpeed, USBSpeed.highSpeed},
    this.strings = const {},
    this.flags = const FunctionFsFlags(),
    this.config = const FunctionFsConfig(),
  }) : _mountPoint = config.mountPoint ?? '/dev/ffs/$name';

  @override
  GadgetFunctionType get type => .ffs;

  /// Base descriptor templates that will be generated for each speed.
  final List<USBDescriptor> descriptors;

  /// USB speeds to generate descriptors for.
  final Set<USBSpeed> speeds;

  /// String descriptors indexed by language ID (e.g., 0x0409 for en-US)
  final Map<USBLanguageId, List<String>> strings;

  /// FunctionFs configuration flags
  final FunctionFsFlags flags;

  /// FunctionFs configuration
  final FunctionFsConfig config;

  /// Mount point for the FunctionFs filesystem
  final String _mountPoint;

  /// Current state of the function
  FunctionFsState _state = .uninitialized;

  /// Control endpoint (ep0) file
  late EndpointControlFile _ep0;

  /// Map of endpoint address to endpoint file
  final Map<int, EndpointFile> _endpointByAddress = {};

  /// State stream
  final StreamController<FunctionFsState> _stateController = .broadcast();

  /// Stream controller for FunctionFs events
  final StreamController<FunctionFsEvent> _eventController = .broadcast();

  /// Subscription for EP0 event reading
  StreamSubscription<FunctionFsEvent>? _eventSubscription;

  /// Stream of FunctionFs events (bind, unbind, enable, disable, setup, etc.)
  Stream<FunctionFsEvent> get events => _eventController.stream;

  /// Control endpoint accessor
  EndpointControlFile get ep0 => _ep0;

  /// Current lifecycle state
  FunctionFsState get state => _state;

  /// Mount point for FunctionFs
  String get mountPoint => _mountPoint;

  /// Future that completes when the function is ready for UDC binding.
  @override
  Future<void> waitState(FunctionFsState state) {
    if (state == this.state) return Future.value();
    if (state == FunctionFsState.disposed) {
      throw StateError('Cannot wait for disposed state');
    }
    return _stateController.stream.where((s) => s == state).first;
  }

  @override
  String get configfsName => 'ffs.$name';

  @override
  Future<void> prepare(String path) async {
    if (_state != FunctionFsState.uninitialized) {
      return log?.error(
        'Cannot prepare function in state $_state. Function must be in uninitialized state.',
      );
    }
    _setState(.preparing);
    try {
      log?.info('Mount point: $_mountPoint');
      log?.info('Configfs path: $path');
      final ep0Path = '$_mountPoint/ep0';
      _ep0 = EndpointControlFile(
        ep0Path,
        mountPoint: _mountPoint,
        mountSource: name,
      );
      await _ep0.open();
      log?.info('Opened EP0 control endpoint at $ep0Path (fd: ${_ep0.fd})');

      final generatedFsDs = _generateDescriptorsForSpeed(.fullSpeed);
      final generatedHsDs = _generateDescriptorsForSpeed(.highSpeed);
      final generatedSsDs = _generateDescriptorsForSpeed(.superSpeed);
      final generatedSspDs = _generateDescriptorsForSpeed(.superSpeedPlus);

      final effectiveFlags = FunctionFsFlags(
        hasFullSpeed: generatedFsDs != null,
        hasHighSpeed: generatedHsDs != null,
        hasSuperSpeed: generatedSsDs != null,
        hasSuperSpeedPlus: generatedSspDs != null,
        allControlRequests: flags.allControlRequests,
        config0Settings: flags.config0Settings,
        virtualAddressBased: flags.virtualAddressBased,
      );
      log?.info('Flags: $effectiveFlags');

      final descBuilder = FunctionFsDescriptorsBuilder()
        ..flags = effectiveFlags;
      if (generatedFsDs != null) descBuilder.fullSpeed = generatedFsDs;
      if (generatedHsDs != null) descBuilder.highSpeed = generatedHsDs;
      if (generatedSsDs != null) descBuilder.superSpeed = generatedSsDs;
      if (generatedSspDs != null) descBuilder.superSpeedPlus = generatedSspDs;

      log?.info('Writing descriptors to EP0...');
      final descriptor = descBuilder.build().toBytes();
      if (log?.level == .debug) descriptor.xxd();
      _ep0.write(descriptor);

      if (strings.isNotEmpty) {
        log?.info(
          'Writing string descriptors (${strings.length} language(s))...',
        );
        final builder = FunctionFsStringsBuilder();
        for (final entry in strings.entries) {
          builder.addLanguage(
            LanguageStrings(language: entry.key, strings: entry.value),
          );
        }
        final stringBytes = builder.build().toBytes();
        if (log?.level == .debug) stringBytes.xxd();
        _ep0.write(stringBytes);
      }

      _openEndpointFiles();
      _startEventListener();
      _setState(.ready);
      log?.success('Ready for UDC binding');
    } catch (err, st) {
      _setState(.uninitialized);
      log?.error('Error preparing FunctionFs function: $err', err, st);
      rethrow;
    }
  }

  @override
  @mustCallSuper
  Future<void> dispose() async {
    log?.info('Disposing function (current state: $_state)');
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    if (_endpointByAddress.isNotEmpty) {
      for (final ep in _endpointByAddress.values) {
        try {
          log?.info('Closing endpoint: ${ep.fd}');
          ep.close();
        } catch (err) {
          log?.warn('Failed to close endpoint: $err');
        }
      }
      _endpointByAddress.clear();
    }

    try {
      log?.info('Closing EP0 and unmounting FunctionFs...');
      _ep0.close();
    } catch (err) {
      log?.warn('Failed to close EP0: $err');
    }

    await _eventController.close();
    _setState(.disposed);
  }

  /// Generates descriptors for a specific speed if enabled.
  DescriptorSet? _generateDescriptorsForSpeed(USBSpeed speed) {
    if (descriptors.isEmpty || !speeds.contains(speed)) return null;
    return DescriptorGenerator.generateForSpeed(descriptors, speed);
  }

  /// Update internal state and notify listeners (no-op when same state).
  void _setState(FunctionFsState newState) {
    if (_state == newState) return;
    log?.info('$_state -> $newState');
    _state = newState;
    if (_stateController.hasListener) _stateController.add(newState);
  }

  /// Opens all endpoint files after descriptors have been written to EP0.
  void _openEndpointFiles() {
    var index = 1; // Start from ep1
    for (final desc in descriptors) {
      if (desc is! EndpointTemplate) continue;
      final epPath = '$_mountPoint/ep$index';
      final endpoint = desc.address.isIn
          ? EndpointInFile(epPath)
          : EndpointOutFile(epPath, config: desc.config);
      _endpointByAddress[desc.address.value] = endpoint;
      endpoint.open();
      log?.info('Opened ${desc.address} at $epPath (fd: ${endpoint.fd})');
      index++;
    }
  }

  /// Starts listening for events from EP0 using Linux AIO.
  void _startEventListener() {
    log?.info('Starting event listener on EP0');
    _eventSubscription = _ep0.stream().listen(
      (event) {
        _eventController.add(event);
        _handleEvent(event);
      },
      onError: (Object err, StackTrace st) {
        log?.error('Error in EP0 event stream: $err', err, st);
      },
      onDone: () {
        log?.warn('EP0 event stream closed');
      },
      cancelOnError: false,
    );
  }

  /// Internal event handler that dispatches to subclass hooks.
  void _handleEvent(FunctionFsEvent event) => switch (event.type) {
    .bind => onBind(),
    .unbind => onUnbind(),
    .enable => onEnable(),
    .disable => onDisable(),
    .suspend => onSuspend(),
    .resume => onResume(),
    .setup when event is SetupEvent => onSetup(
      event.bRequestType,
      event.bRequest,
      event.wValue,
      event.wIndex,
      event.wLength,
    ),
    .setup => throw StateError('Setup event is not a SetupEvent instance'),
  };

  /// Gets an endpoint by number and direction.
  T getEndpoint<T extends EndpointFile>(int number) {
    assert(
      number >= 0 && number <= 15,
      'Endpoint number must be between 0 and 15',
    );
    final address = T == EndpointInFile ? 0x80 | number : number;
    final endpoint = _endpointByAddress[address];
    if (endpoint == null) {
      throw StateError(
        'No endpoint found with address ${address.toHex()}. '
        'Available: ${_endpointByAddress.keys.map((k) => k.toHex()).join(', ')}',
      );
    }
    if (endpoint is! T) {
      throw StateError(
        'Endpoint ${address.toHex()} is ${endpoint.runtimeType}, not $T',
      );
    }
    return endpoint;
  }

  // ============================================================================
  // Lifecycle Hook Methods
  // ============================================================================

  /// Called when the function is bound to the UDC.
  @mustCallSuper
  void onBind() {
    _setState(.bound);
  }

  /// Called when the function is unbound from the UDC.
  @mustCallSuper
  void onUnbind() {
    _setState(.ready);
  }

  /// Called when the host configures the device.
  @mustCallSuper
  void onEnable() {
    _setState(.enabled);
  }

  /// Called when the host de-configures the device.
  @mustCallSuper
  void onDisable() {
    _setState(.bound);
  }

  /// Called when the host suspends the USB bus.
  @mustCallSuper
  void onSuspend() {
    _setState(.suspended);
  }

  /// Called when the host resumes the USB bus after suspend.
  @mustCallSuper
  void onResume() {
    _setState(.enabled);
  }

  /// Called when a USB control request is received on EP0.
  @mustCallSuper
  void onSetup(int requestType, int request, int value, int index, int length) {
    log?.debug(
      'Setup Request: '
      'bmRequestType=${requestType.toHex()}'
      'bRequest=${request.toHex()}'
      'wValue=${value.toHex()}'
      'wIndex=${index.toHex()}'
      'wLength=${length.toHex()}',
    );

    final type = USBRequestType.fromByte(requestType);
    final recipient = USBRecipient.fromByte(requestType);
    final direction = USBDirection.fromByte(requestType);

    if (type != .standard) {
      log?.warn('Non-standard request, halting');
      return _ep0.halt();
    }

    final usbRequest = USBRequest.fromValue(request);

    // GET_STATUS
    if (usbRequest == .getStatus && direction.isIn && length == 2) {
      if (value != 0) return _ep0.halt();
      var status = 0;
      switch (recipient) {
        case .interface:
          if (index != 0) return _ep0.halt();
          status = 0;
        case .endpoint:
          final endpoint = _endpointByAddress[index];
          if (endpoint == null) return _ep0.halt();
          status = endpoint.isHalted ? 1 : 0;
        default:
          return _ep0.halt();
      }
      final bytes = ByteData(2)..setUint16(0, status, Endian.little);
      return _ep0.write(bytes.buffer.asUint8List());
    }

    // CLEAR_FEATURE / SET_FEATURE
    final isSet = usbRequest == .setFeature;
    final isClear = usbRequest == .clearFeature;
    if ((isSet || isClear) && direction.isOut && length == 0) {
      final enable = isSet;
      if (recipient == .endpoint && value == USBFeature.endpointHalt.value) {
        final endpoint = _endpointByAddress[index];
        if (endpoint == null) return _ep0.halt();
        if (enable) {
          endpoint.halt();
        } else {
          endpoint.clearHalt();
        }
        _ep0.read(0);
        return;
      }
    }

    log?.warn('Unhandled: type=${requestType.toHex()} req=${request.toHex()}');
    return _ep0.halt();
  }
}
