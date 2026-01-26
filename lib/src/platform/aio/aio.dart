/// High-performance asynchronous I/O for Linux using kernel AIO (libaio).
///
/// This library provides both low-level primitives and high-level streaming
/// interfaces for efficient file I/O operations.
library;

export 'aio_context.dart' show AioContext;
export 'aio_stream.dart' show AioConfig, AioReader, AioWriter;
