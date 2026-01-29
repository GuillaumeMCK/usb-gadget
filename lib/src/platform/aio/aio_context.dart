import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:using/using.dart';
import '/src/logger/logger.dart';
import '../errno/errno.dart';
import 'aio.ffi.dart' hide iocb;
import 'aio.ffi.dart' as aio_ffi show iocb;

/// Internal bindings for Linux kernel AIO (libaio).
class AioBindings {
  AioBindings._();

  static final Aio _instance = Aio(() {
    try {
      return ffi.DynamicLibrary.open('libaio.so');
    } catch (_) {
      return ffi.DynamicLibrary.process();
    }
  }());

  /// The singleton instance of the [Aio] bindings.
  static Aio get instance => _instance;
}

// ============================================================================
// Resource Pool - Reusable buffers
// ============================================================================

/// A pool of reusable memory buffers for AIO operations.
///
/// This class manages native memory buffers allocated via `calloc`.
/// It is [Releasable] and will free all buffers when released.
final class BufferPool with Releasable {
  /// Creates a new [BufferPool] with [poolSize] buffers of [bufferSize] bytes each.
  BufferPool(this.bufferSize, this.poolSize) {
    _pool = List.generate(poolSize, (_) => calloc<ffi.Uint8>(bufferSize));
  }

  /// The size of each buffer in bytes.
  final int bufferSize;

  /// The total number of buffers in the pool.
  final int poolSize;
  late final List<ffi.Pointer<ffi.Uint8>> _pool;
  final Set<ffi.Pointer<ffi.Uint8>> _inUse = {};

  /// Acquires a buffer from the pool.
  ///
  /// Returns a pointer to a buffer if one is available and the pool is not released,
  /// otherwise returns `null`.
  ffi.Pointer<ffi.Uint8>? acquire() {
    if (isReleased) return null;

    final available = _pool.where((p) => !_inUse.contains(p));
    if (available.isEmpty) return null;

    final buffer = available.first;
    _inUse.add(buffer);
    return buffer;
  }

  /// Marks a [buffer] as available for reuse.
  void releaseBuffer(ffi.Pointer<ffi.Uint8> buffer) {
    _inUse.remove(buffer);
  }

  @override
  void release() {
    if (!isReleased) {
      _pool
        ..forEach(calloc.free)
        ..clear();
      _inUse.clear();
      super.release();
    }
  }

  /// The number of available buffers in the pool.
  int get available => isReleased ? 0 : poolSize - _inUse.length;

  /// The number of buffers currently in use.
  int get inUse => _inUse.length;
}

// ============================================================================
// Operation Tracking - Proper lifecycle management
// ============================================================================

/// A unique identifier for an AIO operation.
@immutable
final class OperationId {
  /// Creates an [OperationId] with the given integer [value].
  const OperationId(this.value);

  /// The raw value of the operation identifier.
  final int value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is OperationId && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// The type of AIO operation.
enum OperationType {
  /// Read operation.
  read,

  /// Write operation.
  write,
}

/// Represents an AIO operation that has been submitted and is being tracked.
final class TrackedOperation {
  /// Creates a new [TrackedOperation].
  TrackedOperation({
    required this.id,
    required this.type,
    required this.buffer,
    required this.size,
    required this.offset,
    required this.iocb,
    this.userData,
  });

  /// The unique identifier for this operation.
  final OperationId id;

  /// The type of operation (read or write).
  final OperationType type;

  /// The native buffer used for the operation.
  final ffi.Pointer<ffi.Uint8> buffer;

  /// The size of the data to be transferred in bytes.
  final int size;

  /// The file offset where the operation should occur.
  final int offset;

  /// The native AIO control block.
  final ffi.Pointer<aio_ffi.iocb> iocb;

  /// Optional opaque user data associated with the operation.
  final Object? userData;

  /// Frees the native resources associated with this operation.
  void free() {
    calloc.free(iocb);
  }
}

// ============================================================================
// AIO Context - Event-driven completion handling
// ============================================================================

/// A context for managed Linux kernel AIO operations.
///
/// This class encapsulates an `io_context` and provides high-level methods for
/// submitting operations and retrieving completion events.
final class AioContext with PlatformLogger {
  /// Creates an [AioContext] capable of handling up to [maxConcurrent]
  /// pending operations.
  factory AioContext({required int maxConcurrent}) {
    if (maxConcurrent <= 0 || maxConcurrent > 65536) {
      throw ArgumentError.value(
        maxConcurrent,
        'maxConcurrent',
        'Must be between 1 and 65536',
      );
    }

    final ctxPtr = calloc<ffi.Pointer<io_context>>();
    try {
      final result = AioBindings.instance.io_setup(maxConcurrent, ctxPtr);
      if (result != 0) {
        throw Errno.toOSError(-result, 'Failed to create AIO context');
      }
      final handle = ctxPtr.value;
      if (handle == ffi.nullptr) {
        throw Errno.toOSError(Errno.einval, 'AIO context handle is null');
      }
      return AioContext._(handle, maxConcurrent);
    } finally {
      calloc.free(ctxPtr);
    }
  }

  AioContext._(this._handle, this._maxConcurrent);

  final ffi.Pointer<io_context> _handle;
  final int _maxConcurrent;
  final Map<OperationId, TrackedOperation> _inFlight = {};
  bool _disposed = false;

  /// The maximum number of concurrent operations allowed in this context.
  int get maxConcurrent => _maxConcurrent;

  /// The number of operations currently in-flight.
  int get inFlightCount => _inFlight.length;

  /// Whether this context has been disposed.
  bool get isDisposed => _disposed;

  /// Whether a new operation can be submitted without exceeding [maxConcurrent].
  bool get canSubmit => _inFlight.length < _maxConcurrent;

  /// Submit operations - returns number submitted
  int submit(List<TrackedOperation> operations) {
    _checkNotDisposed();

    if (operations.isEmpty) return 0;
    if (_inFlight.length + operations.length > _maxConcurrent) {
      throw StateError(
        'Would exceed max concurrent operations: '
        '${_inFlight.length} + ${operations.length} > $_maxConcurrent',
      );
    }

    final iocbArray = calloc<ffi.Pointer<aio_ffi.iocb>>(operations.length);
    try {
      for (var i = 0; i < operations.length; i++) {
        iocbArray[i] = operations[i].iocb;
        _inFlight[operations[i].id] = operations[i];
      }

      final result = AioBindings.instance.io_submit(
        _handle,
        operations.length,
        iocbArray,
      );

      if (result < 0) {
        // Remove from tracking on submit failure
        for (final op in operations) {
          _inFlight.remove(op.id);
        }
        throw Errno.toOSError(-result, 'Failed to submit operations');
      }

      // Handle partial submission
      if (result < operations.length) {
        for (var i = result; i < operations.length; i++) {
          _inFlight.remove(operations[i].id);
        }
      }

      return result;
    } finally {
      calloc.free(iocbArray);
    }
  }

  /// Get completed operations - blocks up to timeout
  List<CompletedOperation> getCompletions({
    int minEvents = 0,
    int? maxEvents,
    Duration? timeout,
  }) {
    _checkNotDisposed();

    final max = maxEvents ?? _maxConcurrent;
    if (minEvents < 0 || minEvents > max) {
      throw ArgumentError('minEvents must be between 0 and $max');
    }

    final eventsArray = calloc<io_event>(max);
    ffi.Pointer<timespec> timeoutPtr = ffi.nullptr;

    try {
      if (timeout != null) {
        timeoutPtr = calloc<timespec>();
        final seconds = timeout.inMicroseconds / Duration.microsecondsPerSecond;
        timeoutPtr.ref.tv_sec = seconds.floor();
        timeoutPtr.ref.tv_nsec = ((seconds - timeoutPtr.ref.tv_sec) * 1e9)
            .floor();
      }

      final result = AioBindings.instance.io_getevents(
        _handle,
        minEvents,
        max,
        eventsArray,
        timeoutPtr,
      );

      if (result < 0) {
        throw Errno.toOSError(-result, 'Failed to get events');
      }

      final completions = <CompletedOperation>[];
      for (var i = 0; i < result; i++) {
        final nativeEvent = eventsArray[i];
        final opId = OperationId(nativeEvent.data.address);
        final tracked = _inFlight.remove(opId);

        if (tracked != null) {
          final bytesTransferred = nativeEvent.res;
          final errorCode = bytesTransferred < 0 ? -bytesTransferred : 0;

          completions.add(
            CompletedOperation(
              operation: tracked,
              bytesTransferred: bytesTransferred >= 0 ? bytesTransferred : 0,
              errorCode: errorCode,
            ),
          );
        }
      }

      return completions;
    } catch (err, st) {
      log?.error('Unexpected error in getCompletions', err, st);
      rethrow;
    } finally {
      calloc.free(eventsArray);
      if (timeoutPtr != ffi.nullptr) calloc.free(timeoutPtr);
    }
  }

  /// Cancels all in-flight operations.
  ///
  /// Note: This does not inform the kernel of the cancellation, but removes
  /// them from local tracking and frees their native control blocks.
  void cancelAll() {
    _checkNotDisposed();

    for (final op in _inFlight.values) {
      op.free();
    }
    _inFlight.clear();
  }

  /// Disposes this [AioContext] and releases all associated native resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    // Clean up any remaining operations
    for (final op in _inFlight.values) {
      op.free();
    }
    _inFlight.clear();

    final result = AioBindings.instance.io_destroy(_handle);
    if (result != 0) {
      log?.warn(
        'io_destroy returned error code $result (${Errno.describe(result)})',
      );
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('AioContext has been disposed');
    }
  }
}

/// Represents the result of a completed AIO operation.
@immutable
final class CompletedOperation {
  /// Creates a new [CompletedOperation].
  const CompletedOperation({
    required this.operation,
    required this.bytesTransferred,
    required this.errorCode,
  });

  /// The original operation that completed.
  final TrackedOperation operation;

  /// The number of bytes successfully transferred.
  final int bytesTransferred;

  /// The error code, if any (0 indicates success).
  final int errorCode;

  /// Whether the operation succeeded.
  bool get isSuccess => errorCode == 0;

  /// Whether the end-of-file was reached during the operation.
  bool get isEof => isSuccess && bytesTransferred == 0;

  /// An [OSError] representation of the result, or `null` if the operation
  /// was successful.
  OSError? get error => isSuccess ? null : OSError('I/O error', errorCode);

  /// Throws an [OSError] if the operation failed.
  void throwIfError() {
    if (!isSuccess) {
      throw Errno.toOSError(errorCode, 'I/O operation failed');
    }
  }
}
