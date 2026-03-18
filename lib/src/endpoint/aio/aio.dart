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

/// Manages the [AioContext], [BufferPool], and file descriptor for a FunctionFS endpoint.
final class Aio with Releasable {
  /// Raw Linux file descriptor for the endpoint.
  final int fd;
  final BufferPool _pool;
  final AioContext _ctx;

  /// Creates an instance with manual sizing. Defaults to 512B (High-Speed Bulk MPS).
  Aio(int fd, {int maxEvents = 128, int bufferSize = 512, int poolSize = 32})
    : this._(fd, pool: BufferPool(bufferSize, poolSize), maxEvents: maxEvents);

  /// Automatically tunes buffer and pool sizes based on the [EndpointConfig] type.
  factory Aio.fromEndpointConfig(int fd, EndpointConfig config) {
    final (maxEvents, defaultMps, poolSize) = switch (config) {
      BulkEndpointConfig() => (256, 512, 64),
      ControlEndpointConfig() => (64, 64, 16),
      IsochronousEndpointConfig() => (128, 1024, 32),
      InterruptEndpointConfig() => (64, 64, 16),
    };
    return Aio._(
      fd,
      pool: BufferPool(config.maxPacketSize ?? defaultMps, poolSize),
      maxEvents: maxEvents,
    );
  }

  Aio._(this.fd, {required BufferPool pool, required int maxEvents})
    : _pool = pool,
      _ctx = AioContext(maxEvents);

  /// The size of each buffer slot (matches the endpoint MPS).
  int get bufferSize => _pool.bufferSize;

  /// Returns an [AioStream] for reading (OUT). Throws if released.
  AioStream get stream {
    if (isReleased) throw const AioDisposedException();
    return AioStream(fd, _ctx, _pool);
  }

  /// Returns an [AioSink] for writing (IN). Throws if released.
  AioSink get sink {
    if (isReleased) throw const AioDisposedException();
    return AioSink(fd, _ctx, _pool);
  }

  /// Disposes of the context and pool. Idempotent.
  @override
  void release() {
    if (isReleased) return;
    super.release();
    _ctx.release();
    _pool.release();
  }
}
