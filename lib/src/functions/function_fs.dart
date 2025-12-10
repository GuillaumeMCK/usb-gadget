import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '/src/core/utils.dart';
import '/usb_gadget.dart';

/// FunctionFS lifecycle states
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

/// Configuration for FunctionFS mounting and operation
class FunctionFsConfig {
  const FunctionFsConfig({this.mountPoint, this.autoMount = true});

  /// Custom mount point (default: /dev/ffs/{name})
  final String? mountPoint;

  /// Automatically mount FunctionFS if not mounted
  final bool autoMount;
}

/// User Space FunctionFS Gadget Function.
///
/// Implements USB functions in userspace using the Linux FunctionFS API.
/// This allows full control over USB endpoints and protocol handling from Dart.
///
/// ## Lifecycle
/// 1. **prepare()** - Mount FunctionFS, write descriptors, open endpoints
/// 2. **waitReady** - Block until function signals ready for UDC binding
/// 3. **onBind()** - Function bound to UDC (device visible to host)
/// 4. **onEnable()** - Host configured device (endpoints active)
/// 5. **onDisable()** - Host de-configured device
/// 6. **dispose()** - Clean up all resources
class FunctionFs extends GadgetFunction {
  FunctionFs({
    required super.name,
    this.descriptors = const [],
    this.speeds = const {USBSpeed.fullSpeed, USBSpeed.highSpeed},
    this.strings = const {},
    this.flags = const FunctionFsFlags(),
    this.config = const FunctionFsConfig(),
    super.debug,
  }) : _mountPoint = config.mountPoint ?? '/dev/ffs/$name';

  @override
  GadgetFunctionType get type => .ffs;

  /// Base descriptor templates that will be generated for each speed.
  ///
  /// Use [EndpointTemplate] for endpoints to automatically generate
  /// speed-appropriate packet sizes and intervals.
  final List<USBDescriptor> descriptors;

  /// USB speeds to generate descriptors for.
  ///
  /// Defaults to Full-Speed and High-Speed for maximum compatibility.
  final Set<USBSpeed> speeds;

  /// String descriptors indexed by language ID (e.g., 0x0409 for en-US)
  final Map<USBLanguageId, List<String>> strings;

  /// FunctionFS configuration flags
  final FunctionFsFlags flags;

  /// FunctionFS configuration
  final FunctionFsConfig config;

  /// Mount point for the FunctionFS filesystem
  final String _mountPoint;

  /// Current state of the function
  FunctionFsState _state = .uninitialized;

  /// Control endpoint (ep0) file
  late EndpointControlFile _ep0;

  /// Map of endpoint address to endpoint file
  final Map<int, EndpointFile> _endpointByAddress = {};

  /// State stream
  final StreamController<FunctionFsState> _stateController = .broadcast();

  /// Stream controller for FunctionFS events
  final StreamController<FunctionFsEvent> _eventController = .broadcast();

  /// Subscription for EP0 event reading
  StreamSubscription<FunctionFsEvent>? _eventSubscription;

  /// Stream of FunctionFS events (bind, unbind, enable, disable, setup, etc.)
  Stream<FunctionFsEvent> get events => _eventController.stream;

  /// Control endpoint accessor
  EndpointControlFile get ep0 => _ep0;

  /// Current lifecycle state
  FunctionFsState get state => _state;

  /// Mount point for FunctionFS
  String get mountPoint => _mountPoint;

  /// Future that completes when the function is ready for UDC binding.
  @override
  Future<void> waitState(FunctionFsState state) => switch (state) {
    _ when state == this.state => Future.value(),
    .disposed => throw StateError('Cannot wait for disposed state'),
    _ => _stateController.stream.where((s) => s == state).first,
  };

  @override
  String getConfigfsInstanceName() => 'ffs.$name';

  @override
  Future<void> prepare(String path) async {
    if (_state != FunctionFsState.uninitialized) {
      throw StateError(
        'Cannot prepare function in state $_state. '
        'Function must be in uninitialized state.',
      );
    }

    _setState(.preparing);
    try {
      log('Mount point: $_mountPoint');
      log('Configfs path: $path');
      final ep0Path = '$_mountPoint/ep0';
      _ep0 = EndpointControlFile(
        ep0Path,
        mountPoint: _mountPoint,
        mountSource: name,
        autoMount: config.autoMount,
      )..open();
      log('Opened EP0 control endpoint... at $ep0Path (fd: ${_ep0.fd})');

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

      log('Flags: $effectiveFlags');

      final descriptorBuilder = FunctionFsDescriptorsBuilder()
        ..flags = effectiveFlags;

      if (generatedFsDs != null) {
        descriptorBuilder.fullSpeed = generatedFsDs;
      }
      if (generatedHsDs != null) {
        descriptorBuilder.highSpeed = generatedHsDs;
      }
      if (generatedSsDs != null) {
        descriptorBuilder.superSpeed = generatedSsDs;
      }
      if (generatedSspDs != null) {
        descriptorBuilder.superSpeedPlus = generatedSspDs;
      }

      log('Writing descriptors to EP0...');
      final descriptorBytes = descriptorBuilder.build().toBytes();
      if (debug) {
        descriptorBytes.xxd();
      }
      _ep0.write(descriptorBytes);

      if (strings.isNotEmpty) {
        log('Writing string descriptors (${strings.length} language(s))...');
        final builder = FunctionFSStringsBuilder();
        for (final MapEntry(:key, :value) in strings.entries) {
          builder.addLanguage(LanguageStrings(language: key, strings: value));
        }
        final stringBytes = builder.build().toBytes();
        if (debug) {
          stringBytes.xxd();
        }
        _ep0.write(stringBytes);
      }
      _openEndpointFiles();
      _startEventListener();
      _setState(.ready);
      log('Function prepared and ready for UDC binding');
    } catch (e, st) {
      _setState(.uninitialized);
      log('Failed to prepare function: $e');
      log(st.toString());
      rethrow;
    }
  }

  @override
  @mustCallSuper
  Future<void> dispose() async {
    log('Disposing function (current state: $_state)');

    await _eventSubscription?.cancel();
    _eventSubscription = null;

    if (_endpointByAddress.isNotEmpty) {
      for (final ep in _endpointByAddress.values) {
        try {
          ep.close();
          log('Closing ${_endpointByAddress.length} endpoint(s)...');
        } catch (e) {
          log('Warning: Failed to close endpoint: $e');
        }
      }
      _endpointByAddress.clear();
    }

    try {
      log('Closing EP0 and unmounting FunctionFS...');
      _ep0.close();
    } catch (e) {
      log('Warning: Failed to close EP0: $e');
    }

    await _eventController.close();
    _setState(.disposed);
  }

  /// Generates descriptors for a specific speed if enabled.
  DescriptorSet? _generateDescriptorsForSpeed(USBSpeed speed) {
    return switch ((descriptors, speeds)) {
      ([], _) => null,
      (_, _) when !speeds.contains(speed) => null,
      _ => DescriptorGenerator.generateForSpeed(descriptors, speed),
    };
  }

  /// Update internal state and notify listeners (no-op when same state).
  void _setState(FunctionFsState newState) {
    if (_state == newState) return;
    log('State change: $_state -> $newState');
    _state = newState;
    if (_stateController.hasListener) {
      _stateController.add(newState);
    }
  }

  /// Opens all endpoint files after descriptors have been written to EP0.
  /// NOTE: The kernel creates endpoint files (ep1, ep2, etc.) in SEQUENTIAL
  /// ORDER based on how endpoints appear in descriptors, NOT by their endpoint
  /// addresses.
  void _openEndpointFiles() {
    // Start from ep1
    var index = 1;
    for (final desc in descriptors) {
      if (desc is! EndpointTemplate) {
        continue;
      }
      final epPath = '$_mountPoint/ep$index';
      final epFile = File(epPath);
      if (!epFile.existsSync()) {
        throw StateError(
          'Expected endpoint file $epPath does not exist. '
          'Check that descriptors are valid and endpoints are defined in '
          'order.',
        );
      }
      final endpoint = desc.address.isIn
          ? EndpointInFile(epPath)
          : EndpointOutFile(epPath, config: desc.config);
      _endpointByAddress[desc.address.value] = endpoint;
      endpoint.open();
      if (debug) {
        log('Opened ${desc.address} at $epPath (fd: ${endpoint.fd})');
      }
      index++;
    }

    log('All ${_endpointByAddress.length} endpoint(s) opened successfully');
  }

  /// Starts listening for events from EP0 using Linux AIO.
  ///
  /// FunctionFS signals events (BIND, UNBIND, ENABLE, DISABLE, SETUP, etc.)
  /// by making EP0 readable. We use AIO to read events asynchronously.
  void _startEventListener() {
    log('Starting event listener on EP0');

    _eventSubscription = _ep0.stream().listen(
      (event) {
        try {
          _eventController.add(event);
          _handleEvent(event);
        } catch (e, st) {
          log('Error handling event: $e');
          log(st.toString());
        }
      },
      onError: (Object err, StackTrace st) {
        log('Error in event stream: $err');
        log(st.toString());
      },
      onDone: () {
        log('Event stream closed');
      },
      cancelOnError: false,
    );
  }

  /// Internal event handler that dispatches to subclass hooks.
  void _handleEvent(FunctionFsEvent event) {
    if (debug) {
      log('Event: ${event.type.name}');
    }

    return switch (event.type) {
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
  }

  /// Gets an endpoint by number and direction.
  ///
  /// Type parameter determines direction:
  /// - EndpointInFile: IN endpoint (device to host)
  /// - EndpointOutFile: OUT endpoint (host to device)
  ///
  /// Throws [StateError] if endpoint not found or wrong type.
  T getEndpoint<T extends EndpointFile>(int number) {
    assert(
      number >= 0 && number <= 15,
      'Endpoint number must be between 0 and 15',
    );

    final address = switch (T) {
      const (EndpointInFile) => 0x80 | number,
      const (EndpointOutFile) => number,
      _ => throw StateError('Unknown endpoint type $T'),
    };

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
  ///
  /// At this point the USB device is visible to the host, but not yet
  /// configured. Endpoints are not yet active.
  @mustCallSuper
  void onBind() {
    _setState(.bound);
  }

  /// Called when the function is unbound from the UDC.
  ///
  /// The USB device is no longer visible to the host.
  @mustCallSuper
  void onUnbind() {
    _setState(.ready);
  }

  /// Called when the host configures the device.
  ///
  /// This is when endpoints become active and the device can transfer data.
  /// Called on SET_CONFIGURATION or after SET_INTERFACE.
  @mustCallSuper
  void onEnable() {
    _setState(.enabled);
  }

  /// Called when the host de-configures the device.
  ///
  /// Endpoints are no longer active. This happens on USB reset or when
  /// the host selects a different configuration.
  @mustCallSuper
  void onDisable() {
    _setState(.bound);
  }

  /// Called when the host suspends the USB bus.
  ///
  /// The device should reduce power consumption.
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
  ///
  /// Default implementation handles standard requests:
  /// - GET_STATUS on interface/endpoints
  /// - CLEAR_FEATURE(ENDPOINT_HALT)
  /// - SET_FEATURE(ENDPOINT_HALT)
  ///
  /// Override to handle class-specific or vendor requests.
  /// Call super.onSetup() to fall back to default handling.
  @mustCallSuper
  void onSetup(int requestType, int request, int value, int index, int length) {
    if (debug) {
      log(
        'Setup Request: '
        'bmRequestType=${requestType.toHex()}, '
        'bRequest=${request.toHex()}, '
        'wValue=${value.toHex()}, '
        'wIndex=${index.toHex()}, '
        'wLength=${length.toHex()}',
      );
    }

    final type = USBRequestType.fromByte(requestType);
    final recipient = USBRecipient.fromByte(requestType);
    final direction = USBDirection.fromByte(requestType);

    if (type != USBRequestType.standard) {
      log('Non-standard request, halting');
      return _ep0.halt();
    }

    final usbRequest = USBRequest.fromValue(request);

    // GET_STATUS
    if (usbRequest == USBRequest.getStatus && direction.isIn && length == 2) {
      if (value != 0) {
        return _ep0.halt();
      }

      var status = 0;
      switch (recipient) {
        case USBRecipient.interface:
          if (index != 0) {
            return _ep0.halt();
          }
          status = 0;

        case USBRecipient.endpoint:
          // Use endpoint address map instead of array index
          final endpoint = _endpointByAddress[index];
          if (endpoint == null) {
            return _ep0.halt();
          }
          status = endpoint.isHalted ? 1 : 0;

        default:
          return _ep0.halt();
      }

      final bytes = ByteData(2)..setUint16(0, status, Endian.little);
      // IN transfer: write data, kernel handles status phase
      return _ep0.write(bytes.buffer.asUint8List());
    }

    // CLEAR_FEATURE / SET_FEATURE
    final isSet = usbRequest == USBRequest.setFeature;
    final isClear = usbRequest == USBRequest.clearFeature;
    if ((isSet || isClear) && direction.isOut && length == 0) {
      final enable = isSet;

      if (recipient == USBRecipient.endpoint &&
          value == USBFeature.endpointHalt.value) {
        // Use endpoint address map
        final endpoint = _endpointByAddress[index];
        if (endpoint == null) {
          return _ep0.halt();
        }

        if (enable) {
          endpoint.halt();
        } else {
          endpoint.clearHalt();
        }
        // OUT transfer with no data: send ACK
        _ep0.read(0);
        return;
      }
    }

    log('Unhandled: type=${requestType.toHex()} req=${request.toHex()}');
    return _ep0.halt();
  }
}
