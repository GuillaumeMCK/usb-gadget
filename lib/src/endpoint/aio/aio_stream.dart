import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:using/using.dart';

import 'aio_context.dart';
import 'buffer_pool.dart';
import '/src/platform/libaio/libaio.ffi.dart' as ffi_aio;

/// Asynchronous file reader using kernel AIO.
///
/// Concurrency is bounded naturally by [BufferPool]: [_submitRead] stops as
/// soon as [BufferPool.acquire] returns `null`, so there is no separate
/// inflight-window counter.
final class AioStream with Releasable {
  AioStream(this._fd, this._ctx, this._pool) {
    _controller = StreamController<Uint8List>(
      onListen: _start,
      onPause: () => _paused = true,
      onResume: _resume,
      onCancel: release,
    );
  }

  final int _fd;
  final AioContext _ctx;
  final BufferPool _pool;

  late final StreamController<Uint8List> _controller;
  bool _paused = false;

  /// Stream of incoming data
  Stream<Uint8List> get stream => _controller.stream;

  /// Submits reads until the pool is exhausted, paused, EOF, or released.
  void _fillWindow() {
    while (!_paused && !isReleased) {
      if (!_submitRead()) {
        break; // pool exhausted — stop until a buffer is freed
      }
    }
  }

  void _start() {
    _fillWindow();
  }

  void _resume() {
    _paused = false;
    _fillWindow();
  }

  bool _submitRead() {
    final buf = _pool.acquire();
    if (buf == null) return false;

    final iocb = calloc<ffi_aio.iocb>();
    final opId = iocb.address;

    iocb.ref
      ..aio_fildes = _fd
      ..aio_lio_opcode = ffi_aio.IOCB_CMD_PREAD
      ..data = ffi.Pointer.fromAddress(opId)
      ..u.c.buf = buf.cast()
      ..u.c.nbytes = _pool.bufferSize
      ..u.c.offset = 0;

    _ctx
        .submit(iocb, opId)
        .then((bytesRead) {
          if (_controller.isClosed) return;
          if (bytesRead >= 0) {
            // Even if bytesRead is 0, it's a ZLP, we pass it up.
            _controller.add(.fromList(buf.asTypedList(bytesRead)));
            _fillWindow(); // Keep the pipe full
          }
        })
        .catchError((Object err) {
          if (!_controller.isClosed) _controller.addError(err);
        })
        .whenComplete(() {
          _pool.free(buf);
          calloc.free(iocb);
        });

    return true;
  }

  @override
  void release() {
    if (isReleased) return;
    super.release();
    if (!_controller.isClosed) _controller.close();
  }
}
