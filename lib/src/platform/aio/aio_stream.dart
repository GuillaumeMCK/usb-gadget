import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:squadron/squadron.dart';

import 'aio_reader_service.dart';
import 'aio_writer_service.dart';

/// Configuration for AIO operations.
@immutable
final class AioConfig {
  /// Creates an [AioConfig].
  ///
  /// [bufferSize] defaults to 64KB.
  /// [windowSize] defaults to 4 concurrent operations.
  const AioConfig({this.bufferSize = 64 * 1024, this.windowSize = 4})
    : assert(bufferSize > 0 && windowSize > 0);

  /// The size of each I/O buffer in bytes.
  final int bufferSize;

  /// The number of concurrent I/O operations (window size).
  final int windowSize;
}

/// Worker class for AIO reading operations.
///
/// This worker runs an [AioReaderService] in a separate isolate.
final class AioReaderWorker extends Worker {
  /// Creates an [AioReaderWorker].
  AioReaderWorker() : super(_entryPoint);

  static void _entryPoint(WorkerRequest command) =>
      run((_) => AioReaderService(), command);

  @override
  List<Object?>? getStartArgs() => null;

  /// Initializes the reader worker with the given [fd], [bufferSize], and [windowSize].
  Future<void> initialize(int fd, int bufferSize, int windowSize) =>
      send(AioReaderService.cmdInitialize, args: [fd, bufferSize, windowSize]);

  /// Starts a stream of data from the reader worker.
  ///
  /// The [demand] specifies how many buffers to pre-fetch.
  Stream<Uint8List> readStream(int demand) => stream(
    AioReaderService.cmdReadStream,
    args: [demand],
  ).map((data) => data as Uint8List);
}

/// Worker class for AIO writing operations.
///
/// This worker runs an [AioWriterService] in a separate isolate.
final class AioWriterWorker extends Worker {
  /// Creates an [AioWriterWorker].
  AioWriterWorker() : super(_entryPoint);

  static void _entryPoint(WorkerRequest command) =>
      run((_) => AioWriterService(), command);

  @override
  List<Object?>? getStartArgs() => null;

  /// Initializes the writer worker with the given [fd], [bufferSize], and [maxInFlight].
  Future<void> initialize(int fd, int bufferSize, int maxInFlight) =>
      send(AioWriterService.cmdInitialize, args: [fd, bufferSize, maxInFlight]);

  /// Submits a write operation for [data] with the given [writeId].
  Future<WriteResult> write(int writeId, Uint8List data) async {
    final result = await send(AioWriterService.cmdWrite, args: [writeId, data]);
    return result as WriteResult;
  }

  /// Flushes all pending write operations.
  Future<void> flush(int flushId) =>
      send(AioWriterService.cmdFlush, args: [flushId]);
}

/// High-level reader for asynchronous I/O operations.
///
/// Uses a worker isolate and Linux AIO for high-performance reading from a file
/// descriptor.
final class AioReader {
  /// Creates an [AioReader] for the given [fd].
  AioReader(this.fd, [this.config = const AioConfig()]) : assert(fd >= 0);

  /// The file descriptor to read from.
  final int fd;

  /// The configuration for AIO operations.
  final AioConfig config;

  AioReaderWorker? _worker;
  StreamController<Uint8List>? _controller;
  StreamSubscription<Uint8List>? _subscription;
  bool _started = false;
  bool _disposed = false;

  /// The stream of data read from the file descriptor.
  ///
  /// Throws [StateError] if the stream is accessed more than once or if the
  /// reader is disposed.
  Stream<Uint8List> get stream {
    if (_started) throw StateError('Stream already created');
    if (_disposed) throw StateError('Reader has been disposed');
    _started = true;

    _controller = StreamController<Uint8List>(
      onListen: _start,
      onPause: _onPause,
      onResume: _onResume,
      onCancel: _onCancel,
    );

    return _controller!.stream;
  }

  Future<void> _start() async {
    if (_disposed) return;

    try {
      _worker = AioReaderWorker();
      await _worker!.start();
      await _worker!.initialize(fd, config.bufferSize, config.windowSize);

      // Subscribe to the worker's stream
      _subscription = _worker!
          .readStream(config.windowSize)
          .listen(
            (data) {
              if (!_disposed && _controller != null && !_controller!.isClosed) {
                _controller!.add(data);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!_disposed && _controller != null && !_controller!.isClosed) {
                _controller!.addError(error, stackTrace);
              }
            },
            onDone: () {
              if (!_disposed && _controller != null && !_controller!.isClosed) {
                _controller!.close();
              }
              unawaited(dispose());
            },
            cancelOnError: false,
          );
    } catch (error, stackTrace) {
      if (!_disposed && _controller != null && !_controller!.isClosed) {
        _controller!.addError(error, stackTrace);
        unawaited(_controller!.close());
      }
      unawaited(dispose());
    }
  }

  void _onPause() {
    _subscription?.pause();
  }

  void _onResume() {
    _subscription?.resume();
  }

  Future<void> _onCancel() async {
    await dispose();
  }

  /// Disposes the [AioReader] and stops the worker.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _subscription?.cancel();
    _subscription = null;

    _worker?.stop();
    _worker = null;

    if (_controller != null && !_controller!.isClosed) {
      await _controller!.close();
    }
    _controller = null;
  }
}

/// High-level writer for asynchronous I/O operations.
///
/// Uses a worker isolate and Linux AIO for high-performance writing to a file
/// descriptor.
final class AioWriter {
  /// Creates an [AioWriter] for the given [fd].
  AioWriter(this.fd, [this.config = const AioConfig()]) : assert(fd >= 0);

  /// The file descriptor to write to.
  final int fd;

  /// The configuration for AIO operations.
  final AioConfig config;

  AioWriterWorker? _worker;
  bool _initialized = false;
  bool _disposed = false;
  int _nextId = 0;

  /// Writes [data] to the file descriptor.
  ///
  /// Returns the number of bytes successfully written.
  /// Throws [StateError] if the writer is disposed.
  Future<int> write(Uint8List data) async {
    if (_disposed) {
      throw StateError('Writer has been disposed');
    }

    await _ensureInitialized();

    final id = _nextId++;
    final result = await _worker!.write(id, data);

    if (result.error != null) {
      Error.throwWithStackTrace(result.error!, StackTrace.current);
    }

    return result.bytesWritten;
  }

  /// Flushes all pending write operations to ensure they are written to disk.
  Future<void> flush() async {
    if (_disposed) {
      throw StateError('Writer has been disposed');
    }

    await _ensureInitialized();

    final id = _nextId++;
    await _worker!.flush(id);
  }

  Future<void> _ensureInitialized() async {
    if (_disposed) {
      throw StateError('Writer has been disposed');
    }

    if (_initialized) return;
    _initialized = true;

    _worker = AioWriterWorker();
    await _worker!.start();
    await _worker!.initialize(fd, config.bufferSize, config.windowSize);
  }

  /// Disposes the [AioWriter] and stops the worker.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _worker?.stop();
    _worker = null;
  }
}
