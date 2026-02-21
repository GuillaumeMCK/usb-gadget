import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:using/using.dart';
import '../aio.ffi.dart' as ffi_aio;
import '../core/aio_context.dart';
import '../core/buffer_pool.dart';

/// Asynchronous file reader using kernel AIO.
final class AioStream with Releasable {
  AioStream(this._fd, this._ctx, this._pool, {int maxInflight = 4})
    : _maxInflight = maxInflight {
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
  final int _maxInflight;

  late final StreamController<Uint8List> _controller;
  final Set<int> _activeOps = {};
  int _offset = 0;
  bool _paused = false;
  bool _eof = false;

  /// Stream of data chunks.
  Stream<Uint8List> get stream => _controller.stream;

  /// Current read offset.
  int get offset => _offset;

  /// End of file reached.
  bool get eof => _eof;

  void _start() => _fillWindow();

  void _resume() {
    _paused = false;
    _fillWindow();
  }

  void _fillWindow() {
    while (_activeOps.length < _maxInflight &&
        !_paused &&
        !_eof &&
        !isReleased) {
      _submitRead();
    }
  }

  void _submitRead() {
    final buf = _pool.acquire();
    if (buf == null) return;

    final iocb = calloc<ffi_aio.iocb>();
    final opId = iocb.address;
    final readOffset = _offset;

    _offset += _pool.bufferSize;
    _activeOps.add(opId);

    iocb.ref
      ..aio_fildes = _fd
      ..aio_lio_opcode = 0
      ..data = ffi.Pointer.fromAddress(opId)
      ..u.c.buf = buf.cast()
      ..u.c.nbytes = _pool.bufferSize
      ..u.c.offset = readOffset;

    _ctx
        .submit(iocb, opId)
        .then((bytesRead) {
          _activeOps.remove(opId);

          if (bytesRead > 0 && !_controller.isClosed) {
            _controller.add(buf.asTypedList(bytesRead));
            _fillWindow();
          } else {
            _eof = true;
            if (!_controller.isClosed) _controller.close();
          }
        })
        .catchError((Object err) {
          _activeOps.remove(opId);
          if (!_controller.isClosed) _controller.addError(err);
        })
        .whenComplete(() {
          _pool.free(buf);
          calloc.free(iocb);
        });
  }

  @override
  void release() {
    if (isReleased) return;
    super.release();
    if (!_controller.isClosed) _controller.close();
  }
}
