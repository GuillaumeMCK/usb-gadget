import 'package:using/using.dart';

import '/usb_gadget.dart';
import 'aio_context.dart';
import 'buffer_pool.dart';
import 'exceptions.dart';
import 'aio_sink.dart';
import 'aio_stream.dart';

export 'exceptions.dart';
export 'aio_sink.dart';
export 'aio_stream.dart';

/// Simple, safe AIO with automatic resource management.
///
/// A single [BufferPool] is shared between the [AioContext] and every
/// [AioStream] / [AioSink] created from this instance. The pool size is the
/// concurrency limit for both reads and writes — no separate tuning needed.
final class Aio with Releasable {
  Aio(int fd, {int maxEvents = 128, int bufferSize = 16384, int poolSize = 32})
    : this._(fd, pool: BufferPool(bufferSize, poolSize), maxEvents: maxEvents);

  /// Creates an [Aio] instance sized for the given [EndpointConfig].
  ///
  /// Buffer size is set to [EndpointConfig.maxPacketSize] when provided,
  /// otherwise the transfer-type default is used.
  factory Aio.fromEndpointConfig(int fd, EndpointConfig config) {
    final (maxEvents, bufferSize, poolSize) = switch (config) {
      BulkEndpointConfig() => (256, 65536, 64),
      ControlEndpointConfig() => (64, 512, 16),
      IsochronousEndpointConfig() => (128, 8192, 32),
      InterruptEndpointConfig() => (64, 1024, 16),
    };
    return Aio._(
      fd,
      pool: BufferPool(config.maxPacketSize ?? bufferSize, poolSize),
      maxEvents: maxEvents,
    );
  }

  Aio._(this.fd, {required BufferPool pool, required int maxEvents})
    : _pool = pool,
      _ctx = AioContext(maxEvents);

  final int fd;
  final BufferPool _pool;
  final AioContext _ctx;

  int get bufferSize => _pool.bufferSize;

  int get poolSize => _pool.poolSize;

  int get available => _pool.available;

  AioStream get stream {
    if (isReleased) throw const AioDisposedException();
    return AioStream(fd, _ctx, _pool);
  }

  AioSink get sink {
    if (isReleased) throw const AioDisposedException();
    return AioSink(fd, _ctx, _pool);
  }

  @override
  void release() {
    if (isReleased) return;
    super.release();
    _ctx.release();
    _pool.release();
  }
}
