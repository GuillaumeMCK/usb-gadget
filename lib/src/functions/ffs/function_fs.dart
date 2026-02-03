import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '/src/logger/logger.dart';
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

/// User Space FunctionFs Gadget Function.
///
/// Implements USB functions in userspace using the Linux FunctionFs API.
/// This allows full control over USB endpoints and protocol handling from Dart.
class FunctionFs extends GadgetFunction with USBGadgetLogger {
  FunctionFs({
    required super.name,
    this.descriptors = const [],
    this.speeds = const {.fullSpeed, .highSpeed},
    this.strings = const {},
    this.flags = const FunctionFsFlags(),
    String? mountPoint,
  }) : _mountPoint = mountPoint ?? '/dev/ffs/$name';

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

  /// Mount point for the FunctionFs filesystem
  final String _mountPoint;

  /// Current state of the function
  FunctionFsState _state = .uninitialized;

  /// Control endpoint (ep0) file
  late EndpointControlFile _ep0;

  /// Map of endpoints by their addresses
  final Map<EndpointAddress, EndpointFile> _endpoints = {};

  /// Per-endpoint status buffers, keyed by [EndpointAddress].
  /// Each value is the raw 2-byte payload returned by GET_STATUS (endpoint).
  /// Bit 0 of byte 0: endpoint halted (STALL).
  /// Entries are created on first SET_FEATURE and persist for the lifetime
  /// of the function so that GET_STATUS can return them without allocation.
  final Map<EndpointAddress, Uint8List> _endpointStatus = {};

  /// Raw 2-byte device-status buffer, returned verbatim by GET_STATUS (device).
  /// Bit 0: self-powered (0 = bus-powered, 1 = self-powered).
  /// Bit 1: remote-wakeup enabled.
  /// Set bit 0 after construction when the powered state of your hardware
  /// is known; bit 1 is managed by SET/CLEAR_FEATURE (DEVICE_REMOTE_WAKEUP).
  final Uint8List _deviceStatus = Uint8List(2);

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

  /// Configfs name for the function
  @override
  String get configfsName => 'ffs.$name';

  /// Waits until the function reaches the specified state.
  @override
  Future<void> waitState(FunctionFsState state) => state != _state
      ? _stateController.stream.where((s) => s == state).first
      : .value();

  @override
  Future<void> prepare(String path) async {
    if (_state != .uninitialized) {
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

      final descriptor = descBuilder.build().toBytes();
      log?.debug(
        'Writing descriptors to EP0 (${descriptor.length}) :${descriptor.xxd()}',
      );

      // Write descriptors with error recovery
      try {
        _ep0.write(descriptor);
      } catch (e) {
        log?.error('Failed to write descriptors: $e');
        await _ep0.close();
        _setState(.uninitialized);
        rethrow;
      }

      if (strings.isNotEmpty) {
        final builder = FunctionFsStringsBuilder();
        for (final entry in strings.entries) {
          builder.addLanguage(
            LanguageStrings(language: entry.key, strings: entry.value),
          );
        }
        final stringBytes = builder.build().toBytes();
        log?.debug('Writing strings to EP0:${stringBytes.xxd()}');

        try {
          _ep0.write(stringBytes);
        } catch (e) {
          log?.error('Failed to write strings: $e');
          await _ep0.close();
          _setState(.uninitialized);
          rethrow;
        }
      }

      // Open endpoint files with error recovery
      try {
        await _openEndpointFiles();
      } catch (e) {
        log?.error('Failed to open endpoint files: $e');
        await _ep0.close();
        _setState(.uninitialized);
        rethrow;
      }

      _startEventListener();
      _setState(.ready);
      log?.debug('Ready for UDC binding');
    } catch (err, st) {
      _setState(.uninitialized);
      log?.error('Error preparing FunctionFs function: $err', err, st);
      rethrow;
    }
  }

  @override
  @mustCallSuper
  void release() {
    if (!isReleased) {
      log?.info('Releasing function (current state: $_state)');
      _eventSubscription?.cancel();
      _eventSubscription = null;

      if (_endpoints.isNotEmpty) {
        for (final ep in _endpoints.values) {
          try {
            log?.info('Closing endpoint: ${ep.fd}');
            ep.close();
          } catch (err) {
            log?.warn('Failed to close endpoint: $err');
          }
        }
        _endpoints.clear();
      }

      try {
        log?.info('Closing EP0 and unmounting FunctionFs...');
        _ep0.close();
      } catch (err) {
        log?.warn('Failed to close EP0: $err');
      }

      _eventController.close();
      _setState(.disposed);
      super.release();
    }
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
  ///
  /// FunctionFS uses sequential endpoint numbering: ep1, ep2, ep3, etc.
  /// The order matches the order of EndpointTemplate descriptors.
  ///
  /// If any endpoint fails to open, all previously opened endpoints are closed
  /// and the error is propagated.
  Future<void> _openEndpointFiles() async {
    var index = 1; // Start from ep1 (ep0 is control)
    final openedEndpoints = <EndpointAddress, EndpointFile>{};

    try {
      for (final desc in descriptors) {
        if (desc is! EndpointTemplate) continue;

        final epPath = '$_mountPoint/ep$index';
        final endpoint = switch (desc.address.direction) {
          .in_ => EndpointInFile(epPath),
          .out => EndpointOutFile(epPath, config: desc.config),
        };

        try {
          await endpoint.open();
          openedEndpoints[desc.address] = endpoint;
          log?.info('Opened ${desc.address} at $epPath (fd: ${endpoint.fd})');
        } catch (e) {
          log?.error('Failed to open ${desc.address} at $epPath: $e');
          // Close all previously opened endpoints
          await _closeEndpoints(openedEndpoints);
          rethrow;
        }

        index++;
      }

      // All endpoints opened successfully, commit to instance map
      _endpoints.addAll(openedEndpoints);
    } catch (e) {
      // Ensure cleanup on any error
      await _closeEndpoints(openedEndpoints);
      rethrow;
    }
  }

  /// Closes a map of endpoints (helper for error recovery).
  Future<void> _closeEndpoints(
    Map<EndpointAddress, EndpointFile> endpoints,
  ) async {
    for (final ep in endpoints.values) {
      try {
        await ep.close();
      } catch (e) {
        log?.warn('Error closing endpoint during cleanup: $e');
      }
    }
    endpoints.clear();
  }

  /// Starts listening for events from EP0.
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
      event.bmRequestType,
      event.bRequest,
      event.wValue,
      event.wIndex,
      event.wLength,
    ),
    .setup => throw StateError('Setup event is not a SetupEvent instance'),
  };

  /// Gets an endpoint by number and direction.
  T getEndpoint<T extends EndpointFile>(EndpointNumber number) {
    final address = switch (T) {
      const (EndpointInFile) => EndpointAddress.in_(number),
      const (EndpointOutFile) => EndpointAddress.out(number),
      Type() => throw StateError('Unsupported endpoint type $T'),
    };
    final endpoint = _endpoints[address];
    if (endpoint == null) {
      throw StateError('No endpoint found with the number $number');
    }
    if (endpoint is! T) {
      throw StateError(
        'Endpoint $number is not of expected type ${T.runtimeType}',
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
  void onSetup(
    int bmRequestType,
    int bRequest,
    int wValue,
    int wIndex,
    int wLength,
  ) {
    log?.debug(
      'Standard Setup: '
      'bmRequestType=${bmRequestType.toHex()} '
      'bRequest=${bRequest.toHex()} '
      'wValue=${wValue.toHex()} '
      'wIndex=${wIndex.toHex()} '
      'wLength=${wLength.toHex()}',
    );

    final recipient = USBRecipient.fromByte(bmRequestType);
    final type = USBRequestType.fromByte(bmRequestType);
    final direction = USBDirection.fromByte(bmRequestType);
    final request = USBRequest.fromByte(bRequest);
    final feature = USBFeature.fromByte(wValue.lowByte, recipient);
    final address = EndpointAddress.fromByte(wIndex.lowByte);

    if (type != .standard) {
      log?.warn('Non-standard request, halting');
      return _ep0.halt();
    }

    switch ((request, direction, feature, recipient)) {
      // Clear endpoint halt
      case (.clearFeature, .out, .endpointHalt, _):
        getEndpoint<EndpointInFile>(address.number).clearHalt();
        // clear bit 0 (halted)
        _endpointStatus[address]?[0] &= 0x01;
        log?.debug('Cleared halt on $address');
        _ep0.halt();

      // Set endpoint halt
      case (.setFeature, .out, .endpointHalt, _):
        _endpoints[address]?.halt();
        // set bit 0 (halted) if not already present
        (_endpointStatus[address] ??= Uint8List(2))[0] |= 0x01;
        _ep0.halt();

      // Get endpoint status - IN transfer
      case (.getStatus, .in_, _, .endpoint):
        final endpoint = _endpoints[address];
        if (endpoint != null) {
          final status = _endpointStatus[address] ??= Uint8List(2);
          _ep0.write(status);
          log?.debug(
            'Returned status for $address (halted: ${status[0].bitAt(0)})',
          );
        } else {
          log?.warn('Cannot get status for $address: Endpoint not found');
          _ep0.halt();
        }

      // Get device status - IN transfer
      case (.getStatus, .in_, _, .device):
        _ep0.write(_deviceStatus);
        log?.debug(
          'Returned device status '
          '(self-powered: ${_deviceStatus[0].bitAt(0)}, '
          'remote-wakeup: ${_deviceStatus[0].bitAt(1)})',
        );

      // Set device remote wakeup - OUT transfer
      case (.setFeature, .out, .deviceRemoteWakeup, _):
        _deviceStatus[0] |= 0x02; // set bit 1 (remote wakeup)
        _ep0.halt(); // ACK the OUT transfer
        log?.debug('Enabled remote wakeup');

      // Clear device remote wakeup - OUT transfer
      case (.clearFeature, .out, .deviceRemoteWakeup, _):
        _deviceStatus[0] &= 0x02; // clear bit 1 (remote wakeup)
        _ep0.halt(); // ACK the OUT transfer
        log?.debug('Disabled remote wakeup');

      default:
        log?.warn(
          'Unhandled: request=$request, direction=$direction, '
          'feature=$feature, recipient=$recipient',
        );
        _ep0.halt();
    }
  }
}
