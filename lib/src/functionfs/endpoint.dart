import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:using/using.dart';

import '/src/platform/platform.dart';
import '/usb_gadget.dart';

/// Base class for FunctionFs endpoint file descriptors.
///
/// Manages the low-level lifecycle (open, close, halt) for USB endpoints
/// exposed via the Linux FunctionFs (FFS) interface.
abstract class EndpointFile with USBGadgetLogger {
  /// Creates an endpoint file manager for the specified [path].
  EndpointFile(this.path) {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'Path cannot be empty');
    }
  }

  /// The absolute path to the endpoint file (e.g., `/dev/ffs/<name>/ep1`).
  final String path;

  /// The raw Linux file descriptor assigned to this endpoint.
  ///
  /// This is `null` until the endpoint is successfully opened.
  int? _fd;

  /// Returns the current file descriptor or `null` if the endpoint is closed.
  int? get fd => _fd;

  /// Opens the endpoint file with appropriate system flags.
  ///
  /// Implementation varies by endpoint type (Read, Write, or RDWR).
  /// Throws [OSError] if the system `open` call fails.
  /// Throws [StateError] if already open.
  Future<void> open();

  /// Closes the underlying file descriptor and releases kernel resources.
  ///
  /// Clears the internal file descriptor after closing. This is idempotent.
  Future<void> close();

  /// Signals a protocol STALL (Halt) to the USB host.
  ///
  /// Throws [StateError] if the endpoint is not open.
  /// Note: [EndpointOutFile] overrides this to throw [UnsupportedError]
  /// unconditionally, as manual STALL is not supported for OUT endpoints.
  void halt();

  /// Discards any pending data currently residing in the endpoint's FIFO buffer.
  ///
  /// Throws [StateError] if the endpoint is not open.
  /// Throws [OSError] if the `ioctl` call fails.
  void flushFIFO() {
    if (fd == null) {
      throw StateError('Cannot flush FIFO: Endpoint is not open');
    }
    Ioctl.call(fd!, .fifoFlush);
  }

  /// Queries the kernel for the number of bytes currently in the endpoint's FIFO.
  ///
  /// Returns the byte count or throws [OSError] if the `ioctl` fails.
  int getFIFOStatus() {
    if (fd == null) {
      throw StateError('Cannot get FIFO status: Endpoint is not open');
    }
    // Ioctl.call() already throws OSError on any negative return value.
    return Ioctl.call(fd!, .fifoStatus);
  }

  @override
  String toString() => 'EndpointFile(path: $path, open: ${_fd != null})';
}

/// Manages the USB control endpoint (EP0) for FunctionFs.
///
/// Handles the FunctionFs mount lifecycle and provides a broadcast stream
/// for USB setup events (BIND, ENABLE, SETUP, etc.).
final class EndpointControlFile extends EndpointFile with Releasable {
  /// Creates a control endpoint manager with mounting capabilities.
  EndpointControlFile(
    super.path, {
    required String mountPoint,
    required String mountSource,
  }) : _mount = FunctionFsMount(
         mountPoint: mountPoint,
         mountSource: mountSource,
         ep0Path: path,
       );

  /// Event buffer size for polling (48 bytes = 4 events of 12 bytes each).
  ///
  /// Reading multiple events at once reduces syscall overhead during enumeration.
  static const int eventBufferSize = 4 * FunctionFsEvent.size;

  /// The mount manager responsible for the `functionfs` filesystem.
  final FunctionFsMount _mount;

  /// Broadcast controller for emitting [FunctionFsEvent] objects.
  StreamController<FunctionFsEvent>? _streamController;

  /// Periodic timer that reads from the non-blocking EP0 file descriptor
  /// at a fixed interval to deliver kernel USB events to the stream.
  Timer? _pollingTimer;

  /// Internal flag to track if the polling loop is active.
  bool _eventReadingActive = false;

  /// Indicates if the FunctionFs backing store is currently mounted.
  bool get isMounted => _mount.isMounted;

  /// The directory where FunctionFs is mounted.
  String get mountPoint => _mount.mountPoint;

  @override
  Future<void> open() async {
    if (_fd != null) throw StateError('Endpoint is already open');

    _mount.ensure();
    try {
      _fd = Unistd.open(path, const [.rdWr, .nonBlock]);
    } on OSError catch (e) {
      _mount.unmount();
      throw StateError(
        'Failed to open EP0 at $path: ${e.message} (errno: ${e.errorCode})',
      );
    }
  }

  @override
  Future<void> close() async {
    if (_fd == null) return;
    super.release();

    _eventReadingActive = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;

    await _streamController?.close();
    _streamController = null;

    try {
      Unistd.close(_fd!);
    } on OSError catch (e) {
      log?.error('Failed to close EP0 file descriptor: ${e.message}');
    } finally {
      _fd = null;
    }

    _mount.unmount();
  }

  /// Sends a STALL response to the host via a 0-length read.
  @override
  void halt() {
    if (fd == null) throw StateError('Cannot halt: Endpoint is not open');

    try {
      Unistd.read(fd!, 0);
    } on OSError catch (e) {
      final code = e.errorCode;
      if (const [Errno.epipe, Errno.eshutdown, Errno.enotconn].contains(code)) {
        log?.warn('Halt ignored: Host disconnected (${e.errorCode})');
      } else {
        rethrow;
      }
    }
  }

  /// Performs a synchronous write to EP0, retrying on `EAGAIN`.
  void write(Uint8List data) {
    final currentFd = _fd;
    if (currentFd == null) throw StateError('write: Endpoint is not open');

    var offset = 0;
    while (offset < data.length) {
      try {
        offset += Unistd.write(currentFd, data.sublist(offset));
      } on OSError catch (e) {
        if (e.errorCode == Errno.eagain) continue;
        rethrow;
      }
    }
  }

  /// Reads up to [length] bytes from EP0 in non-blocking mode.
  Uint8List read(int length) {
    if (_fd == null) throw StateError('read: Endpoint is not open');
    return Unistd.read(_fd!, length);
  }

  /// Acknowledges a host request with a Zero-Length Packet (ZLP).
  void ack() {
    if (fd == null) throw StateError('Cannot ACK: Endpoint is not open');
    Unistd.write(fd!, Uint8List(0));
  }

  /// A broadcast stream emitting control events from the kernel.
  Stream<FunctionFsEvent> get stream {
    if (_fd == null) throw StateError('Cannot create stream: EP0 not open');

    final controller = _streamController;
    if (controller != null && !controller.isClosed) {
      return controller.stream;
    }

    _streamController ??= StreamController.broadcast(
      onListen: _startReading,
      onCancel: _stopReading,
    );
    return _streamController!.stream;
  }

  void _startReading() {
    if (_eventReadingActive) return;
    _eventReadingActive = true;

    _pollingTimer ??= .periodic(const .new(milliseconds: 1), (_) {
      try {
        final data = Unistd.read(_fd!, eventBufferSize);
        const offset = FunctionFsEvent.size;
        for (var i = 0; i + offset <= data.length; i += offset) {
          _streamController?.add(.fromBytes(data.sublist(i, i + offset)));
        }
      } on OSError catch (err) {
        if (err.errorCode != Errno.eagain) {
          _streamController?.addError(err);
        }
      }
    });
  }

  void _stopReading() {
    _eventReadingActive = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }
}

/// Manages a USB IN endpoint (device-to-host) using Linux AIO.
///
/// Provides high-performance asynchronous writes with automatic buffer
/// management and backpressure handling.
final class EndpointInFile extends EndpointFile with Releasable {
  /// Creates an IN endpoint with optional custom AIO instance.
  EndpointInFile(super.path, {required this.config})
    : _aio = .fromEndpointConfig(config);

  /// Endpoint configuration defining transfer characteristics.
  final EndpointConfig config;

  /// AIO context for asynchronous operations.
  Aio? _aio;

  /// Writer sink for asynchronous writes.
  AioSink? _sink;

  @override
  Future<void> open() async {
    if (_fd != null) return;

    _fd = Unistd.open(path, const [.wrOnly]);

    // Create AIO context if not provided
    _aio ??= Aio.fromEndpointConfig(config);

    // Create writer sink for this endpoint
    _sink ??= _aio!.createWriter(
      _fd!,
      config: switch (config) {
        BulkEndpointConfig() => const .new(
          maxQueueSize: 64,
          backpressure: .block,
        ),
        ControlEndpointConfig() => const .new(
          maxQueueSize: 16,
          backpressure: .block,
        ),
        IsochronousEndpointConfig() => const .new(
          maxQueueSize: 32,
          backpressure: .dropOldest,
        ),
        InterruptEndpointConfig() => const .new(
          maxQueueSize: 16,
          backpressure: .dropOldest,
        ),
      },
    );
  }

  @override
  Future<void> close() async {
    if (_fd == null) return;
    super.release();

    // Close and wait for pending writes
    await _sink?.close();
    _sink = null;

    // Release AIO
    _aio?.release();
    _aio = null;

    Unistd.close(_fd!);
    _fd = null;
  }

  @override
  void halt() {
    if (_fd != null) Unistd.write(_fd!, Uint8List(0));
  }

  /// Enqueues [data] for asynchronous transmission to the host.
  ///
  /// The data is handed off to the [AioSink] and transmitted via Linux AIO.
  /// Backpressure behaviour is determined by the AIO configuration.
  ///
  /// Throws [StateError] if endpoint is not open.
  void write(Uint8List data) {
    if (_sink == null) throw StateError('Endpoint not open');
    _sink!.add(data);
  }

  /// Flushes all pending writes and waits for completion.
  ///
  /// Closes the current [AioSink] (draining all queued operations) and then
  /// reopens a fresh sink so the endpoint can continue to be used.
  /// Returns a future that completes when all queued data has been
  /// transmitted to the host.
  Future<void> flush() async {
    if (_sink == null) return;
    final config = _sink!.config;
    await _sink!.close();
    _sink = null;
    // Reopen sink for continued use
    _sink ??= _aio!.createWriter(_fd!, config: config);
  }

  /// Clears the halt (STALL) condition on the endpoint.
  ///
  /// Sends the CLEAR_HALT ioctl to the endpoint to clear a previously
  /// set halt condition. Used to recover from error conditions after
  /// the host has acknowledged the STALL.
  ///
  /// Throws [StateError] if endpoint is not open.
  /// Throws [OSError] if the operation fails.
  void clearHalt() {
    if (_fd == null) {
      throw StateError('Cannot clear halt: Endpoint is not open');
    }

    try {
      Ioctl.call(_fd!, .clearHalt);
    } on OSError catch (e) {
      if (e.errorCode == Errno.einval) {
        // Endpoint not halted, this is not an error
        return;
      }

      throw StateError(
        'Failed to clear halt on IN endpoint: ${e.message} (errno: ${e.errorCode})',
      );
    }
  }
}

/// Manages a USB OUT endpoint (host-to-device) using Linux AIO.
///
/// Provides high-performance asynchronous reads with automatic buffer
/// management and demand-driven backpressure.
final class EndpointOutFile extends EndpointFile with Releasable {
  /// Creates an OUT endpoint with optional custom AIO instance.
  EndpointOutFile(super.path, {required this.config})
    : _aio = .fromEndpointConfig(config);

  /// Endpoint configuration defining transfer characteristics.
  final EndpointConfig config;

  /// AIO context for asynchronous operations.
  Aio? _aio;

  /// Reader stream for asynchronous reads.
  AioStream? _reader;

  @override
  Future<void> open() async {
    if (_fd != null) return;

    _fd = Unistd.open(path, const [.rdOnly]);

    // Create AIO context if not provided
    _aio ??= Aio.fromEndpointConfig(config);

    // Create reader stream for this endpoint
    _reader ??= _aio!.createReader(
      _fd!,
      maxInflight: switch (config) {
        BulkEndpointConfig() => 16,
        IsochronousEndpointConfig() => 8,
        InterruptEndpointConfig() => 4,
        ControlEndpointConfig() => 2,
      },
    );
  }

  @override
  Future<void> close() async {
    if (_fd == null) return;
    super.release();

    // Release reader stream
    _reader?.release();
    _reader = null;

    // Release AIO
    _aio?.release();
    _aio = null;

    Unistd.close(_fd!);
    _fd = null;
  }

  @override
  void halt() => throw UnsupportedError('Manual STALL not supported for OUT');

  /// Stream of data from the host.
  ///
  /// The stream automatically manages backpressure - pausing the stream
  /// will stop submitting new read operations to the kernel, and resuming
  /// will restart them. This provides natural flow control.
  ///
  /// Example:
  /// ```dart
  /// await for (final data in endpoint.stream) {
  ///   // Process data...
  ///   // Stream pauses automatically if processing is slow
  /// }
  /// ```
  Stream<Uint8List> get stream {
    if (_reader == null) throw StateError('Endpoint not open');
    return _reader!.stream;
  }
}
