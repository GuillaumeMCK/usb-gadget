import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'aio.ffi.dart';
import 'aio_context.dart';

sealed class WriterMessage {}

final class WriterInit extends WriterMessage {
  WriterInit(this.fd, this.bufferSize, this.maxInFlight);

  final int fd;
  final int bufferSize;
  final int maxInFlight;
}

final class WriterWrite extends WriterMessage {
  WriterWrite(this.id, this.data);

  final int id;
  final Uint8List data;
}

final class WriterFlush extends WriterMessage {
  WriterFlush(this.id);

  final int id;
}

final class WriterStop extends WriterMessage {}

sealed class WriterResponse {}

final class WriterReady extends WriterResponse {
  WriterReady(this.sendPort);

  final SendPort sendPort;
}

final class WriterComplete extends WriterResponse {
  WriterComplete(this.id, this.bytesWritten, [this.error]);

  final int id;
  final int bytesWritten;
  final Object? error;
}

final class WriterFlushed extends WriterResponse {
  WriterFlushed(this.id);

  final int id;
}

final class WriterError extends WriterResponse {
  WriterError(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

void writerIsolateEntry(SendPort mainPort) {
  final receivePort = ReceivePort();
  mainPort.send(WriterReady(receivePort.sendPort));

  _WriterIsolate(mainPort).run(receivePort);
}

final class _WriterIsolate {
  _WriterIsolate(this.mainPort);

  final SendPort mainPort;

  AioContext? _context;
  BufferPool? _bufferPool;

  int _fd = -1;
  int _bufferSize = 0;
  int _maxInFlight = 0;
  int _fileOffset = 0;
  int _nextOpId = 0;

  final List<_QueuedWrite> _writeQueue = [];
  final Map<int, _WriteTracker> _trackers = {};

  bool _stopped = false;
  Timer? _pollTimer;

  void run(ReceivePort receivePort) {
    receivePort.listen((message) {
      try {
        _handleMessage(message);
      } catch (e, st) {
        mainPort.send(WriterError(e, st));
        _cleanup();
      }
    });
  }

  void _handleMessage(dynamic message) {
    switch (message) {
      case WriterInit(:final fd, :final bufferSize, :final maxInFlight):
        _initialize(fd, bufferSize, maxInFlight);

      case WriterWrite(:final id, :final data):
        _enqueueWrite(id, data);

      case WriterFlush(:final id):
        _flush(id);

      case WriterStop():
        _stopped = true;
        _cleanup();
    }
  }

  void _initialize(int fd, int bufferSize, int maxInFlight) {
    _fd = fd;
    _bufferSize = bufferSize;
    _maxInFlight = maxInFlight;

    _context = AioContext(maxConcurrent: maxInFlight);
    _bufferPool = BufferPool(bufferSize, maxInFlight);

    _pollCompletions();
  }

  void _enqueueWrite(int writeId, Uint8List data) {
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
      _writeQueue.add(_QueuedWrite(writeId, chunk, _fileOffset));
      _fileOffset += chunk.length;
    }

    _processQueue();
  }

  void _processQueue() {
    while (_writeQueue.isNotEmpty &&
        _context!.canSubmit &&
        _bufferPool!.available > 0) {
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

  void _flush(int flushId) {
    // Process all queued
    while (_writeQueue.isNotEmpty) {
      _processQueue();
    }

    // Wait for all in-flight to complete
    while (_context!.inFlightCount > 0) {
      _context!
          .getCompletions(minEvents: 1, timeout: const Duration(seconds: 5))
          .forEach(_handleCompletion);
    }

    mainPort.send(WriterFlushed(flushId));
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

        _processQueue();
      } catch (e, st) {
        mainPort.send(WriterError(e, st));
        _stopped = true;
        _cleanup();
      }
    });
  }

  void _handleCompletion(CompletedOperation completion) {
    final op = completion.operation;
    final writeId = op.userData! as int;
    final tracker = _trackers[writeId];

    try {
      if (!completion.isSuccess) {
        mainPort.send(
          WriterComplete(writeId, tracker?.written ?? 0, completion.error),
        );
        _trackers.remove(writeId);
        return;
      }

      if (completion.bytesTransferred != op.size) {
        mainPort.send(
          WriterComplete(
            writeId,
            tracker?.written ?? 0,
            OSError(
              'Incomplete write: ${completion.bytesTransferred}/${op.size}',
            ),
          ),
        );
        _trackers.remove(writeId);
        return;
      }

      if (tracker != null) {
        tracker.written += completion.bytesTransferred;
        tracker.completed++;

        if (tracker.completed == tracker.totalChunks) {
          mainPort.send(WriterComplete(writeId, tracker.written));
          _trackers.remove(writeId);
        }
      }
    } finally {
      _bufferPool!.release(op.buffer);
      op.free();
    }
  }

  void _cleanup() {
    _pollTimer?.cancel();

    for (final tracker in _trackers.values) {
      mainPort.send(
        WriterComplete(
          tracker.writeId,
          tracker.written,
          const OSError('Writer stopped'),
        ),
      );
    }

    _context?.dispose();
    _bufferPool?.dispose();
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
