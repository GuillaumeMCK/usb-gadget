import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'aio.dart';

/// Entry point for writer isolate
///
/// This isolate performs async writes using Linux AIO with automatic
/// batching and flow control for optimal throughput.
void writerIsolateEntryPoint(WriterConfig config) =>
    _WriterIsolateController(config).run();

/// Internal controller for writer isolate logic
class _WriterIsolateController {
  _WriterIsolateController(this.config);

  final WriterConfig config;
  final ReceivePort receivePort = ReceivePort();

  AioContext? _ctx;
  final Map<int, _WriteRequest> _activeWrites = {};
  final List<_PendingWrite> _pendingWrites = [];
  int _nextInternalId = 0;
  int _currentOffset = 0;

  void run() {
    // Send our SendPort back to main isolate
    config.sendPort.send(WriterReady(receivePort.sendPort));

    try {
      // Initialize AIO context
      _ctx = AioContext.create(config.numBuffers * 2);

      // Process messages
      receivePort.listen(_handleMessage);
    } catch (e, st) {
      config.sendPort.send(WriterError(e, st));
      _cleanup();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      switch (message) {
        case WriteData():
          _handleWriteData(message);
        case WriteFlush():
          _handleFlush(message);
        case StopWriting():
          _cleanup();
      }
    } catch (e, st) {
      if (message is WriteData) {
        config.sendPort.send(WriteResult(message.id, 0, e));
      } else {
        config.sendPort.send(WriterError(e, st));
      }
    }
  }

  void _handleWriteData(WriteData message) {
    // Split data into chunks if needed
    final chunks = _splitIntoChunks(message.data);
    var totalBytes = 0;

    for (final chunk in chunks) {
      _pendingWrites.add(
        _PendingWrite(
          data: chunk,
          offset: _currentOffset + totalBytes,
          requestId: message.id,
        ),
      );
      totalBytes += chunk.length;
    }

    _currentOffset += totalBytes;

    // Submit pending writes
    _processPendingWrites();

    // Send success response
    config.sendPort.send(WriteResult(message.id, totalBytes, null));
  }

  void _handleFlush(WriteFlush message) {
    // Submit all pending writes
    while (_pendingWrites.isNotEmpty &&
        _activeWrites.length < config.numBuffers) {
      final write = _pendingWrites.removeAt(0);
      _submitWrite(write);
    }

    // Wait for all active writes to complete
    while (_activeWrites.isNotEmpty) {
      _ctx!
          // Blocking wait for events
          .getEvents(
            maxNr: config.numBuffers,
            timeout: const Duration(milliseconds: 100),
          )
          // Process all completed events
          .forEach(_processWriteEvent);
    }

    config.sendPort.send(FlushComplete(message.id));
  }

  List<Uint8List> _splitIntoChunks(Uint8List data) {
    if (data.length <= config.bufferSize) {
      return [data];
    }

    final chunks = <Uint8List>[];
    var offset = 0;

    while (offset < data.length) {
      final chunkSize = (data.length - offset).clamp(0, config.bufferSize);
      chunks.add(
        Uint8List.view(data.buffer, data.offsetInBytes + offset, chunkSize),
      );
      offset += chunkSize;
    }

    return chunks;
  }

  void _processPendingWrites() {
    // Submit writes up to buffer limit
    while (_pendingWrites.isNotEmpty &&
        _activeWrites.length < config.numBuffers) {
      final write = _pendingWrites.removeAt(0);
      _submitWrite(write);
    }

    // Check for completions (non-blocking)
    _ctx!
        // Get completed events
        .getEvents(minNr: 0, maxNr: config.numBuffers)
        // Process all completed events
        .forEach(_processWriteEvent);
  }

  void _submitWrite(_PendingWrite pending) {
    final id = _nextInternalId++;
    final buffer = calloc<ffi.Uint8>(pending.data.length);

    try {
      // Copy data to native buffer
      buffer
          .asTypedList(pending.data.length)
          .setRange(0, pending.data.length, pending.data);

      final iocb = AioControlBlock.write(
        fd: config.fd,
        buffer: buffer.cast<ffi.Void>(),
        size: pending.data.length,
        offset: pending.offset,
        userData: id,
      );

      _ctx!.submit([iocb]);

      _activeWrites[id] = _WriteRequest(
        iocb: iocb,
        buffer: buffer,
        expectedSize: pending.data.length,
        requestId: pending.requestId,
      );
    } catch (err) {
      calloc.free(buffer);
      rethrow;
    }
  }

  void _processWriteEvent(AioEvent event) {
    final request = _activeWrites.remove(event.userData);
    if (request == null) return;

    try {
      if (!event.isSuccess) {
        throw OSError('AIO write failed', event.errorCode);
      }

      if (event.bytesTransferred != request.expectedSize) {
        throw StateError(
          'Partial write: expected ${request.expectedSize}, '
          'got ${event.bytesTransferred}',
        );
      }
    } finally {
      request.free();
    }
  }

  void _cleanup() {
    // Free all active writes
    for (final request in _activeWrites.values) {
      try {
        request.free();
      } catch (_) {}
    }
    _activeWrites.clear();

    _pendingWrites.clear();

    // Destroy context
    try {
      _ctx?.destroy();
    } catch (_) {}

    receivePort.close();
  }
}

/// Represents a write operation waiting to be submitted
class _PendingWrite {
  _PendingWrite({
    required this.data,
    required this.offset,
    required this.requestId,
  });

  final Uint8List data;
  final int offset;
  final int requestId;
}

/// Tracks an active write request
class _WriteRequest {
  _WriteRequest({
    required this.iocb,
    required this.buffer,
    required this.expectedSize,
    required this.requestId,
  });

  final AioControlBlock iocb;
  final ffi.Pointer<ffi.Uint8> buffer;
  final int expectedSize;
  final int requestId;

  void free() {
    calloc.free(buffer);
    iocb.free();
  }
}
