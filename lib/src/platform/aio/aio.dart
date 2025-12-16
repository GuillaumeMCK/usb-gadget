/// High-performance asynchronous I/O for Linux using kernel AIO (libaio).
///
/// This library provides both low-level primitives and high-level streaming
/// interfaces for efficient file I/O operations.
library;

// Core primitives for advanced use
export 'aio_context.dart' show AioContext;

// High-level streaming API
export 'aio_stream.dart' show AioReader, AioWriter;
