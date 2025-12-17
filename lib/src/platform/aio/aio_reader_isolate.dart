import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'aio.ffi.dart';
import 'aio_context.dart';

// Messages
sealed class ReaderMessage {}

final class ReaderInit extends ReaderMessage {
  ReaderInit(this.fd, this.bufferSize, this.windowSize);

  final int fd;
  final int bufferSize;
  final int windowSize;
}

final class ReaderDemand extends ReaderMessage {
  ReaderDemand(this.count);

  final int count;
}

final class ReaderStop extends ReaderMessage {}

sealed class ReaderResponse {}

final class ReaderReady extends ReaderResponse {
  ReaderReady(this.sendPort);

  final SendPort sendPort;
}

final class ReaderData extends ReaderResponse {
  ReaderData(this.data, this.sequenceId);

  final Uint8List data;
  final int sequenceId;
}

final class ReaderEof extends ReaderResponse {}

final class ReaderError extends ReaderResponse {
  ReaderError(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

void readerIsolateEntry(SendPort mainPort) {
  final receivePort = ReceivePort();
  mainPort.send(ReaderReady(receivePort.sendPort));

  _ReaderIsolate(mainPort).run(receivePort);
}

final class _ReaderIsolate {
  _ReaderIsolate(this.mainPort);

  final SendPort mainPort;

  AioContext? _context;
  BufferPool? _bufferPool;

  int _fd = -1;
  int _bufferSize = 0;
  int _fileOffset = 0;
  int _nextOpId = 0;
  int _nextSeqId = 0;

  int _pendingDemand = 0;
  bool _stopped = false;
  bool _eofReached = false;
  Timer? _pollTimer;

  void run(ReceivePort receivePort) {
    receivePort.listen((message) {
      try {
        _handleMessage(message);
      } catch (e, st) {
        mainPort.send(ReaderError(e, st));
        _cleanup();
      }
    });
  }

  void _handleMessage(dynamic message) {
    switch (message) {
      case ReaderInit(:final fd, :final bufferSize, :final windowSize):
        _initialize(fd, bufferSize, windowSize);

      case ReaderDemand(:final count):
        _handleDemand(count);

      case ReaderStop():
        _stopped = true;
        _cleanup();
    }
  }

  void _initialize(int fd, int bufferSize, int windowSize) {
    _fd = fd;
    _bufferSize = bufferSize;

    _context = AioContext(maxConcurrent: windowSize);
    _bufferPool = BufferPool(bufferSize, windowSize);

    // Start completion polling
    _pollCompletions();
  }

  void _handleDemand(int count) {
    _pendingDemand += count;
    _submitReads();
  }

  void _submitReads() {
    if (_stopped || _eofReached) return;

    final operations = <TrackedOperation>[];

    // Submit up to min(demand, available_buffers, window_space)
    while (_pendingDemand > 0 &&
        _context!.canSubmit &&
        _bufferPool!.available > 0) {
      final buffer = _bufferPool!.acquire();
      if (buffer == null) break;

      final opId = OperationId(_nextOpId);
      final seqId = _nextSeqId++;
      _nextOpId++;

      final iocbPtr = calloc<iocb>()
        ..ref.aio_fildes = _fd
        ..ref.aio_lio_opcode =
            0 // IOCB_CMD_PREAD
        ..ref.aio_reqprio = 0
        ..ref.aio_rw_flags = 0
        ..ref.data = ffi.Pointer<ffi.Void>.fromAddress(opId.value)
        ..ref.u.c.buf = buffer.cast<ffi.Void>()
        ..ref.u.c.nbytes = _bufferSize
        ..ref.u.c.offset = _fileOffset;

      operations.add(
        TrackedOperation(
          id: opId,
          type: OperationType.read,
          buffer: buffer,
          size: _bufferSize,
          offset: _fileOffset,
          iocb: iocbPtr,
          userData: seqId,
        ),
      );

      _fileOffset += _bufferSize;
      _pendingDemand--;
    }

    if (operations.isNotEmpty) {
      _context!.submit(operations);
    }
  }

  void _pollCompletions() {
    _pollTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      if (_stopped) {
        _pollTimer?.cancel();
        return;
      }

      try {
        _context!
            .getCompletions(timeout: const Duration(milliseconds: 10))
            .forEach(_handleCompletion);
      } catch (e, st) {
        mainPort.send(ReaderError(e, st));
        _stopped = true;
        _cleanup();
      }
    });
  }

  void _handleCompletion(CompletedOperation completion) {
    final op = completion.operation;

    try {
      if (!completion.isSuccess) {
        throw completion.error!;
      }

      if (completion.isEof) {
        _eofReached = true;
        mainPort.send(ReaderEof());
        _cleanup();
        return;
      }

      // Copy data and send
      final data = Uint8List.fromList(
        op.buffer.asTypedList(completion.bytesTransferred),
      );
      mainPort.send(ReaderData(data, op.userData! as int));
    } catch (e, st) {
      mainPort.send(ReaderError(e, st));
      _stopped = true;
      _cleanup();
    } finally {
      _bufferPool!.release(op.buffer);
      op.free();
    }
  }

  void _cleanup() {
    _pollTimer?.cancel();
    _context?.dispose();
    _bufferPool?.dispose();
  }
}
