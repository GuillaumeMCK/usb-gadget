import 'package:using/using.dart';

import '/usb_gadget.dart';
import 'core/aio_context.dart';
import 'core/buffer_pool.dart';
import 'core/exceptions.dart';
import 'io/aio_sink.dart';
import 'io/aio_stream.dart';

export 'core/exceptions.dart';
export 'io/aio_sink.dart';
export 'io/aio_stream.dart';

/// Simple, safe AIO with automatic resource management.
///
/// A single [BufferPool] is shared between the [AioContext] and every
/// [AioStream] / [AioSink] created from this instance. This ensures that
/// backpressure in [AioSink._kernelWrite] (via [BufferPool.acquireAsync]) is
/// felt across the whole I/O pipeline rather than only within one side.
final class Aio with Releasable {
  Aio({int maxEvents = 128, int bufferSize = 16384, int poolSize = 32})
    : this._(pool: BufferPool(bufferSize, poolSize), maxEvents: maxEvents);

  /// Creates an [Aio] instance tuned for the given [EndpointConfig].
  ///
  /// Uses the transfer-type defaults unless [EndpointConfig.maxPacketSize] is
  /// set, in which case that value overrides the default buffer size.
  factory Aio.fromEndpointConfig(EndpointConfig config) {
    final (maxEvents, bufferSize, poolSize, ctxPollInterval) = switch (config) {
      BulkEndpointConfig() => (256, 65536, 64, _lowerCtxPollInterval),
      ControlEndpointConfig() => (64, 512, 16, _lowerCtxPollInterval),
      IsochronousEndpointConfig() => (128, 8192, 32, _lowerCtxPollInterval),
      InterruptEndpointConfig(:final interval) => (
        64,
        1024,
        16,
        switch (interval ~/ 2) {
          <= _lowerCtxPollInterval => _lowerCtxPollInterval,
          final i => i,
        },
      ),
    };

    return Aio._(
      pool: BufferPool(config.maxPacketSize ?? bufferSize, poolSize),
      maxEvents: maxEvents,
      ctxPollInterval: ctxPollInterval,
    );
  }

  // Private constructor that accepts a pre-built pool, ensuring _pool and _ctx
  // share the same instance without needing a `late` field.
  Aio._({
    required BufferPool pool,
    required int maxEvents,
    Duration ctxPollInterval = const Duration(milliseconds: 1),
  }) : _pool = pool,
       _ctx = AioContext(maxEvents, ctxPollInterval);

  /// Bulk transfer optimized (64 KB buffers, high concurrency).
  Aio.bulk() : this._(pool: BufferPool(65536, 64), maxEvents: 256);

  /// Control transfer optimized (512 B buffers, low latency).
  Aio.control() : this._(pool: BufferPool(512, 16), maxEvents: 64);

  /// Interrupt transfer optimized (1 KB buffers, low latency).
  Aio.interrupt() : this._(pool: BufferPool(1024, 16), maxEvents: 64);

  /// Isochronous transfer optimized (8 KB buffers, streaming).
  Aio.isochronous() : this._(pool: BufferPool(8192, 32), maxEvents: 128);

  /// Minimum poll interval for the AIO context to avoid excessive CPU usage on
  /// very low intervals. (default: 500μs)
  static const _lowerCtxPollInterval = Duration(microseconds: 500);

  final BufferPool _pool;
  final AioContext _ctx;

  int get bufferSize => _pool.bufferSize;

  int get poolSize => _pool.poolSize;

  int get available => _pool.available;

  AioStream createReader(int fd, {int maxInflight = 4}) {
    if (isReleased) throw const AioDisposedException();
    return AioStream(fd, _ctx, _pool, maxInflight: maxInflight);
  }

  AioSink createWriter(int fd, {AioSinkConfig? config}) {
    if (isReleased) throw const AioDisposedException();
    return AioSink(fd, _ctx, _pool, config: config);
  }

  @override
  void release() {
    if (isReleased) return;
    super.release();
    _ctx.release();
    _pool.release();
  }
}
