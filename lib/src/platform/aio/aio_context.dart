import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:using/using.dart';

import '/src/logger/logger.dart';
import '/src/platform/errno/errno.dart';
import 'aio.ffi.dart';
import 'aio_bindings.dart';
import 'aio_reader.dart';
import 'aio_writer.dart';

// ============================================================================
// Configuration
// ============================================================================

/// Configuration for AIO operations.
///
/// Defines buffer size, concurrency limits, and polling intervals for both
/// [AioReader] and [AioWriter] instances.
///
/// Example:
///
/// ```dart
/// final config = AioConfig(
///   bufferSize: 32768,
///   maxConcurrent: 8,
///   interval: Duration(milliseconds: 2),
/// );
/// ```
final class AioConfig {
  /// Creates an [AioConfig] with the specified parameters.
  ///
  /// All parameters have sensible defaults optimized for typical USB gadget
  /// I/O workloads.
  ///
  /// Throws [ArgumentError] if any parameter is invalid.
  const AioConfig({
    this.bufferSize = 16384,
    this.maxConcurrent = 4,
    this.interval = const Duration(milliseconds: 1),
  }) : assert(
         bufferSize > 0 && bufferSize <= 1048576,
         'bufferSize must be between 1 and 1048576 bytes',
       ),
       assert(
         maxConcurrent > 0 && maxConcurrent <= 256,
         'maxConcurrent must be between 1 and 256',
       );

  /// Size of each I/O buffer in bytes.
  ///
  /// Default: 16384 (16 KiB)
  final int bufferSize;

  /// Maximum number of concurrent operations.
  ///
  /// Default: 4
  final int maxConcurrent;

  /// Interval for polling completions.
  ///
  /// Default: 1ms
  final Duration interval;
}

// ============================================================================
// Resource Pool - Reusable buffers
// ============================================================================

/// A pool of reusable memory buffers for AIO operations.
///
/// Manages native memory buffers allocated via `calloc` to avoid repeated
/// allocations and deallocations during I/O operations. Implements [Releasable]
/// to ensure proper cleanup of native resources.
///
/// Example:
///
/// ```dart
/// final pool = BufferPool(16384, 4);
/// final buffer = pool.acquire();
/// if (buffer != null) {
///   // Use buffer...
///   pool.releaseBuffer(buffer);
/// }
/// pool.release();
/// ```
final class BufferPool with Releasable {
  /// Creates a new [BufferPool] with [poolSize] buffers of [bufferSize] bytes each.
  BufferPool(this.bufferSize, this.poolSize) {
    _pool = .generate(poolSize, (_) => calloc<ffi.Uint8>(bufferSize));
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
    super.release();
    assert(
      _inUse.isEmpty,
      'BufferPool released while ${_inUse.length} buffers are still in use',
    );
    _pool
      ..forEach(calloc.free)
      ..clear();
    _inUse.clear();
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
///
/// Used to track operations through their lifecycle from submission to
/// completion. The [value] corresponds to the operation's position in the
/// submission sequence.
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
///
/// Contains all the metadata and native resources associated with a pending
/// I/O operation. The [iocb] pointer must be freed when the operation completes
/// or is cancelled.
@immutable
final class TrackedOperation {
  /// Creates a new [TrackedOperation].
  ///
  /// All parameters are required except [userData], which can be used to attach
  /// arbitrary application data to the operation.
  const TrackedOperation({
    required this.id,
    required this.type,
    required this.buffer,
    required this.size,
    required this.offset,
    required this.block,
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
  final ffi.Pointer<iocb> block;

  /// Optional opaque user data associated with the operation.
  final Object? userData;

  /// Frees the native resources associated with this operation.
  void free() {
    calloc.free(block);
  }
}

// ============================================================================
// AIO Context - Event-driven completion handling
// ============================================================================

/// A context for managed Linux kernel AIO operations.
///
/// Encapsulates a Linux kernel `io_context` and provides high-level methods for
/// submitting I/O operations and retrieving completion events. Manages the
/// lifecycle of in-flight operations and ensures proper cleanup of native
/// resources.
///
/// Example:
///
/// ```dart
/// final context = AioContext(maxConcurrent: 4);
/// final operations = [/* ... */];
/// context.submit(operations);
/// final completions = context.getCompletions();
/// context.release();
/// ```
final class AioContext with PlatformLogger, Releasable {
  /// Creates an [AioContext] capable of handling up to [maxConcurrent]
  /// pending operations.
  ///
  /// The [maxConcurrent] parameter must be between 1 and 65536.
  ///
  /// Throws [ArgumentError] if [maxConcurrent] is out of range.
  /// Throws [OSError] if the kernel fails to create the AIO context.
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

  /// The maximum number of concurrent operations allowed in this context.
  int get maxConcurrent => _maxConcurrent;

  /// The number of operations currently in-flight.
  int get inFlightCount => _inFlight.length;

  /// Whether a new operation can be submitted without exceeding [maxConcurrent].
  bool get canSubmit => _inFlight.length < _maxConcurrent;

  /// Submits a batch of operations to the kernel.
  ///
  /// Returns the number of operations successfully submitted. If the return
  /// value is less than `operations.length`, only the first N operations were
  /// submitted.
  ///
  /// Throws [StateError] if the context is disposed or if submitting would
  /// exceed [maxConcurrent].
  /// Throws [OSError] if the kernel rejects the submission.
  int submit(List<TrackedOperation> operations) {
    if (isReleased) {
      throw StateError('Cannot submit operations to a released AioContext');
    }

    if (operations.isEmpty) return 0;
    if (_inFlight.length + operations.length > _maxConcurrent) {
      throw StateError(
        'Would exceed max concurrent operations: '
        '${_inFlight.length} + ${operations.length} > $_maxConcurrent',
      );
    }

    final iocbArray = calloc<ffi.Pointer<iocb>>(operations.length);
    try {
      for (var i = 0; i < operations.length; i++) {
        iocbArray[i] = operations[i].block;
        _inFlight[operations[i].id] = operations[i];
      }

      final result = AioBindings.instance.io_submit(
        _handle,
        operations.length,
        iocbArray,
      );

      if (result < 0) {
        for (final op in operations) {
          _inFlight.remove(op.id);
          op.free();
        }
        throw Errno.toOSError(-result, 'Failed to submit operations');
      }

      // Handle partial submission
      if (result < operations.length) {
        for (var i = result; i < operations.length; i++) {
          final op = operations[i];
          _inFlight.remove(op.id);
          op.free();
        }
      }

      return result;
    } finally {
      calloc.free(iocbArray);
    }
  }

  /// Retrieves completed operations from the kernel.
  ///
  /// Blocks until at least [minEvents] operations complete or [timeout] expires.
  /// Returns up to [maxEvents] completions (defaults to [maxConcurrent]).
  ///
  /// If [timeout] is `null`, waits indefinitely. If [timeout] is [Duration.zero],
  /// returns immediately with any available completions.
  ///
  /// Throws [ArgumentError] if [minEvents] is invalid.
  /// Throws [OSError] if the kernel call fails.
  List<CompletedOperation> getCompletions({
    int minEvents = 0,
    int? maxEvents,
    Duration? timeout,
  }) {
    if (isReleased) {
      throw StateError('Cannot get completions from a released AioContext');
    }

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
    for (final op in _inFlight.values) {
      op.free();
    }
    _inFlight.clear();
  }

  /// Releases this [AioContext] and frees all associated native resources.
  @override
  void release() {
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

    super.release();
  }
}

/// Represents the result of a completed AIO operation.
///
/// Contains the original operation metadata along with the completion status,
/// including bytes transferred and any error code.
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
}
