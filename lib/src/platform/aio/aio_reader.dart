import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'aio.dart';
import 'aio_reader_isolate.dart';

/// High-level async reader using Linux AIO
///
/// Provides a stream-based interface for reading from file descriptors
/// using efficient async I/O in a dedicated isolate.
class AioReader {
  /// Creates an AIO reader
  ///
  /// [fd] - File descriptor to read from
  /// [bufferSize] - Size of each read buffer (typically 4KB-1MB)
  /// [numBuffers] - Number of concurrent read operations (2-8 recommended)
  AioReader({
    required this.fd,
    this.bufferSize = 64 * 1024,
    this.numBuffers = 4,
  }) : assert(fd >= 0, 'File descriptor must be non-negative'),
       assert(bufferSize > 0, 'Buffer size must be positive'),
       assert(numBuffers > 0, 'Number of buffers must be positive');

  /// File descriptor to read from
  final int fd;

  /// Size of each read buffer in bytes
  final int bufferSize;

  /// Number of concurrent read operations
  final int numBuffers;

  bool _disposed = false;
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  StreamController<Uint8List>? _controller;

  /// Whether this reader has been disposed
  bool get isDisposed => _disposed;

  /// Creates a stream of data chunks read from the file descriptor
  ///
  /// The stream can only be listened to once. If you need multiple listeners,
  /// use `.asBroadcastStream()`.
  ///
  /// [handleError] - Optional error handler that determines how to handle
  /// read errors. By default, EAGAIN is ignored and other errors throw.
  ///
  /// Returns a stream that emits [Uint8List] chunks until EOF or error.
  Stream<Uint8List> stream({
    AioErrorAction Function(int errorCode)? handleError,
  }) {
    if (_disposed) {
      throw StateError('Reader has been disposed');
    }
    if (_controller != null) {
      throw StateError('Stream already created. Only one stream per reader.');
    }

    _controller = StreamController<Uint8List>(
      onListen: () => _startIsolate(handleError),
      onCancel: dispose,
    );

    return _controller!.stream;
  }

  Future<void> _startIsolate(
    AioErrorAction Function(int errorCode)? handleError,
  ) async {
    _receivePort = ReceivePort();

    // Spawn the reader isolate
    _isolate = await Isolate.spawn(
      readerIsolateEntryPoint,
      ReaderConfig(
        fd: fd,
        bufferSize: bufferSize,
        numBuffers: numBuffers,
        sendPort: _receivePort!.sendPort,
        handleError: handleError,
      ),
    );

    // Handle messages from isolate
    _receivePort!.listen((message) {
      switch (message) {
        case ReaderReady(:final sendPort):
          _sendPort = sendPort;

        case ReadData(:final data):
          if (!_disposed) {
            _controller?.add(data);
          }

        case ReadError(:final error, :final stackTrace):
          if (!_disposed) {
            _controller?.addError(error, stackTrace);
          }

        case ReadDone():
          if (!_disposed) {
            _controller?.close();
            dispose();
          }
      }
    });
  }

  /// Stops reading and releases all resources
  ///
  /// After calling this, the reader cannot be used again.
  /// This is automatically called when the stream completes or is cancelled.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    // Signal isolate to stop
    _sendPort?.send(StopReading());

    // Kill isolate
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;

    // Close ports
    _receivePort?.close();
    _receivePort = null;

    // Close stream
    _controller?.close();
    _controller = null;
  }
}
