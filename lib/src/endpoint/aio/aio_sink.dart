import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:using/using.dart';

import 'aio_context.dart';
import 'buffer_pool.dart';
import '/src/platform/libaio/libaio.ffi.dart' as ffi_aio;

/// Asynchronous file writer using kernel AIO.
///
/// Use [write] for individual chunks and [addStream] for pipeline
/// sources — both are `async` and propagate hardware backpressure naturally
/// via [BufferPool.acquireAsync].
final class AioSink with Releasable {
  AioSink(this._fd, this._ctx, this._pool);

  final int _fd;
  final AioContext _ctx;
  final BufferPool _pool;

  /// Writes [data] to the kernel asynchronously, suspending the caller until
  /// a buffer slot is available.
  ///
  /// Returns the number of bytes accepted by the kernel (capped at
  /// [BufferPool.bufferSize]).
  /// Throws [StateError] if the sink is released.
  Future<int> write(Uint8List data) async {
    if (isReleased) {
      throw StateError('Cannot write to a closed sink');
    }
    final buf = await _pool.acquireAsync();
    final iocb = calloc<ffi_aio.iocb>();
    final opId = iocb.address;

    try {
      final len = data.length < _pool.bufferSize
          ? data.length
          : _pool.bufferSize;
      if (len > 0) buf.asTypedList(len).setAll(0, data.take(len));

      iocb.ref
        ..aio_fildes = _fd
        ..aio_lio_opcode = ffi_aio.IOCB_CMD_PWRITE
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
  Future<void> release() async {
    if (isReleased) return;
    super.release();
  }
}
