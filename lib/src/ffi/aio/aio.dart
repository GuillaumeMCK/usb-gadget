/// Linux AIO (Asynchronous I/O) library for Dart
///
/// This library provides efficient async I/O operations using Linux's native
/// AIO (libaio) through FFI. Operations run in dedicated isolates to prevent
/// blocking the main thread.
///
/// ## Features
///
/// - Zero-copy I/O using native memory
/// - Non-blocking operations with event-driven architecture
/// - Automatic batching and flow control
/// - Efficient isolate-based concurrency
/// - Stream-based reading interface
/// - Future-based writing interface
///
/// ## Usage
///
/// ### Reading from a file:
/// ```dart
/// import 'dart:io';
/// import 'package:aio/aio.dart';
///
/// final file = File('large_file.bin').openSync();
/// final reader = AioReader(
///   fd: file.fd,
///   bufferSize: 64 * 1024, // 64KB chunks
///   numBuffers: 4,         // 4 concurrent reads
/// );
///
/// await for (final chunk in reader.stream()) {
///   // Process chunk
///   print('Read ${chunk.length} bytes');
/// }
///
/// file.closeSync();
/// ```
///
/// ### Writing to a file:
/// ```dart
/// final file = File('output.bin').openSync(mode: FileMode.write);
/// final writer = AioWriter(
///   fd: file.fd,
///   bufferSize: 64 * 1024, // 64KB chunks
///   numBuffers: 4,         // 4 concurrent writes
/// );
///
/// await writer.write(data1);
/// await writer.write(data2);
/// await writer.flush(); // Ensure all data is written
///
/// writer.dispose();
/// file.closeSync();
/// ```
///
/// ### Custom error handling:
/// ```dart
/// final reader = AioReader(fd: file.fd);
///
/// await for (final chunk in reader.stream(
///   handleError: (errorCode) {
///     if (errorCode == Errno.eintr) {
///       return AioErrorAction.ignore; // Retry
///     }
///     return AioErrorAction.error;
///   },
/// )) {
///   processChunk(chunk);
/// }
/// ```
library;

import 'dart:ffi' as ffi;
import 'dart:io' show OSError;

import 'package:ffi/ffi.dart';
import 'package:usb_gadget/src/ffi/aio/aio.dart' show AioReader, AioWriter;

import '../errno/errno.dart';
import 'aio.ffi.dart' as aio_ffi;

export 'aio_messages.dart';
export 'aio_reader.dart' show AioReader;
export 'aio_writer.dart' show AioWriter;

/// Singleton library loader for libaio
class AioLibrary {
  AioLibrary._();

  static final instance = AioLibrary._();

  final aio_ffi.Aio lib = aio_ffi.Aio(ffi.DynamicLibrary.open('libaio.so'));
}

/// AIO operation codes
enum AioOpcode {
  pread(0),
  pwrite(1),
  fsync(2);

  const AioOpcode(this.value);

  final int value;
}

/// Flags for AIO read/write operations
enum AioRwFlag {
  hipri(1 << 0),
  dsync(1 << 1),
  sync(1 << 2),
  nowait(1 << 3),
  append(1 << 4);

  const AioRwFlag(this.value);

  final int value;
}

/// Action to take when an AIO operation encounters an error
enum AioErrorAction { error, ignore, empty }

/// Low-level AIO operations wrapper
///
/// Provides direct access to Linux AIO (libaio) operations.
/// Users should prefer the high-level [AioReader] and [AioWriter] classes.
class AioContext {
  /// Creates an AIO context with the specified maximum number of events
  ///
  /// Throws [OSError] if creation fails.
  factory AioContext.create(int maxEvents) {
    if (maxEvents <= 0) {
      throw ArgumentError.value(maxEvents, 'maxEvents', 'Must be positive');
    }

    final ctxPtr = calloc<ffi.Pointer<aio_ffi.io_context>>();
    try {
      final result = AioLibrary.instance.lib.io_setup(maxEvents, ctxPtr);
      if (result != 0) {
        throw Errno.currentOSError;
      }
      return AioContext._(ctxPtr.value, maxEvents);
    } finally {
      calloc.free(ctxPtr);
    }
  }

  AioContext._(this._ctx, this._maxEvents);

  final ffi.Pointer<aio_ffi.io_context> _ctx;
  final int _maxEvents;
  bool _destroyed = false;

  /// Maximum number of concurrent operations this context can handle
  int get maxEvents => _maxEvents;

  /// Whether this context has been destroyed
  bool get isDestroyed => _destroyed;

  /// Destroys this AIO context and frees associated resources
  ///
  /// After calling this method, the context cannot be used again.
  /// Throws [StateError] if already destroyed.
  void destroy() {
    if (_destroyed) {
      throw StateError('Context already destroyed');
    }

    final result = AioLibrary.instance.lib.io_destroy(_ctx);
    _destroyed = true;

    if (result != 0) {
      throw Errno.currentOSError;
    }
  }

  /// Submits AIO operations to the kernel
  ///
  /// Returns the number of operations successfully submitted.
  /// Throws [OSError] if submission fails.
  int submit(List<AioControlBlock> iocbs) {
    _checkNotDestroyed();
    if (iocbs.isEmpty) return 0;
    if (iocbs.length > _maxEvents) {
      throw ArgumentError('Cannot submit more than $_maxEvents operations');
    }

    final iocbArray = calloc<ffi.Pointer<aio_ffi.iocb>>(iocbs.length);
    try {
      for (var i = 0; i < iocbs.length; i++) {
        iocbArray[i] = iocbs[i]._iocb;
      }

      final result = AioLibrary.instance.lib.io_submit(
        _ctx,
        iocbs.length,
        iocbArray,
      );

      if (result < 0) {
        throw Errno.currentOSError;
      }

      return result;
    } finally {
      calloc.free(iocbArray);
    }
  }

  /// Retrieves completed AIO events
  ///
  /// [minNr] - Minimum number of events to wait for (0 = non-blocking)
  /// [maxNr] - Maximum number of events to retrieve
  /// [timeout] - Optional timeout duration
  ///
  /// Returns a list of completed events.
  List<AioEvent> getEvents({int minNr = 1, int? maxNr, Duration? timeout}) {
    _checkNotDestroyed();

    final max = maxNr ?? _maxEvents;
    if (minNr < 0 || minNr > max) {
      throw ArgumentError('minNr must be between 0 and $max');
    }

    final events = calloc<aio_ffi.io_event>(max);
    ffi.Pointer<aio_ffi.timespec> timeoutPtr = ffi.nullptr;

    try {
      if (timeout != null) {
        timeoutPtr = calloc<aio_ffi.timespec>();
        final seconds = timeout.inMicroseconds / 1000000.0;
        timeoutPtr.ref.tv_sec = seconds.floor();
        timeoutPtr.ref.tv_nsec = ((seconds - timeoutPtr.ref.tv_sec) * 1e9)
            .floor();
      }

      final result = AioLibrary.instance.lib.io_getevents(
        _ctx,
        minNr,
        max,
        events,
        timeoutPtr,
      );

      if (result < 0) {
        throw Errno.currentOSError;
      }

      return List.generate(result, (i) => AioEvent._(events[i]));
    } finally {
      calloc.free(events);
      if (timeoutPtr != ffi.nullptr) {
        calloc.free(timeoutPtr);
      }
    }
  }

  void _checkNotDestroyed() {
    if (_destroyed) {
      throw StateError('Context has been destroyed');
    }
  }
}

/// Represents an AIO control block (IOCB)
class AioControlBlock {
  /// Creates an IOCB for a read operation
  factory AioControlBlock.read({
    required int fd,
    required ffi.Pointer<ffi.Void> buffer,
    required int size,
    int offset = 0,
    int userData = 0,
  }) {
    return AioControlBlock._create(
      fd: fd,
      opcode: AioOpcode.pread,
      buffer: buffer,
      size: size,
      offset: offset,
      userData: userData,
    );
  }

  /// Creates an IOCB for a write operation
  factory AioControlBlock.write({
    required int fd,
    required ffi.Pointer<ffi.Void> buffer,
    required int size,
    int offset = 0,
    int userData = 0,
  }) {
    return AioControlBlock._create(
      fd: fd,
      opcode: AioOpcode.pwrite,
      buffer: buffer,
      size: size,
      offset: offset,
      userData: userData,
    );
  }

  factory AioControlBlock._create({
    required int fd,
    required AioOpcode opcode,
    required ffi.Pointer<ffi.Void> buffer,
    required int size,
    int offset = 0,
    int userData = 0,
  }) {
    if (fd < 0) {
      throw ArgumentError.value(fd, 'fd', 'Must be non-negative');
    }
    if (size < 0) {
      throw ArgumentError.value(size, 'size', 'Must be non-negative');
    }

    final iocb = calloc<aio_ffi.iocb>();
    iocb.ref.aio_fildes = fd;
    iocb.ref.aio_lio_opcode = opcode.value;
    iocb.ref.aio_reqprio = 0;
    iocb.ref.aio_rw_flags = 0;
    iocb.ref.data = ffi.Pointer<ffi.Void>.fromAddress(userData);
    iocb.ref.u.c.buf = buffer;
    iocb.ref.u.c.nbytes = size;
    iocb.ref.u.c.offset = offset;

    return AioControlBlock._(iocb);
  }

  AioControlBlock._(this._iocb);

  final ffi.Pointer<aio_ffi.iocb> _iocb;
  bool _freed = false;

  /// Frees the memory associated with this IOCB
  void free() {
    if (!_freed) {
      calloc.free(_iocb);
      _freed = true;
    }
  }
}

/// Represents a completed AIO event
class AioEvent {
  AioEvent._(aio_ffi.io_event event)
    : userData = event.data.address,
      result = event.res,
      result2 = event.res2;

  /// User data associated with the operation
  final int userData;

  /// Result of the operation (bytes transferred or negative error code)
  final int result;

  /// Secondary result (typically 0)
  final int result2;

  /// Whether the operation succeeded
  bool get isSuccess => result >= 0;

  /// Error code if the operation failed (0 if successful)
  int get errorCode => result < 0 ? -result : 0;

  /// Number of bytes transferred (if successful)
  int get bytesTransferred => result >= 0 ? result : 0;
}
