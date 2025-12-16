import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

  /// Polling task cancellation.
  bool _pollingActive = false;

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

    // Ensure FunctionFs is mounted
    await _mount.ensureMounted();

    // Open the EP0 file
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

    // Stop polling
    _pollingActive = false;

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
    log?.debug('clearHalt() called on EP0 (no-op)');
  }

  @override
  void halt() {
    assert(_fd != null, 'halt: Endpoint is not open');
    // Reading 0 bytes on EP0 sends STALL to host
    Unistd.read(_fd!, 0);
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
        final written = Unistd.write(_fd!, data.sublist(offset));
        offset += written;
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
  List<int> read(int length) {
    assert(_fd != null, 'read: Endpoint is not open');

    if (length < 0) {
      throw ArgumentError.value(length, 'length', 'Length cannot be negative');
    }

    if (length == 0) {
      // Reading 0 bytes is used for ACK
      try {
        Unistd.read(_fd!, 0);
        return const [];
      } on OSError catch (e) {
        if (e.errorCode != Errno.eagain) {
          log?.error('Failed to ACK on EP0: ${e.message}');
        }
        rethrow;
      }
    }

    try {
      return Unistd.read(_fd!, length);
    } on OSError catch (e) {
      if (e.errorCode == Errno.eagain) {
        return const [];
      }
      log?.error('Failed to read from EP0: ${e.message}');
      rethrow;
    }
  }

  /// Event buffer size (48 bytes = 4 events of 12 bytes each).
  ///
  /// Reading multiple events at once reduces syscall overhead.
  static const int eventBufferSize = 4 * FunctionFsEvent.size;

  /// Polling interval in milliseconds.
  ///
  /// Default is 100ms which provides good balance between responsiveness
  /// and CPU usage. Can be adjusted based on requirements:
  /// - Lower (e.g., 10ms) for latency-sensitive applications
  /// - Higher (e.g., 250ms) for power-sensitive applications
  ///
  /// For production, consider using epoll or select for event-driven I/O
  /// instead of polling.
  static const Duration pollingInterval = Duration(milliseconds: 100);

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
  /// The stream uses async polling with a default interval of 100ms.
  /// Errors are reported through the stream's error channel.
  ///
  /// The stream automatically closes when:
  /// - The endpoint is closed via close()
  /// - All listeners have canceled their subscriptions
  /// - An unrecoverable error occurs
  ///
  /// Throws [StateError] if endpoint is not open.
  Stream<FunctionFsEvent> stream() {
    assert(_fd != null, 'stream: Endpoint is not open');

    // Return existing stream if already created
    final controller = _streamController;
    if (controller != null && !controller.isClosed) {
      return controller.stream;
    }

    // Create new broadcast controller
    final newController = StreamController<FunctionFsEvent>.broadcast(
      onListen: _startPolling,
      onCancel: _stopPolling,
    );

    _streamController = newController;
    return newController.stream;
  }

  /// Starts polling EP0 for events.
  void _startPolling() {
    if (_pollingActive) return;
    _pollingActive = true;
    _pollLoop();
  }

  /// Stops polling EP0 for events.
  void _stopPolling() {
    _pollingActive = false;
  }

  /// Polling loop that reads events and adds them to the stream.
  Future<void> _pollLoop() async {
    final controller = _streamController;
    if (controller == null) return;

    while (_pollingActive && _fd != null && !controller.isClosed) {
      try {
        final bytes = read(eventBufferSize);
        if (bytes.isNotEmpty) {
          final events = FunctionFsEvent.fromBytesMultiple(bytes);
          for (final event in events) {
            if (!controller.isClosed) {
              controller.add(event);
            }
          }
        }
      } on OSError catch (e, st) {
        if (e.errorCode == Errno.eagain) {
          // No data available, continue polling
        } else if (e.errorCode == Errno.ebadf) {
          // File descriptor closed, stop polling
          _pollingActive = false;
          break;
        } else {
          // Other errors propagate to stream
          if (!controller.isClosed) {
            controller.addError(e, st);
          }
          // Continue polling after error
        }
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }

      await Future<void>.delayed(pollingInterval);
    }
  }

  /// Flushes the FIFO buffer.
  ///
  /// Discards any pending data in the endpoint's FIFO.
  /// Useful for recovery after errors or protocol violations.
  ///
  /// Throws [StateError] if endpoint is not open.
  /// Throws [OSError] if ioctl fails.
  void flushFIFO() {
    assert(_fd != null, 'flushFIFO: Endpoint is not open');

    final result = Ioctl.call(_fd!, .fifoFlush);
    if (result < 0) {
      final error = Errno.toOSError(result);
      log?.error('Failed to flush FIFO: ${error.message}');
      throw error;
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

  /// Configuration for AIO writer (immutable after first use).
  ({int bufferSize, int numBuffers})? _writerConfig;

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

    // Dispose AIO writer
    await _writer?.dispose();
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
    assert(_fd != null, 'clearHalt: Endpoint is not open');

    final result = Ioctl.call(_fd!, .clearHalt);
    if (result < 0) throw Errno.currentOSError;
  }

  @override
  void halt() {
    assert(_fd != null, 'halt: Endpoint is not open');
    // Writing 0 bytes to IN endpoint sends STALL to host
    Unistd.write(_fd!, Uint8List(0));
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
  /// - [numBuffers]: Number of AIO buffers (default: 4)
  ///
  /// Note: [bufferSize] and [numBuffers] are locked after the first call.
  /// Subsequent calls with different values will use the original configuration.
  ///
  /// Returns a Future that completes with the number of bytes written.
  ///
  /// Throws [StateError] if endpoint is not open.
  /// Throws [ArgumentError] if buffer parameters are invalid.
  Future<int> writeAsync(
    Uint8List data, {
    int bufferSize = 16384,
    int numBuffers = 4,
  }) {
    assert(_fd != null, 'writeAsync: Endpoint is not open');

    if (bufferSize <= 0) {
      throw ArgumentError.value(
        bufferSize,
        'bufferSize',
        'Buffer size must be positive',
      );
    }
    if (numBuffers <= 0) {
      throw ArgumentError.value(
        numBuffers,
        'numBuffers',
        'Number of buffers must be positive',
      );
    }

    // Lazy-create writer with locked configuration
    if (_writer == null) {
      _writerConfig = (bufferSize: bufferSize, numBuffers: numBuffers);
      _writer = AioWriter(
        fd: _fd!,
        bufferSize: bufferSize,
        numBuffers: numBuffers,
      );
    }

    return _writer!.write(data);
  }

  /// Flushes all pending asynchronous writes.
  ///
  /// Waits for all queued AIO operations to complete.
  /// Safe to call even if no async writes are pending.
  Future<void> flush() async {
    await _writer?.flush();
  }

  /// Whether there are pending asynchronous writes.
  bool get hasPendingWrites => _writer?.hasPendingWrites ?? false;

  /// Gets the current AIO writer configuration, if any.
  ///
  /// Returns null if writeAsync has never been called.
  ({int bufferSize, int numBuffers})? get writerConfig => _writerConfig;
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

  /// Reader configuration (immutable after stream creation).
  ({int bufferSize, int numBuffers})? _readerConfig;

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

    // Close stream controller
    await _streamController?.close();
    _streamController = null;

    // Dispose AIO reader
    await _reader?.dispose();
    _reader = null;

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
    assert(_fd != null, 'clearHalt: Endpoint is not open');

    final result = Ioctl.call(_fd!, .clearHalt);
    if (result < 0) throw Errno.currentOSError;
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
  List<int> read(int length) {
    assert(_fd != null, 'read: Endpoint is not open');

    if (length < 0) {
      throw ArgumentError.value(length, 'length', 'Length cannot be negative');
    }

    try {
      return Unistd.read(_fd!, length);
    } on OSError catch (e) {
      if (e.errorCode == Errno.eagain) {
        return const [];
      }
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
  /// - Isochronous timing errors (returns empty packets)
  /// - Aborted bulk/interrupt transfers (ignores)
  ///
  /// Parameters:
  /// - [numBuffers]: Number of AIO buffers to use (default: 4)
  ///   More buffers = better throughput but more memory
  ///
  /// Buffer size is determined automatically based on transfer type:
  /// - Bulk: 16KB
  /// - Interrupt: 64 bytes
  /// - Isochronous: 1KB
  /// - Control: 64 bytes
  /// - Or uses maxPacketSize from config if specified
  ///
  /// Throws [StateError] if endpoint is not open.
  /// Throws [ArgumentError] if numBuffers is invalid.
  Stream<Uint8List> stream({int numBuffers = 4}) {
    assert(_fd != null, 'stream: Endpoint is not open');

    if (numBuffers <= 0) {
      throw ArgumentError.value(
        numBuffers,
        'numBuffers',
        'Number of buffers must be positive',
      );
    }

    // Return cached stream if already created
    final controller = _streamController;
    if (controller != null && !controller.isClosed) {
      return controller.stream;
    }

    // Determine buffer size based on transfer type
    final bufferSize = switch (transferType) {
      _ when config.maxPacketSize != null => config.maxPacketSize!,
      TransferType.bulk => 16384,
      TransferType.interrupt => 64,
      TransferType.isochronous => 1024,
      TransferType.control => 64,
    };

    // Create reader if not exists (configuration is locked)
    if (_reader == null) {
      _readerConfig = (bufferSize: bufferSize, numBuffers: numBuffers);
      _reader = AioReader(
        fd: _fd!,
        bufferSize: bufferSize,
        numBuffers: numBuffers,
      );
    }

    // Capture transfer type to avoid capturing 'this'
    final type = transferType;

    // Create new broadcast controller
    _streamController = StreamController<Uint8List>.broadcast();

    // Forward AIO reader stream to controller
    _reader!
        .stream(
          handleError: (errorCode) {
            // Isochronous: return empty on timing errors
            if (type == TransferType.isochronous &&
                (errorCode == Errno.eio || errorCode == Errno.etimedout)) {
              return AioErrorAction.empty;
            }

            // Bulk/Interrupt: ignore aborted transfers
            if (errorCode == Errno.epipe &&
                (type == TransferType.bulk || type == TransferType.interrupt)) {
              return AioErrorAction.ignore;
            }

            // All other errors propagate to stream
            return AioErrorAction.error;
          },
        )
        .listen(
          _streamController?.add,
          onError: _streamController?.addError,
          onDone: _streamController?.close,
          cancelOnError: false,
        );

    return _streamController!.stream;
  }

  /// Whether there is an active stream.
  bool get hasActiveStream =>
      _streamController != null && !_streamController!.isClosed;

  /// Gets the current AIO reader configuration, if any.
  ///
  /// Returns null if stream() has never been called.
  ({int bufferSize, int numBuffers})? get readerConfig => _readerConfig;
}
