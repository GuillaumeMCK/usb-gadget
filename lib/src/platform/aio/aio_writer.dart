import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:using/using.dart';

import '../errno/errno.dart';
import 'aio.ffi.dart';
import 'aio_context.dart';

/// Asynchronous I/O writer using Linux kernel AIO with automatic backpressure.
///
/// Provides a [Future]-based interface for writing data to a file descriptor
/// using Linux kernel AIO. Automatically manages write queuing and backpressure
/// when buffers are unavailable.
///
/// ## Architecture
///
/// ```text
/// write(data)
///     │
///     ├──> Create completer
///     ├──> Add to queue
///     ├──> Process queue
///     │       ├──> Acquire buffer from pool
///     │       ├──> Copy data to buffer
///     │       └──> io_submit() to kernel
///     └──> Return future
///
/// [Timer: config.interval]
///     │
///     ├──> io_getevents() (harvest completions)
///     ├──> Release buffer to pool
///     ├──> Process queue (submit pending)
///     └──> Complete future
/// ```
///
/// ## Usage
///
/// ```dart
/// final config = AioConfig(bufferSize: 32768, maxConcurrent: 8);
/// final writer = AioWriter(fd, config);
///
/// await writer.write(data);
/// await writer.flush();
/// writer.release();
/// ```
final class AioWriter with Releasable {
  /// Creates an [AioWriter] for the given file descriptor.
  ///
  /// The [fd] must be a valid, open file descriptor. The [config] parameter
  /// controls buffer sizes, concurrency, and polling behavior.
  ///
  /// Example:
  ///
  /// ```dart
  /// final writer = AioWriter(fd, AioConfig(bufferSize: 16384));
  /// ```
  AioWriter(this._fd, [this.config = const AioConfig()]) {
    _context = AioContext(maxConcurrent: config.maxConcurrent);
    _bufferPool = BufferPool(config.bufferSize, config.maxConcurrent);

    // Start polling timer for completion harvesting
    _pollTimer = Timer.periodic(config.interval, (_) {
      if (!isReleased) {
        _harvestCompletions();
      }
    });
  }

  final int _fd;

  /// The configuration for this writer.
  final AioConfig config;

  AioContext? _context;
  BufferPool? _bufferPool;
  Timer? _pollTimer;

  int _nextOpId = 0;
  final Map<int, _WriteRequest> _pending = {};
  final List<_QueuedWrite> _queue = [];

  /// Writes data asynchronously using Linux AIO.
  ///
  /// Queues the write operation and returns a [Future] that completes with the
  /// number of bytes written. If buffers are unavailable, the write is queued
  /// and will be submitted when a buffer becomes available.
  ///
  /// Throws [StateError] if the writer has been released or if the file
  /// descriptor is invalid.
  Future<int> write(Uint8List data) {
    if (isReleased) {
      throw StateError('AioWriter has been released');
    }

    if (_fd < 0) {
      throw StateError('Invalid file descriptor: $_fd');
    }

    final request = _WriteRequest(data);
    final opId = _nextOpId++;
    _pending[opId] = request;

    // Queue the write
    _queue.add(_QueuedWrite(opId, data));
    _processQueue();

    return request.completer.future;
  }

  // Processes the write queue, submitting operations while buffers are available.
  void _processQueue() {
    while (_queue.isNotEmpty && _bufferPool!.available > 0 && !isReleased) {
      final queued = _queue.removeAt(0);
      try {
        _submitWrite(queued.opId, queued.data);
      } catch (e) {
        final request = _pending.remove(queued.opId);
        request?.completer.completeError(e);
      }
    }
  }

  // Submits a single write operation to the kernel.
  void _submitWrite(int opId, Uint8List data) {
    final buffer = _bufferPool!.acquire();
    if (buffer == null) {
      // This shouldn't happen if _processQueue is working correctly
      throw StateError('No buffers available');
    }

    // Copy data to buffer
    buffer.asTypedList(data.length).setAll(0, data);

    final iocbPtr = calloc<iocb>()
      ..ref.aio_fildes = _fd
      // IOCB_CMD_PWRITE
      ..ref.aio_lio_opcode = 1
      ..ref.aio_reqprio = 0
      ..ref.aio_rw_flags = 0
      ..ref.data = ffi.Pointer<ffi.Void>.fromAddress(opId)
      ..ref.u.c.buf = buffer.cast<ffi.Void>()
      ..ref.u.c.nbytes = data.length
      ..ref.u.c.offset = 0;

    final op = TrackedOperation(
      id: OperationId(opId),
      type: OperationType.write,
      buffer: buffer,
      size: data.length,
      offset: 0,
      block: iocbPtr,
      userData: opId,
    );

    _context!.submit([op]);
  }

  // Harvests completed operations from the kernel.
  void _harvestCompletions() {
    if (_context == null || isReleased) return;

    try {
      _context!
          .getCompletions(maxEvents: 16, timeout: .zero)
          .forEach(_handleCompletion);
    } on OSError catch (e) {
      // Handle EBADF gracefully (file descriptor closed)
      if (e.errorCode == Errno.ebadf) {
        // EBADF - stop harvesting
        return;
      }
      rethrow;
    }
  }

  // Handles a single completed operation.
  void _handleCompletion(CompletedOperation completion) {
    final op = completion.operation;
    final opId = op.userData! as int;
    final request = _pending.remove(opId);

    // Release buffer
    _bufferPool!.releaseBuffer(op.buffer);
    op.free();

    // Process queue now that a buffer is available
    _processQueue();

    if (request == null) {
      // Already completed or cancelled
      return;
    }

    if (completion.isSuccess) {
      request.completer.complete(completion.bytesTransferred);
    } else {
      request.completer.completeError(
        completion.error ?? const OSError('Write failed'),
      );
    }
  }

  /// Flushes all pending writes.
  ///
  /// Waits for all in-flight operations to complete. Returns immediately if
  /// the writer has been released.
  Future<void> flush() async {
    if (isReleased) return;

    while (_pending.isNotEmpty && !isReleased) {
      await Future<void>.delayed(config.interval);
    }
  }

  @override
  void release() {
    if (!isReleased) {
      _pollTimer?.cancel();
      _pollTimer = null;

      // Complete any pending requests with error
      for (final request in _pending.values) {
        if (!request.completer.isCompleted) {
          request.completer.completeError(
            StateError('AioWriter released before completion'),
          );
        }
      }
      _pending.clear();

      _bufferPool?.release();
      _bufferPool = null;

      _context?.release();
      _context = null;

      super.release();
    }
  }
}

// Internal class representing a pending write request.
@immutable
final class _WriteRequest {
  _WriteRequest(this.data) : completer = Completer<int>();

  final Uint8List data;
  final Completer<int> completer;
}

// Internal class representing a queued write operation.
@immutable
final class _QueuedWrite {
  const _QueuedWrite(this.opId, this.data);

  final int opId;
  final Uint8List data;
}
