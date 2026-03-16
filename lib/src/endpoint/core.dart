import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:using/using.dart';

import '/src/platform/platform.dart';
import '/usb_gadget.dart';
import 'aio/aio.dart';

/// Base class for FunctionFs endpoint file descriptors.
///
/// Manages the low-level lifecycle (open, close, halt) for USB endpoints
/// exposed via the Linux FunctionFs (FFS) interface.
abstract class EndpointFile with USBGadgetLogger, Releasable {
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
  Future<void> release() async {
    if (isReleased) return;
    super.release();
    await close();
  }

  @override
  String toString() => 'EndpointFile(path: $path, open: ${_fd != null})';
}

/// Manages the USB control endpoint (EP0) for FunctionFs.
///
/// Handles the FunctionFs mount lifecycle and provides a broadcast stream
/// for USB setup events (BIND, ENABLE, SETUP, etc.).
final class EndpointControlFile extends EndpointFile {
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

  /// Maximum bytes read per epoll wake (4 events * 12 bytes each).
  static const int eventBufferSize = 4 * FunctionFsEvent.size;

  /// The mount manager responsible for the `functionfs` filesystem.
  final FunctionFsMount _mount;

  /// Broadcast controller for emitting [FunctionFsEvent] objects.
  StreamController<FunctionFsEvent>? _streamController;

  /// Periodic timer that reads from the non-blocking EP0 file descriptor
  /// at a fixed interval to deliver kernel USB events to the stream.
  Timer? _pollingTimer;

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
    _pollingTimer?.cancel();
    _pollingTimer = null;

    await _streamController?.close();
    _streamController = null;

    final fd = _fd;
    if (fd == null) return;
    try {
      Unistd.close(fd);
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
    final fd = _fd;
    if (fd == null) throw StateError('Cannot halt: Endpoint is not open');

    try {
      Unistd.read(fd, 0);
    } on OSError catch (e) {
      final code = e.errorCode;
      if (const {epipe, eshutdown, enotconn}.contains(code)) {
        log?.warn('Halt ignored: Host disconnected (${e.errorCode})');
      } else {
        rethrow;
      }
    }
  }

  /// Performs a synchronous write to EP0, retrying on `EAGAIN`.
  void write(Uint8List data) {
    final fd = _fd;
    if (fd == null) throw StateError('write: Endpoint is not open');

    var offset = 0;
    while (offset < data.length) {
      try {
        offset += Unistd.write(fd, data.sublist(offset));
      } on OSError catch (e) {
        if (e.errorCode == eagain) continue;
        rethrow;
      }
    }
  }

  /// Reads up to [length] bytes from EP0 in non-blocking mode.
  Uint8List read(int length) {
    final fd = _fd;
    if (fd == null) throw StateError('read: Endpoint is not open');
    return Unistd.read(fd, length);
  }

  /// Acknowledges a host request with a Zero-Length Packet (ZLP).
  void ack() {
    final fd = _fd;
    if (fd == null) throw StateError('Cannot ACK: Endpoint is not open');
    Unistd.write(fd, Uint8List(0));
  }

  /// A broadcast stream emitting control events from the kernel.
  Stream<FunctionFsEvent> get stream {
    if (_fd == null) throw StateError('Cannot create stream: EP0 not open');

    final controller = _streamController;
    if (controller != null && !controller.isClosed) {
      return controller.stream;
    }

    _streamController ??= .broadcast(
      onListen: _startReading,
      onCancel: _stopReading,
    );
    return _streamController!.stream;
  }

  void _startReading() {
    _pollingTimer ??= .periodic(const .new(milliseconds: 1), (_) {
      try {
        final data = Unistd.read(_fd!, eventBufferSize);
        const offset = FunctionFsEvent.size;
        for (var i = 0; i + offset <= data.length; i += offset) {
          _streamController?.add(.fromBytes(data.sublist(i, i + offset)));
        }
      } on OSError catch (err, st) {
        if (err.errorCode case eagain || einval) return;
        _streamController?.addError(err, st);
      }
    });
  }

  void _stopReading() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }
}

/// Manages a USB IN endpoint (device-to-host) using Linux AIO.
///
/// Provides high-performance asynchronous writes with automatic buffer
/// management and backpressure handling.
final class EndpointInFile extends EndpointFile {
  /// Creates an IN endpoint with optional custom AIO instance.
  EndpointInFile(super.path, {required this.config});

  /// Endpoint configuration defining transfer characteristics.
  final EndpointConfig config;

  /// AIO context for asynchronous operations.
  Aio? _aio;

  /// Writer sink for asynchronous writes.
  late AioSink _aioSink;

  @override
  Future<void> open() async {
    if (_fd != null) return;
    final fd = Unistd.open(path, const [.wrOnly]);
    _aio ??= Aio.fromEndpointConfig(fd, config);
    _aioSink = _aio!.sink;
    _fd = fd;
  }

  @override
  Future<void> close() async {
    final fd = _fd;
    if (fd == null) return;

    await _aioSink.release();
    _aio?.release();
    _aio = null;

    Unistd.close(fd);
    _fd = null;
  }

  @override
  void halt() {
    final fd = _fd;
    if (fd != null) Unistd.write(fd, Uint8List(0));
  }

  /// Enqueues [data] for asynchronous transmission to the host.
  ///
  /// The data is handed off to the [AioSink] and transmitted via Linux AIO.
  /// Backpressure behaviour is determined by the AIO configuration.
  ///
  /// Throws [StateError] if endpoint is not open.
  void write(Uint8List data) {
    if (_fd == null) throw StateError('write: Endpoint is not open');
    _aioSink.add(data);
  }

  /// Flushes all pending writes and waits for completion.
  ///
  /// Closes the current [AioSink] (draining all queued operations) and then
  /// reopens a fresh sink so the endpoint can continue to be used.
  /// Returns a future that completes when all queued data has been
  /// transmitted to the host.
  Future<void> flush() async {
    if (_fd == null) return; // No-op before open().
    await _aioSink.release();
    _aioSink = _aio!.sink;
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
    final fd = _fd;
    if (fd == null) throw StateError('Cannot clear halt: Endpoint is not open');

    try {
      Ioctl.call(fd, .clearHalt);
    } on OSError catch (e) {
      if (e.errorCode == einval) {
        // Endpoint not halted, this is not an error
        return;
      }

      throw StateError(
        'Failed to clear halt on IN endpoint: ${e.message} (errno: ${e.errorCode})',
      );
    }
  }

  @override
  Future<void> release() async {
    if (isReleased) return;
    super.release();
    await this.close();
  }
}

/// Manages a USB OUT endpoint (host-to-device) using Linux AIO.
///
/// Provides high-performance asynchronous reads with automatic buffer
/// management and demand-driven backpressure.
final class EndpointOutFile extends EndpointFile {
  EndpointOutFile(super.path, {required this.config});

  final EndpointConfig config;

  Aio? _aio;

  AioStream? _aioStream;

  /// Stable proxy that outlives individual [AioStream] instances.
  final StreamController<Uint8List> _proxy = .broadcast();

  /// Active subscription forwarding [_aioStream] → [_proxy].
  /// `null` until the stream is first accessed or [refresh] is called.
  StreamSubscription<Uint8List>? _aioStreamSub;

  /// Subscribes [_aioStream] into [_proxy].
  ///
  /// Data and errors are forwarded. `onDone` is intentionally omitted — EOF
  /// on the inner stream means kernel disconnect/suspend, not end-of-channel.
  void _connectReader() {
    _aioStreamSub?.cancel();
    _aioStreamSub = _aioStream?.stream.listen(
      _proxy.add,
      onError: _proxy.addError,
      // onDone intentionally omitted — keeps the proxy open across cycles.
    );
  }

  // ---------------------------------------------------------------------------

  @override
  Future<void> open() async {
    if (_fd != null) return;
    final fd = Unistd.open(path, const [.rdOnly]);
    _aio ??= Aio.fromEndpointConfig(fd, config);
    _aioStream = _aio!.stream;
    _fd = fd;
  }

  @override
  Future<void> close() async {
    final fd = _fd;
    if (fd == null) return;

    _aioStreamSub?.cancel();
    _aioStreamSub = null;
    _aioStream?.release();
    _aioStream = null;

    _aio?.release();
    _aio = null;

    await _proxy.close();

    Unistd.close(fd);
    _fd = null;
  }

  @override
  void halt() => throw UnsupportedError('Manual STALL not supported for OUT');

  /// Stable broadcast stream of data received from the host.
  ///
  /// Accessing this getter for the first time wires the inner [AioStream] into
  /// the proxy and starts submitting reads to the kernel. The stream remains
  /// open — and delivers data — across any number of disable/enable cycles.
  Stream<Uint8List> get stream {
    // Lazily connect on first access.  Guarded so a second call (e.g. after
    // the consumer re-reads the getter) does not reset an active subscription.
    if (_aioStreamSub == null && _fd != null && !_proxy.isClosed) {
      _connectReader();
    }
    return _proxy.stream;
  }

  /// Reprimes the endpoint to resume receiving data after a USB reset or
  /// re-configuration.
  ///
  /// When the host de-configures the function (e.g., during a power cycle or
  /// mode switch), the kernel terminates all in-flight asynchronous transfers.
  /// This causes the current [AioStream] to reach end-of-file and stop reading.
  ///
  /// This method replaces the exhausted internal stream with a fresh one
  /// without disrupting existing subscribers to the public [stream].
  ///
  /// No-op if the endpoint is not currently open.
  void refresh() {
    final fd = _fd;
    if (fd == null) return;

    _aioStreamSub?.cancel();
    _aioStreamSub = null;

    _aioStream?.release();
    _aioStream = _aio!.stream;
    _connectReader();
  }

  @override
  Future<void> release() async {
    if (isReleased) return;
    super.release();
    await close();
  }
}
