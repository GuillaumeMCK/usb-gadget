import 'dart:async';
import 'dart:collection' show Queue;
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:using/using.dart';
import '../aio.ffi.dart' as ffi_aio;
import '../core/aio_context.dart';
import '../core/buffer_pool.dart';
import '../core/exceptions.dart';

/// Defines how [AioSink] handles backpressure when the write queue is full.
enum BackpressureBehavior {
  /// Block until queue space is available.
  ///
  /// **WARNING**: Can cause memory leaks if writes are not properly awaited.
  /// The awaiting futures accumulate in memory. Only use this if you're
  /// certain all writes will be awaited and completed in bounded time.
  ///
  /// Best for: Critical data that must not be lost, with careful async handling.
  block,

  /// Drop the oldest queued write and add the new one.
  ///
  /// Prioritizes recent data over old data. The dropped write's future
  /// completes with 0 bytes written. Safe for fire-and-forget writes.
  ///
  /// Best for: Real-time data streams where recent data is more valuable
  /// (e.g., sensor readings, video frames, live telemetry, HID reports, etc.).
  dropOldest,

  /// Drop the new write and return immediately.
  ///
  /// Preserves already-queued data. The new write's future completes
  /// immediately with 0 bytes written. Safe for fire-and-forget writes.
  ///
  /// Best for: Preserving data integrity when older writes are more important
  /// (e.g., sequential log entries, ordered commands).
  dropNewest,

  /// Throw [AioQueueFullException] when queue is full.
  ///
  /// Lets the application decide how to handle backpressure. The caller
  /// must catch and handle the exception appropriately.
  ///
  /// Best for: Applications that need explicit control over backpressure
  /// handling and can implement custom retry or buffering logic.
  throwError,
}

/// Tuning parameters for [AioSink].
final class AioSinkConfig {
  const AioSinkConfig({
    this.maxQueueSize = 32,
    this.backpressure = .dropOldest,
  });

  final int maxQueueSize;
  final BackpressureBehavior backpressure;
}

/// Internal class representing a pending write entry in the [AioSink] queue.
final class _WriteEntry {
  _WriteEntry(this.data, this.offset);

  final Uint8List data;

  /// Write offset captured at enqueue time to preserve ordering.
  final int offset;

  /// Resolves with bytes written, or 0 if dropped before reaching the kernel.
  final completer = Completer<int>();
}

/// Asynchronous file writer using kernel AIO with configurable backpressure.
///
/// Maintains a bounded FIFO write queue of at most [AioSinkConfig.maxQueueSize]
/// entries.  When the queue is full the chosen [BackpressureBehavior] governs
/// how new writes are handled.
final class AioSink with Releasable implements StreamSink<Uint8List> {
  AioSink(this._fd, this._ctx, this._pool, {AioSinkConfig? config})
    : config = config ?? AioSinkConfig(maxQueueSize: _pool.poolSize);

  final int _fd;
  final AioContext _ctx;
  final BufferPool _pool;
  final AioSinkConfig config;

  final Queue<_WriteEntry> _writeQueue = Queue();

  /// Single shared completer for all [BackpressureBehavior.block] waiters.
  /// Nulled out once space is confirmed so the next enqueue creates a fresh one.
  Completer<void>? _queueSpaceCompleter;

  int get queued => _writeQueue.length;

  final Completer<void> _doneCompleter = Completer<void>();
  bool _closed = false;
  bool _processorRunning = false;
  int _writeOffset = 0;

  @override
  Future<void> get done => _doneCompleter.future;

  /// Writes [data], applying [config.backpressure] if the queue is full.
  ///
  /// Returns the number of bytes accepted by the kernel, or `0` if the write
  /// was dropped by [BackpressureBehavior.dropOldest] /
  /// [BackpressureBehavior.dropNewest].
  Future<int> write(Uint8List data) async {
    if (_closed || isReleased) {
      return Future.error(StateError('Cannot write to a closed sink'));
    }

    if (_writeQueue.length >= config.maxQueueSize) {
      switch (config.backpressure) {
        case .block:
          // Shared completer: all blocked callers wake together when space
          // opens.  Each re-checks the length condition independently.
          _queueSpaceCompleter ??= Completer<void>();
          await _queueSpaceCompleter!.future;
          if (_writeQueue.length < config.maxQueueSize) {
            _queueSpaceCompleter = null;
          }

        case .dropOldest:
          final dropped = _writeQueue.removeFirst();
          if (!dropped.completer.isCompleted) {
            dropped.completer.complete(0);
          }

        case .dropNewest:
          return 0;

        case .throwError:
          throw AioQueueFullException(_writeQueue.length, config.maxQueueSize);
      }
    }

    final entry = _WriteEntry(data, _writeOffset);
    _writeOffset += data.length < _pool.bufferSize
        ? data.length
        : _pool.bufferSize;
    _writeQueue.add(entry);
    _wakeProcessor();

    return entry.completer.future;
  }

  @override
  void add(Uint8List data) {
    return write(data).ignore();
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!_closed && !_doneCompleter.isCompleted) {
      _doneCompleter.completeError(error, stackTrace);
    }
  }

  @override
  Future<void> addStream(Stream<Uint8List> stream) async {
    await for (final chunk in stream) {
      await write(chunk);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return done;
    _closed = true;

    try {
      await Future.wait(_writeQueue.map((e) => e.completer.future));
      if (!_doneCompleter.isCompleted) _doneCompleter.complete();
    } catch (err, st) {
      if (!_doneCompleter.isCompleted) _doneCompleter.completeError(err, st);
    }
  }

  @override
  Future<void> release() async {
    if (isReleased) return;
    super.release();

    // Wake blocked writers so they don't hang.
    _queueSpaceCompleter?.completeError(const AioDisposedException());
    _queueSpaceCompleter = null;

    for (final e in _writeQueue) {
      if (!e.completer.isCompleted) {
        e.completer.completeError(const AioDisposedException());
      }
    }
    _writeQueue.clear();

    if (!_closed) await close();
  }

  void _wakeProcessor() {
    if (_processorRunning || _writeQueue.isEmpty) return;
    _processorRunning = true;
    _runProcessor();
  }

  Future<void> _runProcessor() async {
    while (_writeQueue.isNotEmpty && !isReleased) {
      final entry = _writeQueue.first;

      try {
        final written = await _kernelWrite(entry);
        if (!entry.completer.isCompleted) entry.completer.complete(written);
      } catch (err, st) {
        if (!entry.completer.isCompleted) {
          entry.completer.completeError(err, st);
        }
      }

      _writeQueue.removeFirst();

      // Wake any callers blocked on queue space.
      if (_queueSpaceCompleter != null && !_queueSpaceCompleter!.isCompleted) {
        _queueSpaceCompleter!.complete();
      }
    }

    _processorRunning = false;
  }

  Future<int> _kernelWrite(_WriteEntry entry) async {
    final data = entry.data;
    if (data.isEmpty) return 0;

    final buf = await _pool.acquireAsync();
    final iocb = calloc<ffi_aio.iocb>();
    final opId = iocb.address;

    try {
      final len = data.length < _pool.bufferSize
          ? data.length
          : _pool.bufferSize;
      buf.asTypedList(len).setAll(0, data.take(len));

      iocb.ref
        ..aio_fildes = _fd
        ..aio_lio_opcode = 1
        ..data = ffi.Pointer.fromAddress(opId)
        ..u.c.buf = buf.cast()
        ..u.c.nbytes = len
        ..u.c.offset = entry.offset;

      return await _ctx.submit(iocb, opId);
    } finally {
      _pool.free(buf);
      calloc.free(iocb);
    }
  }
}
