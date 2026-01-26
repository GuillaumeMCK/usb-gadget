import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:squadron/squadron.dart';
import 'package:using/using.dart';

import 'aio.ffi.dart';
import 'aio_context.dart';

/// Configuration for AIO reader worker.
final class AioReaderConfig {
  /// Creates an [AioReaderConfig].
  const AioReaderConfig({
    required this.fd,
    required this.bufferSize,
    required this.windowSize,
  });

  /// The file descriptor to read from.
  final int fd;

  /// The size of each read buffer in bytes.
  final int bufferSize;

  /// The number of concurrent read operations (window size).
  final int windowSize;
}

/// Service for reading data using Linux AIO in a worker thread.
base class AioReaderService with Releasable implements WorkerService {
  AioReaderService();

  AioContext? _context;
  BufferPool? _bufferPool;

  int _fd = -1;
  int _bufferSize = 0;
  int _fileOffset = 0;
  int _nextOpId = 0;
  int _nextSeqId = 0;

  bool _initialized = false;
  bool _eofReached = false;

  /// Command IDs
  static const cmdInitialize = 1;
  static const cmdReadStream = 2;

  @override
  late final operations = OperationsMap({
    /// Command to initialize the service.
    cmdInitialize: (WorkerRequest r) =>
        _initialize(r.args[0] as int, r.args[1] as int, r.args[2] as int),

    /// Command to start streaming data.
    cmdReadStream: (WorkerRequest r) => _readStream(r.args[0] as int),
  });

  /// Initialize the AIO context and buffer pool.
  Future<void> _initialize(int fd, int bufferSize, int windowSize) async {
    if (_initialized) {
      throw StateError('Already initialized');
    }

    _fd = fd;
    _bufferSize = bufferSize;
    _context = AioContext(maxConcurrent: windowSize);
    _bufferPool = BufferPool(bufferSize, windowSize);
    _initialized = true;
  }

  /// Stream data from the file descriptor.
  Stream<Uint8List> _readStream(int demand) async* {
    if (!_initialized) {
      throw StateError('Not initialized');
    }

    if (isReleased) {
      throw StateError('Service has been released');
    }

    if (_eofReached) {
      return;
    }

    // Submit initial reads based on demand
    final operations = <TrackedOperation>[];
    for (var i = 0; i < demand && _bufferPool!.available > 0; i++) {
      if (isReleased) return;
      final op = _submitRead();
      if (op != null) {
        operations.add(op);
      }
    }

    if (operations.isNotEmpty) {
      _context!.submit(operations);
    }

    // Poll for completions and yield data
    while (!_eofReached && !isReleased) {
      final completions = _context!.getCompletions(
        timeout: const Duration(milliseconds: 100),
      );

      for (final completion in completions) {
        if (isReleased) return;

        final op = completion.operation;

        try {
          if (!completion.isSuccess) {
            throw completion.error!;
          }

          if (completion.isEof) {
            _eofReached = true;
            return;
          }

          // Copy data and yield
          final data = Uint8List.fromList(
            op.buffer.asTypedList(completion.bytesTransferred),
          );
          yield data;

          // Submit another read to maintain the window
          if (!isReleased && !_eofReached) {
            final nextOp = _submitRead();
            if (nextOp != null) {
              _context!.submit([nextOp]);
            }
          }
        } finally {
          _bufferPool!.releaseBuffer(op.buffer);
          op.free();
        }
      }

      // Small delay to avoid busy-waiting
      if (completions.isEmpty && !isReleased) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  TrackedOperation? _submitRead() {
    if (_eofReached || !_context!.canSubmit) {
      return null;
    }

    final buffer = _bufferPool!.acquire();
    if (buffer == null) {
      return null;
    }

    final opId = OperationId(_nextOpId);
    final seqId = _nextSeqId++;
    _nextOpId++;

    final iocbPtr = calloc<iocb>()
      ..ref.aio_fildes = _fd
      // IOCB_CMD_PREAD
      ..ref.aio_lio_opcode = 0
      ..ref.aio_reqprio = 0
      ..ref.aio_rw_flags = 0
      ..ref.data = ffi.Pointer<ffi.Void>.fromAddress(opId.value)
      ..ref.u.c.buf = buffer.cast<ffi.Void>()
      ..ref.u.c.nbytes = _bufferSize
      ..ref.u.c.offset = _fileOffset;

    _fileOffset += _bufferSize;

    return TrackedOperation(
      id: opId,
      type: OperationType.read,
      buffer: buffer,
      size: _bufferSize,
      offset: _fileOffset - _bufferSize,
      iocb: iocbPtr,
      userData: seqId,
    );
  }

  /// Clean up resources.
  @override
  void release() {
    if (!isReleased) {
      _eofReached = true;
      _context?.dispose();
      _bufferPool?.release();
      _context = null;
      _bufferPool = null;
      super.release();
    }
  }
}
