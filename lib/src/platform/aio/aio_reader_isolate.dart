import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../errno/errno.dart';
import 'aio.dart';

/// Entry point for reader isolate
///
/// This isolate performs async reads using Linux AIO, eliminating blocking
/// and reducing CPU usage through event-driven I/O.
void readerIsolateEntryPoint(ReaderConfig config) =>
    _ReaderIsolateController(config).run();

/// Internal controller for reader isolate logic
class _ReaderIsolateController {
  _ReaderIsolateController(this.config);

  final ReaderConfig config;
  final ReceivePort receivePort = ReceivePort();

  AioContext? _ctx;
  final Map<int, _ReadRequest> _activeRequests = {};
  int _nextRequestId = 0;
  bool _shouldStop = false;

  void run() {
    // Send our SendPort back to main isolate
    config.sendPort.send(ReaderReady(receivePort.sendPort));

    // Setup message handling
    receivePort.listen(_handleMessage);

    try {
      // Initialize AIO context
      _ctx = AioContext.create(config.numBuffers * 2);

      // Submit initial batch of reads
      for (var i = 0; i < config.numBuffers; i++) {
        _submitRead();
      }

      // Main event loop
      _eventLoop();

      // Notify completion
      config.sendPort.send(ReadDone());
    } catch (e, st) {
      config.sendPort.send(ReadError(e, st));
    } finally {
      _cleanup();
    }
  }

  void _handleMessage(dynamic message) {
    if (message is StopReading) {
      _shouldStop = true;
    }
  }

  void _eventLoop() {
    while (!_shouldStop && _activeRequests.isNotEmpty) {
      try {
        // Blocking wait for events with timeout to check stop flag periodically
        _ctx!
            // Get completed events
            .getEvents(
              maxNr: config.numBuffers,
              timeout: const Duration(milliseconds: 100),
            )
            // Process all completed events
            .forEach(_processEvent);
      } catch (e, st) {
        config.sendPort.send(ReadError(e, st));
        _shouldStop = true;
      }
    }
  }

  void _processEvent(AioEvent event) {
    final request = _activeRequests.remove(event.userData);
    if (request == null) return;

    try {
      final data = _handleReadResult(event, request);

      // Send data if non-empty
      if (data != null && data.isNotEmpty) {
        config.sendPort.send(ReadData(data));
      }

      // Submit next read if not stopping
      if (!_shouldStop && data != null && data.isNotEmpty) {
        _submitRead();
      } else if (data != null && data.isEmpty) {
        // EOF reached
        _shouldStop = true;
      }
    } finally {
      request.free();
    }
  }

  Uint8List? _handleReadResult(AioEvent event, _ReadRequest request) {
    if (event.isSuccess) {
      if (event.bytesTransferred == 0) {
        return Uint8List(0); // EOF
      }

      // Copy data from buffer
      return Uint8List(event.bytesTransferred)..setRange(
        0,
        event.bytesTransferred,
        request.buffer.asTypedList(event.bytesTransferred),
      );
    }

    // Handle error
    final errorCode = event.errorCode;
    final action =
        config.handleError?.call(errorCode) ??
        (errorCode == Errno.eagain
            ? AioErrorAction.ignore
            : AioErrorAction.error);

    return switch (action) {
      AioErrorAction.ignore => null,
      AioErrorAction.empty => Uint8List(0),
      AioErrorAction.error => throw Errno.toOSError(errorCode),
    };
  }

  void _submitRead() {
    final id = _nextRequestId++;
    final buffer = calloc<ffi.Uint8>(config.bufferSize);

    try {
      final iocb = AioControlBlock.read(
        fd: config.fd,
        buffer: buffer.cast<ffi.Void>(),
        size: config.bufferSize,
        userData: id,
      );

      _ctx!.submit([iocb]);
      _activeRequests[id] = _ReadRequest(iocb, buffer);
    } catch (err) {
      calloc.free(buffer);
      rethrow;
    }
  }

  void _cleanup() {
    // Free all active requests
    for (final request in _activeRequests.values) {
      try {
        request.free();
      } catch (_) {
        // Ignore cleanup errors
      }
    }
    _activeRequests.clear();

    // Destroy context
    try {
      _ctx?.destroy();
    } catch (_) {
      // Ignore cleanup errors
    }

    receivePort.close();
  }
}

/// Tracks an active read request
class _ReadRequest {
  _ReadRequest(this.iocb, this.buffer);

  final AioControlBlock iocb;
  final ffi.Pointer<ffi.Uint8> buffer;

  void free() {
    calloc.free(buffer);
    iocb.free();
  }
}
