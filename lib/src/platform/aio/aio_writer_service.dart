import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:squadron/squadron.dart';
import 'package:using/using.dart';

import 'aio.ffi.dart';
import 'aio_context.dart';

/// Result of a write operation.
final class WriteResult {
  /// Creates a [WriteResult].
  const WriteResult(this.id, this.bytesWritten, [this.error]);

  /// The unique identifier of the write operation.
  final int id;

  /// Number of bytes successfully written.
  final int bytesWritten;

  /// Optional error object, if the operation failed.
  final Object? error;
}

/// Service for writing data using Linux AIO in a worker thread.
base class AioWriterService with Releasable implements WorkerService {
  AioWriterService();

  AioContext? _context;
  BufferPool? _bufferPool;

  int _fd = -1;
  int _bufferSize = 0;
  int _fileOffset = 0;
  int _nextOpId = 0;

  final List<_QueuedWrite> _writeQueue = [];
  final Map<int, _WriteTracker> _trackers = {};

  bool _initialized = false;

  /// Command IDs
  static const cmdInitialize = 1;
  static const cmdWrite = 2;
  static const cmdFlush = 3;

  @override
  late final operations = OperationsMap({
    /// Command to initialize the service.
    cmdInitialize: (WorkerRequest r) =>
        _initialize(r.args[0] as int, r.args[1] as int, r.args[2] as int),

    /// Command to perform a write operation.
    cmdWrite: (WorkerRequest r) =>
        _write(r.args[0] as int, r.args[1] as Uint8List),

    /// Command to flush pending writes.
    cmdFlush: (WorkerRequest r) => _flush(r.args[0] as int),
  });

  /// Initialize the AIO context and buffer pool.
  Future<void> _initialize(int fd, int bufferSize, int maxInFlight) async {
    if (_initialized) {
      throw StateError('Already initialized');
    }

    _fd = fd;
    _bufferSize = bufferSize;
    _context = AioContext(maxConcurrent: maxInFlight);
    _bufferPool = BufferPool(bufferSize, maxInFlight);
    _initialized = true;
  }

  /// Write data to the file descriptor.
  Future<WriteResult> _write(int writeId, Uint8List data) async {
    if (!_initialized) {
      throw StateError('Not initialized');
    }

    if (isReleased) {
      throw StateError('Service has been released');
    }

    // Split into chunks
    var offset = 0;
    final chunks = <Uint8List>[];

    while (offset < data.length) {
      final size = (data.length - offset).clamp(0, _bufferSize);
      chunks.add(
        Uint8List.view(data.buffer, data.offsetInBytes + offset, size),
      );
      offset += size;
    }

    _trackers[writeId] = _WriteTracker(writeId, data.length, chunks.length);

    for (final chunk in chunks) {
      if (isReleased) {
        return WriteResult(writeId, 0, const OSError('Service released'));
      }
      _writeQueue.add(_QueuedWrite(writeId, chunk, _fileOffset));
      _fileOffset += chunk.length;
    }

    // Process the queue
    await _processQueue();

    // Wait for all chunks to complete
    final tracker = _trackers[writeId];
    while (tracker != null &&
        tracker.completed < tracker.totalChunks &&
        !isReleased) {
      final completions = _context!.getCompletions(
        minEvents: 1,
        timeout: const Duration(seconds: 5),
      );

      for (final completion in completions) {
        await _handleCompletion(completion);
      }
    }

    if (isReleased) {
      return WriteResult(writeId, 0, const OSError('Service released'));
    }

    final result = _trackers.remove(writeId);
    if (result == null) {
      return WriteResult(writeId, 0, const OSError('Write tracker not found'));
    }

    return WriteResult(writeId, result.written);
  }

  /// Flush all pending writes.
  Future<void> _flush(int flushId) async {
    if (!_initialized) {
      throw StateError('Not initialized');
    }

    if (isReleased) {
      throw StateError('Service has been released');
    }

    // Process all queued writes
    while (_writeQueue.isNotEmpty && !isReleased) {
      await _processQueue();
    }

    // Wait for all in-flight operations to complete
    while (_context!.inFlightCount > 0 && !isReleased) {
      final completions = _context!.getCompletions(
        minEvents: 1,
        timeout: const Duration(seconds: 5),
      );

      for (final completion in completions) {
        await _handleCompletion(completion);
      }
    }
  }

  Future<void> _processQueue() async {
    while (_writeQueue.isNotEmpty &&
        _context!.canSubmit &&
        _bufferPool!.available > 0 &&
        !isReleased) {
      final queued = _writeQueue.removeAt(0);
      _submitWrite(queued);
    }
  }

  void _submitWrite(_QueuedWrite queued) {
    final buffer = _bufferPool!.acquire()!;

    // Copy data
    buffer.asTypedList(queued.data.length).setAll(0, queued.data);

    final opId = OperationId(_nextOpId);
    _nextOpId++;

    final iocbPtr = calloc<iocb>()
      ..ref.aio_fildes = _fd
      ..ref.aio_lio_opcode =
          1 // IOCB_CMD_PWRITE
      ..ref.aio_reqprio = 0
      ..ref.aio_rw_flags = 0
      ..ref.data = ffi.Pointer<ffi.Void>.fromAddress(opId.value)
      ..ref.u.c.buf = buffer.cast<ffi.Void>()
      ..ref.u.c.nbytes = queued.data.length
      ..ref.u.c.offset = queued.offset;

    final op = TrackedOperation(
      id: opId,
      type: OperationType.write,
      buffer: buffer,
      size: queued.data.length,
      offset: queued.offset,
      iocb: iocbPtr,
      userData: queued.writeId,
    );

    _context!.submit([op]);
  }

  Future<void> _handleCompletion(CompletedOperation completion) async {
    final op = completion.operation;
    final writeId = op.userData! as int;
    final tracker = _trackers[writeId];

    try {
      if (!completion.isSuccess) {
        _trackers.remove(writeId);
        return;
      }

      if (completion.bytesTransferred != op.size) {
        _trackers.remove(writeId);
        return;
      }

      if (tracker != null) {
        tracker.written += completion.bytesTransferred;
        tracker.completed++;
      }
    } finally {
      _bufferPool!.releaseBuffer(op.buffer);
      op.free();
    }

    // Continue processing queue
    await _processQueue();
  }

  /// Clean up resources.
  @override
  void release() {
    if (!isReleased) {
      // Clear pending operations
      _writeQueue.clear();
      _trackers.clear();

      // Dispose AIO resources
      _context?.dispose();
      _bufferPool?.release();

      // Null out references
      _context = null;
      _bufferPool = null;

      super.release();
    }
  }
}

final class _QueuedWrite {
  const _QueuedWrite(this.writeId, this.data, this.offset);

  final int writeId;
  final Uint8List data;
  final int offset;
}

final class _WriteTracker {
  _WriteTracker(this.writeId, this.totalBytes, this.totalChunks);

  final int writeId;
  final int totalBytes;
  final int totalChunks;
  int written = 0;
  int completed = 0;
}
