import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'aio_messages.dart';
import 'aio_writer_isolate.dart';

/// High-level async writer using Linux AIO
///
/// Provides an efficient interface for writing to file descriptors using
/// async I/O with automatic batching and flow control.
///
/// Example:
/// ```dart
/// final writer = AioWriter(
///   fd: file.fd,
///   bufferSize: 64 * 1024, // 64KB
///   numBuffers: 4,
/// );
///
/// await writer.write(data1);
/// await writer.write(data2);
/// await writer.flush();
/// writer.dispose();
/// ```
class AioWriter {
  /// Creates an AIO writer
  ///
  /// [fd] - File descriptor to write to
  /// [bufferSize] - Maximum size of each write operation (typically 4KB-1MB)
  /// [numBuffers] - Number of concurrent write operations (2-8 recommended)
  /// [autoFlushThreshold] - Automatically flush when this many operations
  ///   are pending (defaults to 80% of numBuffers)
  AioWriter({
    required this.fd,
    this.bufferSize = 64 * 1024,
    this.numBuffers = 4,
    int? autoFlushThreshold,
  }) : assert(fd >= 0, 'File descriptor must be non-negative'),
       assert(bufferSize > 0, 'Buffer size must be positive'),
       assert(numBuffers > 0, 'Number of buffers must be positive'),
       _autoFlushThreshold = autoFlushThreshold ?? (numBuffers * 0.8).floor();

  /// File descriptor to write to
  final int fd;

  /// Maximum size of each write operation in bytes
  final int bufferSize;

  /// Number of concurrent write operations
  final int numBuffers;

  /// Threshold for automatic flushing
  final int _autoFlushThreshold;

  bool _disposed = false;
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  final Completer<void> _readyCompleter = Completer<void>();

  int _nextRequestId = 0;
  final Map<int, Completer<int>> _pendingWrites = {};
  final Map<int, Completer<void>> _pendingFlushes = {};

  /// Whether this writer has been disposed
  bool get isDisposed => _disposed;

  /// As pending write operations
  bool get hasPendingWrites => _pendingWrites.isNotEmpty;

  /// Writes data to the file descriptor
  ///
  /// Large data will be automatically split into chunks.
  /// Returns the number of bytes written.
  ///
  /// Throws [StateError] if the writer has been disposed.
  Future<int> write(Uint8List data) async {
    if (_disposed) {
      throw StateError('Writer has been disposed');
    }
    if (data.isEmpty) {
      return 0;
    }

    // Ensure isolate is started
    if (!_readyCompleter.isCompleted) {
      await _startIsolate();
    }

    final id = _nextRequestId++;
    final completer = Completer<int>();
    _pendingWrites[id] = completer;

    _sendPort!.send(WriteData(id, data));
    return completer.future;
  }

  /// Flushes all pending writes
  ///
  /// Ensures all data has been written to the file descriptor before returning.
  ///
  /// Throws [StateError] if the writer has been disposed.
  Future<void> flush() async {
    if (_disposed) {
      throw StateError('Writer has been disposed');
    }
    if (!_readyCompleter.isCompleted) {
      return; // Nothing to flush
    }

    final id = _nextRequestId++;
    final completer = Completer<void>();
    _pendingFlushes[id] = completer;

    _sendPort!.send(WriteFlush(id));
    return completer.future;
  }

  Future<void> _startIsolate() async {
    if (_readyCompleter.isCompleted) return;

    _receivePort = ReceivePort();

    // Spawn the writer isolate
    _isolate = await Isolate.spawn(
      writerIsolateEntryPoint,
      WriterConfig(
        fd: fd,
        bufferSize: bufferSize,
        numBuffers: numBuffers,
        autoFlushThreshold: _autoFlushThreshold,
        sendPort: _receivePort!.sendPort,
      ),
    );

    // Handle messages from isolate
    _receivePort!.listen((message) {
      switch (message) {
        case WriterReady(:final sendPort):
          _sendPort = sendPort;
          _readyCompleter.complete();

        case WriteResult(:final id, :final bytesWritten, :final error):
          final completer = _pendingWrites.remove(id);
          if (completer != null) {
            if (error != null) {
              completer.completeError(error);
            } else {
              completer.complete(bytesWritten);
            }
          }

        case FlushComplete(:final id):
          _pendingFlushes.remove(id)?.complete();

        case WriterError(:final error, :final stackTrace):
          // Fatal error - fail all pending operations
          _failAllPending(error);
          dispose();
      }
    });

    await _readyCompleter.future;
  }

  void _failAllPending(Object error) {
    for (final completer in _pendingWrites.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pendingWrites.clear();

    for (final completer in _pendingFlushes.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pendingFlushes.clear();
  }

  /// Releases all resources
  ///
  /// After calling this, the writer cannot be used again.
  /// Outstanding operations will be completed with errors.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    // Signal isolate to stop
    _sendPort?.send(StopWriting());

    // Kill isolate
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;

    // Close ports
    _receivePort?.close();
    _receivePort = null;

    // Fail all pending operations
    _failAllPending(Exception('Writer disposed'));
  }
}
