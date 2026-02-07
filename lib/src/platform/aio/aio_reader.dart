import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:usb_gadget/src/platform/errno/errno.dart';
import 'package:using/using.dart';

import 'aio.ffi.dart';
import 'aio_context.dart';

/// Asynchronous I/O reader using Linux kernel AIO with automatic windowing.
///
/// Provides a [Stream]-based interface for reading data from a file descriptor
/// using Linux kernel AIO. Automatically manages a sliding window of read
/// operations to maximize throughput while minimizing latency.
///
/// ## Architecture
///
/// ```text
/// stream.listen()
///     │
///     ├──> Create StreamController
///     ├──> Submit initial reads (fill window)
///     │       ├──> Acquire buffer from pool
///     │       └──> io_submit() to kernel
///     └──> Start polling timer
///
/// [Timer: config.interval]
///     │
///     ├──> io_getevents() (harvest completions)
///     ├──> Copy data to Uint8List
///     ├──> Yield to stream
///     ├──> Release buffer to pool
///     └──> Submit next read (maintain window)
/// ```
///
/// ## Usage
///
/// ```dart
/// final config = AioConfig(bufferSize: 32768, maxConcurrent: 8);
/// final reader = AioReader(fd, config);
///
/// await for (final data in reader.stream) {
///   print('Received: ${data.length} bytes');
/// }
///
/// reader.release();
/// ```
final class AioReader with Releasable {
  /// Creates an [AioReader] for the given file descriptor.
  ///
  /// The [_fd] must be a valid, open file descriptor. The [config] parameter
  /// controls buffer sizes, concurrency, and polling behavior.
  ///
  /// Example:
  ///
  /// ```dart
  /// final reader = AioReader(fd, AioConfig(bufferSize: 16384));
  /// ```
  AioReader(this._fd, [this.config = const AioConfig()]);

  final int _fd;

  /// The configuration for this reader.
  final AioConfig config;

  AioContext? _context;
  BufferPool? _bufferPool;
  Timer? _pollTimer;
  StreamController<Uint8List>? _controller;

  int _nextOpId = 0;
  int _fileOffset = 0;
  bool _eofReached = false;

  /// Creates a stream of data read from the file descriptor.
  ///
  /// The stream automatically submits read operations and yields data as it
  /// becomes available. Only one stream can be created per [AioReader] instance.
  ///
  /// Throws [StateError] if the stream has already been created or if the
  /// reader has been released.
  Stream<Uint8List> get stream {
    if (_controller != null) {
      throw StateError('Stream already created');
    }

    if (isReleased) {
      throw StateError('AioReader has been released');
    }

    _controller = StreamController<Uint8List>(
      onListen: _start,
      onCancel: release,
    );

    return _controller!.stream;
  }

  // Initializes the AIO context and buffer pool, then submits initial reads.
  void _start() {
    _context = AioContext(maxConcurrent: config.maxConcurrent);
    _bufferPool = BufferPool(config.bufferSize, config.maxConcurrent);

    // Submit initial read operations to fill the window
    for (var i = 0; i < config.maxConcurrent && !_eofReached; i++) {
      _submitRead();
    }

    // Start polling timer for completion harvesting
    _pollTimer = Timer.periodic(config.interval, (_) {
      if (!isReleased && !_eofReached) {
        _harvestCompletions();
      }
    });
  }

  // Submits a single read operation to the kernel.
  void _submitRead() {
    if (_eofReached || _context == null || isReleased) return;

    final buffer = _bufferPool!.acquire();
    if (buffer == null) return; // No buffers available

    final opId = _nextOpId++;
    final offset = _fileOffset;
    _fileOffset += config.bufferSize;

    ffi.Pointer<iocb>? iocbPtr;
    TrackedOperation? op;

    try {
      iocbPtr = calloc<iocb>()
        ..ref.aio_fildes = _fd
        // IOCB_CMD_PREAD
        ..ref.aio_lio_opcode = 0
        ..ref.aio_reqprio = 0
        ..ref.aio_rw_flags = 0
        ..ref.data = ffi.Pointer<ffi.Void>.fromAddress(opId)
        ..ref.u.c.buf = buffer.cast<ffi.Void>()
        ..ref.u.c.nbytes = config.bufferSize
        ..ref.u.c.offset = offset;

      op = TrackedOperation(
        id: OperationId(opId),
        type: .read,
        buffer: buffer,
        size: config.bufferSize,
        offset: offset,
        block: iocbPtr,
        userData: opId,
      );

      _context!.submit([op]);
    } catch (e) {
      if (op != null) {
        op.free();
      } else if (iocbPtr != null) {
        calloc.free(iocbPtr);
      }
      _bufferPool!.releaseBuffer(buffer);
      rethrow;
    }
  }

  // Harvests completed operations from the kernel.
  void _harvestCompletions() {
    if (_context == null || isReleased) return;

    try {
      _context!
          .getCompletions(maxEvents: 16, timeout: Duration.zero)
          .forEach(_handleCompletion);
    } on OSError catch (e) {
      // Handle EBADF gracefully (file descriptor closed)
      if (e.errorCode == Errno.ebadf) {
        // EBADF - stop harvesting
        _controller?.close();
        return;
      }
      _controller?.addError(e);
    }
  }

  // Handles a single completed operation.
  void _handleCompletion(CompletedOperation completion) {
    final op = completion.operation;

    try {
      if (!completion.isSuccess) {
        _controller?.addError(completion.error ?? const OSError('Read failed'));
        return;
      }

      if (completion.isEof) {
        _eofReached = true;
        _controller?.close();
        return;
      }

      // Copy data and yield to stream
      _controller?.add(
        .fromList(op.buffer.asTypedList(completion.bytesTransferred)),
      );

      // Submit another read to maintain the window
      if (!_eofReached && !isReleased) {
        _submitRead();
      }
    } finally {
      _bufferPool?.releaseBuffer(op.buffer);
      op.free();
    }
  }

  @override
  void release() {
    super.release();
    _pollTimer?.cancel();
    _pollTimer = null;

    _controller?.close();
    _controller = null;

    _bufferPool?.release();
    _bufferPool = null;

    _context?.release();
    _context = null;
  }
}
