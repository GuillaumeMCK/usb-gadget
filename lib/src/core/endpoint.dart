import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '/src/ffi/ffi.dart';
import '/usb_gadget.dart';

/// Base class for FunctionFs endpoint file descriptors.
///
/// Manages the lifecycle (open, close, halt) for USB endpoints
/// exposed via the Linux FunctionFs interface.
abstract class EndpointFile {
  /// Creates an endpoint file manager for [path].
  EndpointFile(this.path);

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
  void open();

  /// Closes the underlying file descriptor.
  ///
  /// Clears the internal file descriptor after closing.
  /// Safe to call multiple times (idempotent).
  void close();

  /// Whether the endpoint is currently halted (STALL state).
  bool get isHalted;

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

/// Configuration for FunctionFS mount behavior.
class FunctionFsMountConfig {
  const FunctionFsMountConfig({
    this.autoMount = true,
    this.mountDelay = const Duration(milliseconds: 50),
    this.cleanupOnClose = true,
    this.forceUnmount = true,
  });

  /// Automatically mount FunctionFS if not already mounted.
  final bool autoMount;

  /// Delay after mounting before opening endpoint files.
  /// Gives kernel time to create endpoint files.
  final Duration mountDelay;

  /// Automatically unmount when closing if we mounted it.
  final bool cleanupOnClose;

  /// Use force unmount (MNT_DETACH) as fallback.
  final bool forceUnmount;
}

/// Manages the USB control endpoint (EP0) for FunctionFs.
///
/// EP0 is special:
/// - Handles control transfers and setup requests
/// - Can have multiple stream listeners (broadcast)
/// - Manages FunctionFS mounting/unmounting
/// - Provides blocking read/write for descriptor setup
/// - Provides event stream for asynchronous operation
class EndpointControlFile extends EndpointFile {
  EndpointControlFile(
    super.path, {
    required this.mountPoint,
    required this.mountSource,
    bool autoMount = true,
    FunctionFsMountConfig? mountConfig,
  }) : mountConfig = mountConfig ?? FunctionFsMountConfig(autoMount: autoMount);

  /// Mount point for FunctionFS filesystem.
  final String mountPoint;

  /// Mount source name (used as filesystem label).
  final String mountSource;

  /// Mount configuration.
  final FunctionFsMountConfig mountConfig;

  /// Whether we mounted the filesystem (and should unmount on close).
  bool _didMount = false;

  /// Cached stream controller for event broadcasting.
  StreamController<FunctionFsEvent>? _streamController;

  /// Whether the mount point exists and appears to be mounted.
  bool get isMounted {
    final ep0File = File(path);
    return ep0File.existsSync();
  }

  @override
  void open() {
    if (_fd != null) {
      throw StateError('Endpoint is already open');
    }

    final dir = Directory(mountPoint);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final file = File(path);
    if (!file.existsSync()) {
      if (!mountConfig.autoMount) {
        throw StateError(
          'FunctionFS not mounted at $mountPoint and autoMount is disabled. '
          'Please mount manually or enable autoMount.',
        );
      }

      _mountFunctionFs();
      _didMount = true;

      // Give kernel time to create endpoint files
      if (mountConfig.mountDelay > Duration.zero) {
        sleep(mountConfig.mountDelay);
      }

      // Verify mount succeeded
      if (!file.existsSync()) {
        throw StateError(
          'Failed to mount FunctionFS at $mountPoint. '
          'EP0 file does not exist after mount.',
        );
      }
    }

    _fd = Unistd.open(path, const [OpenFlag.rdWr, OpenFlag.nonBlock]);
  }

  /// Mounts the FunctionFS filesystem.
  void _mountFunctionFs() {
    try {
      Mount.mount(
        source: mountSource,
        target: mountPoint,
        filesystemType: FilesystemType.functionfs,
      );
    } on OSError catch (e) {
      throw StateError(
        'Failed to mount FunctionFS at $mountPoint: ${e.message} '
        '(errno: ${e.errorCode}). '
        'Ensure you have root permissions and CONFIG_USB_CONFIGFS_F_FS is enabled.',
      );
    }
  }

  @override
  void close() {
    final fd = _fd;
    if (fd == null) return;

    // Close stream controller
    _streamController?.close();
    _streamController = null;

    // Close file descriptor
    try {
      Unistd.close(fd);
    } catch (e) {}
    _fd = null;

    // Unmount if we mounted it
    if (_didMount && mountConfig.cleanupOnClose) {
      _unmountFunctionFs();
      _didMount = false;
    }
  }

  /// Unmounts the FunctionFS filesystem.
  void _unmountFunctionFs() {
    try {
      Errno.retry(
        () => Mount.umount(mountPoint),
        retryOn: [Errno.ebusy],
        maxRetries: 2,
      );
    } catch (_) {
      print(
        'Warning: Normal unmount failed for $mountPoint, trying force unmount.',
      );
      Errno.retry(
        () => Mount.umount2(mountPoint, [.detach]),
        retryOn: [Errno.ebusy],
        maxRetries: 2,
        quiet: true,
      );
    }
  }

  @override
  bool get isHalted => false;

  @override
  void clearHalt() {
    // EP0 doesn't support halt/clear operations
  }

  @override
  void halt() {
    assert(fd != null, 'halt');
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
  /// Throws [StateError] if endpoint is not open.
  void write(Uint8List data) {
    assert(fd != null, 'write');

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
  /// Throws [StateError] if endpoint is not open.
  List<int> read(int length) {
    assert(fd != null, 'read');

    try {
      return Unistd.read(_fd!, length);
    } on OSError catch (e) {
      if (e.errorCode == Errno.eagain) {
        return const [];
      }
      rethrow;
    }
  }

  /// Event buffer size (48 bytes = 4 events of 12 bytes each).
  static const int eventBufferSize = 4 * FunctionFsEvent.size;

  /// Polling interval in milliseconds.
  ///
  /// Default is 100ms which provides good balance between responsiveness
  /// and CPU usage. Can be adjusted based on requirements:
  /// - Lower (e.g., 10ms) for latency-sensitive applications
  /// - Higher (e.g., 250ms) for power-sensitive applications
  static const Duration pollingInterval = Duration(milliseconds: 100);

  /// Creates a stream of FunctionFS events using async polling.
  ///
  /// EP0 is special and can have multiple stream listeners.
  /// The stream is cached and reused for all listeners.
  /// This is a broadcast stream that multiple listeners can subscribe to.
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
  /// Throws [StateError] if endpoint is not open.
  Stream<FunctionFsEvent> stream() {
    assert(fd != null, 'stream');

    final controller = _streamController;
    if (controller != null) return controller.stream;

    late StreamController<FunctionFsEvent> newController;
    newController = StreamController<FunctionFsEvent>.broadcast(
      onListen: () => _startPolling(eventBufferSize, newController),
      onCancel: () {
        _streamController?.close();
        _streamController = null;
      },
    );
    _streamController = newController;

    return newController.stream;
  }

  /// Polls EP0 for events and adds them to the stream.
  Future<void> _startPolling(
    int bufferSize,
    StreamController<FunctionFsEvent> controller,
  ) async {
    while (!controller.isClosed && _fd != null) {
      try {
        FunctionFsEvent.fromBytesMultiple(
          read(bufferSize),
        ).forEach(controller.add);
      } on OSError catch (e, st) {
        if (e.errorCode == Errno.eagain) {
          // No data available, continue polling
        } else if (e.errorCode == Errno.ebadf) {
          // File descriptor closed, stop polling
          break;
        } else {
          controller.addError(e, st);
        }
      } catch (e, st) {
        controller.addError(e, st);
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
    assert(fd != null, 'flushFIFO');

    final result = Ioctl.call(_fd!, FunctionFsIoctl.fifoFlush);
    if (result < 0) throw Errno.toOSError(result);
  }

  /// Gets the FIFO status (number of bytes in buffer).
  ///
  /// Returns the number of bytes currently in the endpoint's FIFO.
  ///
  /// Throws [StateError] if endpoint is not open.
  /// Returns negative value on error (can be converted with Errno.toOSError).
  int getFIFOStatus() {
    assert(fd != null, 'getFIFOStatus');
    return Ioctl.call(_fd!, FunctionFsIoctl.fifoStatus);
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
  void open() {
    if (_fd != null) {
      throw StateError('Endpoint is already open');
    }
    _fd = Unistd.open(path, const [OpenFlag.wrOnly]);
  }

  @override
  void close() {
    if (_fd == null) return;

    // Dispose AIO writer
    _writer?.dispose();
    _writer = null;

    // Close file descriptor
    try {
      Unistd.close(_fd!);
    } catch (e) {
      // Best effort close
    }
    _fd = null;
  }

  @override
  bool get isHalted => false; // No way to read halt state

  @override
  void clearHalt() {
    assert(fd != null, 'clearHalt');

    final result = Ioctl.call(_fd!, FunctionFsIoctl.clearHalt);
    if (result < 0) throw Errno.currentOSError;
  }

  @override
  void halt() {
    assert(fd != null, 'halt');

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
    assert(fd != null, 'write');
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
  /// Returns a Future that completes with the number of bytes written.
  ///
  /// Throws [StateError] if endpoint is not open.
  Future<int> writeAsync(
    Uint8List data, {
    int bufferSize = 16384,
    int numBuffers = 4,
  }) {
    assert(fd != null, 'writeAsync');

    // Lazy-create writer
    _writer ??= AioWriter(
      fd: _fd!,
      bufferSize: bufferSize,
      numBuffers: numBuffers,
    );

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
  Stream<Uint8List>? _stream;

  @override
  void open() {
    if (_fd != null) {
      throw StateError('Endpoint is already open');
    }
    _fd = Unistd.open(path, const [OpenFlag.rdOnly]);
  }

  @override
  void close() {
    if (_fd == null) return;

    // Dispose AIO reader and stream
    _reader?.dispose();
    _reader = null;
    _stream = null;

    // Close file descriptor
    try {
      Unistd.close(_fd!);
    } catch (e) {
      // Best effort close
    }
    _fd = null;
  }

  @override
  bool get isHalted => false; // No way to read halt state

  @override
  void clearHalt() {
    assert(fd != null, 'clearHalt');

    final result = Ioctl.call(_fd!, FunctionFsIoctl.clearHalt);
    if (result < 0) throw Errno.currentOSError;
  }

  @override
  void halt() {
    // Cannot halt OUT endpoints in FunctionFS.
    // The host controls data flow on OUT endpoints.
    throw UnsupportedError('Cannot halt OUT endpoints in FunctionFS');
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
  List<int> read(int length) {
    assert(fd != null, 'read');

    try {
      return Unistd.read(_fd!, length);
    } on OSError catch (e) {
      if (e.errorCode == Errno.eagain) {
        return const [];
      }
      rethrow;
    }
  }

  /// Creates a stream using Linux AIO for high throughput.
  ///
  /// **IMPORTANT**: Only ONE stream can be created per endpoint.
  /// The stream is cached and reused for all listeners.
  /// This is a broadcast stream that multiple listeners can subscribe to.
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
  /// Throws [StateError] if endpoint is not open.
  Stream<Uint8List> stream({int numBuffers = 4}) {
    assert(fd != null, 'stream');

    // Return cached stream if already created
    if (_stream != null) return _stream!;

    // Determine buffer size based on transfer type
    final bufferSize = switch (transferType) {
      _ when config.maxPacketSize != null => config.maxPacketSize!,
      TransferType.bulk => 16384,
      TransferType.interrupt => 64,
      TransferType.isochronous => 1024,
      TransferType.control => 64,
    };

    // Create reader if not exists
    _reader ??= AioReader(
      fd: _fd!,
      bufferSize: bufferSize,
      numBuffers: numBuffers,
    );

    // Capture transfer type locally to avoid closure capturing 'this'
    final type = transferType;

    // Create broadcast stream so multiple listeners can subscribe
    return _stream = _reader!
        .stream(
          handleError: (errorCode) {
            // Isochronous: return empty on timing errors
            // These are expected for isochronous transfers
            if (type == TransferType.isochronous &&
                (errorCode == Errno.eio || errorCode == Errno.etimedout)) {
              return AioErrorAction.empty;
            }

            // Bulk/Interrupt: ignore aborted transfers
            // Host may abort pending transfers when closing
            if (errorCode == Errno.epipe &&
                (type == TransferType.bulk || type == TransferType.interrupt)) {
              return AioErrorAction.ignore;
            }

            // All other errors propagate to stream
            return AioErrorAction.error;
          },
        )
        .asBroadcastStream();
  }

  /// Whether there is an active stream.
  bool get hasActiveStream => _stream != null;
}
