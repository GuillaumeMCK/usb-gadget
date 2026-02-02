import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '/src/logger/logger.dart';
import '/src/platform/platform.dart';
import '/usb_gadget.dart';

/// Base class for FunctionFs endpoint file descriptors.
///
/// Manages the lifecycle (open, close, halt) for USB endpoints
/// exposed via the Linux FunctionFs interface.
abstract class EndpointFile {
  /// Creates an endpoint file manager for [path].
  EndpointFile(this.path) {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'Path cannot be empty');
    }
  }

  /// The path to the endpoint file (e.g., '/dev/usb-ffs/ep1').
  final String path;

  /// The underlying file descriptor.
  int? _fd;

  /// Whether this endpoint is currently open.
  bool get isOpen => _fd != null;

  /// Opens the endpoint file with appropriate flags.
  ///
  /// Sets the internal file descriptor upon success.
  /// Throws [OSError] if the underlying C `open` call fails.
  /// Throws [StateError] if already open.
  Future<void> open();

  /// Closes the underlying file descriptor.
  ///
  /// Clears the internal file descriptor after closing.
  /// Safe to call multiple times (idempotent).
  Future<void> close();

  /// Whether the endpoint is currently halted (STALL state).
  ///
  /// Note: Most endpoints cannot read their halt state, so this
  /// returns false by default. Override if halt state tracking is needed.
  bool get isHalted => false;

  /// Clears the halt (STALL) condition on the endpoint.
  ///
  /// Throws [OSError] if the operation fails.
  /// Throws [StateError] if endpoint is not open.
  void clearHalt();

  /// Halts (STALLs) the endpoint.
  ///
  /// The implementation differs based on endpoint type.
  /// Throws [StateError] if endpoint is not open.
  void halt();

  /// The file descriptor for this endpoint.
  ///
  /// Returns `null` if the file is not currently open.
  int? get fd => _fd;
}

/// Manages the USB control endpoint (EP0) for FunctionFs.
///
/// EP0 is special:
/// - Handles control transfers and setup requests
/// - Can have multiple stream listeners (broadcast)
/// - Manages FunctionFs mounting/unmounting
/// - Provides blocking read/write for descriptor setup
/// - Provides event stream for asynchronous operation
///
/// ## Thread Safety
/// This class is NOT thread-safe. All operations should be performed
/// from the same isolate. Stream operations are safe for multiple listeners.
class EndpointControlFile extends EndpointFile with USBGadgetLogger {
  EndpointControlFile(
    super.path, {
    required String mountPoint,
    required String mountSource,
    FunctionFsMountConfig? mountConfig,
  }) : _mount = FunctionFsMount(
         mountPoint: mountPoint,
         mountSource: mountSource,
         ep0Path: path,
         config: mountConfig,
       );

  /// Mount manager for the FunctionFs filesystem.
  final FunctionFsMount _mount;

  /// Stream controller for event broadcasting.
  StreamController<FunctionFsEvent>? _streamController;

  /// Timer for polling EP0 events.
  Timer? _pollingTimer;

  /// Whether event reading is active.
  bool _eventReadingActive = false;

  /// Whether the mount point exists and appears to be mounted.
  bool get isMounted => _mount.isMounted;

  /// Mount point for FunctionFs filesystem.
  String get mountPoint => _mount.mountPoint;

  /// Mount configuration.
  FunctionFsMountConfig get mountConfig => _mount.config;

  @override
  Future<void> open() async {
    if (_fd != null) {
      throw StateError('Endpoint is already open');
    }

    await _mount.ensureMounted();

    try {
      _fd = Unistd.open(path, const [OpenFlag.rdWr, OpenFlag.nonBlock]);
    } on OSError catch (e) {
      _mount.cleanupIfNeeded();
      throw StateError(
        'Failed to open EP0 at $path: ${e.message} (errno: ${e.errorCode})',
      );
    }
  }

  @override
  Future<void> close() async {
    final fd = _fd;
    if (fd == null) return;

    // Stop event reading
    _eventReadingActive = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;

    // Close stream controller
    await _streamController?.close();
    _streamController = null;

    // Close file descriptor
    try {
      Unistd.close(fd);
    } on OSError catch (e) {
      log?.error('Failed to close EP0 file descriptor: ${e.message}');
    } finally {
      _fd = null;
    }

    // Cleanup mount if configured
    _mount.cleanupIfNeeded();
  }

  @override
  void clearHalt() {
    // EP0 doesn't support halt/clear operations
  }

  @override
  void halt() {
    if (_fd == null) {
      throw StateError('Cannot halt: Endpoint is not open');
    }
    try {
      // Reading 0 bytes on EP0 sends STALL to host
      Unistd.read(_fd!, 0);
    } on OSError catch (e) {
      // Handle common errors gracefully
      if (e.errorCode == Errno.epipe) {
        log?.warn('Cannot halt: Broken pipe (host disconnected)');
      } else if (e.errorCode == Errno.eshutdown) {
        log?.warn('Cannot halt: Endpoint is shut down');
      } else if (e.errorCode == Errno.enotconn) {
        log?.warn('Cannot halt: Not connected');
      } else {
        log?.error('Failed to halt EP0: ${e.message}');
        rethrow;
      }
    }
  }

  /// Writes data to EP0 (blocking, retries on EAGAIN).
  ///
  /// Used for:
  /// - Writing descriptors during setup
  /// - Sending responses to GET_DESCRIPTOR requests
  /// - Returning data for IN control transfers
  ///
  /// This method will block until all data is written or an error occurs.
  /// EAGAIN errors are retried automatically.
  ///
  /// Throws [StateError] if endpoint is not open.
  /// Throws [OSError] on unrecoverable write errors.
  void write(Uint8List data) {
    assert(_fd != null, 'write: Endpoint is not open');

    if (data.isEmpty) {
      return log?.warn('Attempting to write empty data to EP0');
    }

    var offset = 0;
    while (offset < data.length) {
      try {
        offset += Unistd.write(_fd!, data.sublist(offset));
      } on OSError catch (e) {
        if (e.errorCode == Errno.eagain) {
          // Retry on EAGAIN (would block)
          continue;
        }
        log?.error('Failed to write to EP0: ${e.message}');
        rethrow;
      }
    }
  }

  /// Reads up to [length] bytes from EP0 (non-blocking).
  ///
  /// Used for:
  /// - Reading 0 bytes to ACK OUT control transfers
  /// - Reading data from SET_REPORT or other OUT transfers
  ///
  /// Returns empty list if no data available (EAGAIN).
  /// Does NOT block waiting for data.
  ///
  /// Throws [StateError] if endpoint is not open.
  /// Throws [OSError] on unrecoverable read errors.
  /// Throws [ArgumentError] if length is negative.
  Uint8List read(int length) {
    assert(_fd != null, 'read: Endpoint is not open');
    try {
      return Unistd.read(_fd!, length);
    } on OSError catch (e) {
      log?.error('Failed to read from EP0: ${e.message}');
      rethrow;
    }
  }

  /// Event buffer size (48 bytes = 4 events of 12 bytes each).
  ///
  /// Reading multiple events at once reduces overhead.
  static const int eventBufferSize = 4 * FunctionFsEvent.size;

  /// Creates a broadcast stream of FunctionFs events.
  ///
  /// EP0 supports multiple stream listeners (broadcast semantics).
  /// The stream is cached and reused for all listeners.
  ///
  /// Events include:
  /// - BIND: Function bound to UDC
  /// - UNBIND: Function unbound from UDC
  /// - ENABLE: Host configured device
  /// - DISABLE: Host de-configured device
  /// - SETUP: Control transfer request from host
  /// - SUSPEND: Bus suspended
  /// - RESUME: Bus resumed
  ///
  /// The stream uses AIO for event-driven I/O with minimal latency.
  /// Errors are reported through the stream's error channel.
  ///
  /// The stream automatically closes when:
  /// - The endpoint is closed via close()
  /// - All listeners have canceled their subscriptions
  /// - An unrecoverable error occurs
  ///
  /// Throws [StateError] if endpoint is not open.
  Stream<FunctionFsEvent> stream() {
    if (_fd == null) {
      throw StateError('Cannot create stream: Endpoint is not open');
    }

    // Return existing stream if already created
    final controller = _streamController;
    if (controller != null && !controller.isClosed) {
      return controller.stream;
    }

    // Create new broadcast controller
    final newController = StreamController<FunctionFsEvent>.broadcast(
      onListen: _startEventReading,
      onCancel: _stopEventReading,
    );

    _streamController = newController;
    return newController.stream;
  }

  /// Starts event reading from EP0 using synchronous polling with a Timer.
  ///
  /// EP0 does NOT support Linux AIO, so we use synchronous reads
  /// with a polling timer. The file descriptor is opened with O_NONBLOCK
  /// to prevent blocking on reads when no events are available.
  void _startEventReading() {
    if (_eventReadingActive || _fd == null) return;
    _eventReadingActive = true;

    // Use a timer to poll for events (10ms interval for low latency)
    _pollingTimer = Timer.periodic(const .new(milliseconds: 10), (_) {
      if (!_eventReadingActive || _fd == null) {
        return _pollingTimer?.cancel();
      }

      try {
        // Try to read events (non-blocking)
        final bytesRead = Unistd.read(_fd!, eventBufferSize);

        if (bytesRead.isNotEmpty) {
          // Parse and emit events
          try {
            final events = FunctionFsEvent.fromBytesMultiple(bytesRead);
            final controller = _streamController;
            if (controller != null && !controller.isClosed) {
              events.forEach(controller.add);
            }
          } catch (e, st) {
            log?.error('Failed to parse FunctionFs event', e, st);
            _streamController?.addError(e, st);
          }
        }
      } on OSError catch (e) {
        if (e.errorCode == Errno.eagain || e.errorCode == Errno.ewouldblock) {
          // No data available, this is normal for non-blocking I/O
          return;
        } else if (e.errorCode == Errno.ebadf || e.errorCode == Errno.einval) {
          // File descriptor closed or invalid, stop polling
          log?.warn('EP0 file descriptor invalid, stopping event reading');
          _eventReadingActive = false;
          _pollingTimer?.cancel();
          return;
        } else {
          log?.error(
            'Error reading EP0 events: ${e.message} (errno: ${e.errorCode})',
          );
          if (_streamController != null && !_streamController!.isClosed) {
            _streamController!.addError(e);
          }
        }
      }
    });
  }

  /// Stops event reading.
  Future<void> _stopEventReading() async {
    _eventReadingActive = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Flushes the FIFO buffer.
  ///
  /// Discards any pending data in the endpoint's FIFO.
  ///
  /// **When to use:**
  /// - After protocol errors or STALL conditions
  /// - When recovering from host-side errors
  /// - Before re-enabling after disable event
  /// - When resetting endpoint state
  ///
  /// Throws [StateError] if endpoint is not open.
  /// Throws [OSError] if ioctl fails.
  void flushFIFO() {
    if (_fd == null) {
      throw StateError('Cannot flush FIFO: Endpoint is not open');
    }

    try {
      Ioctl.call(_fd!, .fifoFlush);
      log?.debug('FIFO flushed successfully');
    } on OSError catch (e) {
      log?.error('Failed to flush FIFO: ${e.message}');
      rethrow;
    }
  }

  /// Gets the FIFO status (number of bytes in buffer).
  ///
  /// Returns the number of bytes currently in the endpoint's FIFO.
  ///
  /// Throws [StateError] if endpoint is not open.
  /// Throws [OSError] if ioctl fails.
  int getFIFOStatus() {
    assert(_fd != null, 'getFIFOStatus: Endpoint is not open');

    final result = Ioctl.call(_fd!, .fifoStatus);
    if (result < 0) {
      final error = Errno.toOSError(result);
      log?.error('Failed to get FIFO status: ${error.message}');
      throw error;
    }
    return result;
  }
}

/// Manages a USB IN endpoint (device-to-host).
///
/// IN endpoints send data from the device to the host.
/// Common uses:
/// - HID input reports (keyboard, mouse, gamepad)
/// - Bulk data transfers (file uploads)
/// - Interrupt notifications
class EndpointInFile extends EndpointFile {
  EndpointInFile(super.path);

  /// AIO writer for high-throughput async writes.
  AioWriter? _writer;

  @override
  Future<void> open() async {
    if (_fd != null) {
      throw StateError('Endpoint is already open');
    }

    try {
      _fd = Unistd.open(path, const [OpenFlag.wrOnly]);
    } on OSError catch (e) {
      throw StateError(
        'Failed to open IN endpoint at $path: ${e.message} (errno: ${e.errorCode})',
      );
    }
  }

  @override
  Future<void> close() async {
    if (_fd == null) return;

    // Flush any pending writes before releasing
    await _writer?.flush();
    _writer?.release();
    _writer = null;

    // Close file descriptor
    try {
      Unistd.close(_fd!);
    } on OSError {
      // Silently ignore errors during cleanup
    } finally {
      _fd = null;
    }
  }

  @override
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

  @override
  void halt() {
    if (_fd == null) {
      throw StateError('Cannot halt: Endpoint is not open');
    }
    try {
      // Writing 0 bytes to IN endpoint sends STALL to host
      Unistd.write(_fd!, Uint8List(0));
    } on OSError catch (e) {
      if (e.errorCode == Errno.epipe) {
        throw StateError('Cannot halt IN endpoint: Host disconnected (EPIPE)');
      } else if (e.errorCode == Errno.eshutdown) {
        throw StateError(
          'Cannot halt IN endpoint: Endpoint is shut down (ESHUTDOWN)',
        );
      } else if (e.errorCode == Errno.enotconn) {
        throw StateError('Cannot halt IN endpoint: Not connected (ENOTCONN)');
      }
      // Provide meaningful error message for other errors
      throw StateError(
        'Failed to halt IN endpoint: ${e.message} (errno: ${e.errorCode})',
      );
    }
  }

  /// Synchronous write (blocking).
  ///
  /// Writes data to the endpoint. Blocks until all data is written or an
  /// error occurs. For high-throughput scenarios, use [writeAsync] instead.
  ///
  /// Throws [StateError] if endpoint is not open.
  /// Throws [OSError] on write failure.
  void write(Uint8List data) {
    assert(_fd != null, 'write: Endpoint is not open');
    Unistd.write(_fd!, data);
  }

  /// Asynchronous write using Linux AIO for high throughput.
  ///
  /// Automatically creates and manages an internal [AioWriter] instance.
  /// Much more efficient than [write] for large data transfers or
  /// high-frequency updates.
  ///
  /// Parameters:
  /// - [data]: Data to write
  /// - [bufferSize]: Size of each AIO buffer (default: 16KB)
  /// - [concurrency]: Number of concurrent operations (default: 4)
  ///
  /// Note: [bufferSize] and [concurrency] are locked after the first call.
  /// Subsequent calls with different values will use the original configuration.
  ///
  /// Returns a Future that completes with the number of bytes written.
  ///
  /// Throws [StateError] if endpoint is not open.
  /// Throws [ArgumentError] if buffer parameters are invalid.
  Future<int> writeAsync(
    Uint8List data, {
    int bufferSize = 16384,
    int concurrency = 4,
    Duration? interval,
  }) {
    assert(_fd != null, 'writeAsync: Endpoint is not open');
    assert(bufferSize > 0, 'Buffer size must be positive');
    assert(concurrency > 0, 'Concurrency must be positive');

    _writer ??= AioWriter(
      _fd!,
      AioConfig(
        bufferSize: bufferSize,
        maxConcurrent: concurrency,
        interval: interval ?? const .new(milliseconds: 1),
      ),
    );

    return _writer!.write(data);
  }

  /// Flushes all pending asynchronous writes.
  ///
  /// Waits for all queued AIO operations to complete.
  /// Safe to call even if no async writes are pending.
  Future<void> flush() => _writer?.flush() ?? Future.value();
}

/// Manages a USB OUT endpoint (host-to-device).
///
/// OUT endpoints receive data from the host.
/// Common uses:
/// - HID output reports (keyboard LEDs)
/// - Bulk data transfers (file downloads)
/// - Control/command channels
class EndpointOutFile extends EndpointFile {
  EndpointOutFile(super.path, {required this.config});

  /// Endpoint configuration (transfer type, packet size, etc.)
  final EndpointConfig config;

  /// Transfer type for this endpoint.
  TransferType get transferType => config.transferType;

  /// AIO reader for high-throughput async reads.
  AioReader? _reader;

  /// Cached broadcast stream.
  StreamController<Uint8List>? _streamController;

  @override
  Future<void> open() async {
    if (_fd != null) {
      throw StateError('Endpoint is already open');
    }

    try {
      _fd = Unistd.open(path, const [OpenFlag.rdOnly]);
    } on OSError catch (e) {
      throw StateError(
        'Failed to open OUT endpoint at $path: ${e.message} (errno: ${e.errorCode})',
      );
    }
  }

  @override
  Future<void> close() async {
    if (_fd == null) return;

    await _streamController?.close();
    _streamController = null;

    _reader?.release();
    _reader = null;

    try {
      Unistd.close(_fd!);
    } on OSError {
      // Silently ignore errors during cleanup
    } finally {
      _fd = null;
    }
  }

  @override
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
      // Provide meaningful error message
      throw StateError(
        'Failed to clear halt on OUT endpoint: ${e.message} (errno: ${e.errorCode})',
      );
    }
  }

  @override
  void halt() {
    // Cannot halt OUT endpoints in FunctionFs.
    // The host controls data flow on OUT endpoints.
    throw UnsupportedError(
      'Cannot halt OUT endpoints in FunctionFs. '
      'The host controls data flow on OUT endpoints.',
    );
  }

  /// Synchronous read (non-blocking).
  ///
  /// Attempts to read up to [length] bytes. Returns immediately with
  /// available data or empty list if no data available (EAGAIN).
  ///
  /// For continuous reading, use [stream] instead which is much more
  /// efficient and handles backpressure automatically.
  ///
  /// Throws [StateError] if endpoint is not open.
  /// Throws [ArgumentError] if length is negative.
  Uint8List read(int length) {
    assert(_fd != null, 'read: Endpoint is not open');
    try {
      return Unistd.read(_fd!, length);
    } on OSError {
      rethrow;
    }
  }

  /// Creates a broadcast stream using Linux AIO for high throughput.
  ///
  /// **IMPORTANT**: The stream can have multiple listeners (broadcast semantics),
  /// but the underlying AIO reader is created once and shared. The buffer
  /// configuration is locked after the first call to this method.
  ///
  /// The stream automatically handles:
  /// - Transfer-type-specific error conditions
  /// - Backpressure management
  /// - Buffer allocation and reuse
  /// - Isochronous timing errors (stops reading)
  /// - Aborted bulk/interrupt transfers (ignores)
  ///
  /// Parameters:
  /// - [concurrency]: Number of concurrent AIO operations (default: 4)
  ///   More concurrency = better throughput but more memory
  ///
  /// Buffer size is determined automatically based on transfer type:
  /// - Bulk: 16KB
  /// - Interrupt: 64 bytes
  /// - Isochronous: 1KB
  /// - Control: 64 bytes
  /// - Or uses maxPacketSize from config if specified
  ///
  /// Throws [StateError] if endpoint is not open.
  /// Throws [ArgumentError] if concurrency is invalid.
  Stream<Uint8List> stream({int concurrency = 4, Duration? interval}) {
    assert(_fd != null, 'stream: Endpoint is not open');
    assert(concurrency > 0, 'Concurrency must be positive');

    // Return cached stream if already created
    if (_streamController?.isClosed == false) {
      return _streamController!.stream;
    }

    final bufferSize = switch (transferType) {
      _ when config.maxPacketSize != null => config.maxPacketSize!,
      .bulk => 16384,
      .interrupt => 64,
      .isochronous => 1024,
      .control => 64,
    };

    _reader ??= AioReader(
      _fd!,
      AioConfig(
        bufferSize: bufferSize,
        maxConcurrent: concurrency,
        interval: interval ?? const .new(milliseconds: 1),
      ),
    );

    _streamController = StreamController<Uint8List>.broadcast();

    // Store subscription so we can cancel it later if needed
    _reader?.stream.listen(
      (data) {
        if (_streamController != null && !_streamController!.isClosed) {
          _streamController!.add(data);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_streamController != null && !_streamController!.isClosed) {
          _streamController!.addError(error, stackTrace);
        }
      },
      onDone: () {
        _streamController?.close();
      },
      cancelOnError: false,
    );

    return _streamController!.stream;
  }
}
