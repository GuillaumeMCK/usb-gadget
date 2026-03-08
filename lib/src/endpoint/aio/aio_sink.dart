import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:using/using.dart';

import 'aio_context.dart';
import 'buffer_pool.dart';
import '/src/platform/libaio/libaio.ffi.dart' as ffi_aio;

/// Asynchronous file writer using kernel AIO.
final class AioSink with Releasable implements StreamSink<Uint8List> {
  AioSink(this._fd, this._ctx, this._pool);

  final int _fd;
  final AioContext _ctx;
  final BufferPool _pool;

  final Completer<void> _doneCompleter = Completer<void>();
  bool _closed = false;

  @override
  Future<void> get done => _doneCompleter.future;

  /// Writes [data] to the kernel asynchronously.
  ///
  /// Suspends naturally when the [BufferPool] is exhausted — no explicit
  /// backpressure policy is needed. Returns the number of bytes accepted by
  /// the kernel (capped at [BufferPool.bufferSize]).
  ///
  /// Throws [StateError] if the sink is closed or released.
  Future<int> write(Uint8List data) async {
    if (_closed || isReleased) {
      throw StateError('Cannot write to a closed sink');
    }
    if (data.isEmpty) return 0;

    // Blocks here when all buffers are in flight — hardware backpressure.
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
        ..u.c.offset = 0; // USB endpoints are not seekable

      return await _ctx.submit(iocb, opId);
    } finally {
      _pool.free(buf);
      calloc.free(iocb);
    }
  }

  @override
  void add(Uint8List data) => write(data).ignore();

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
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }

  @override
  Future<void> release() async {
    if (isReleased) return;
    super.release();
    if (!_closed) await close();
  }
}
