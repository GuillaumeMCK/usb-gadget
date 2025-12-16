import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import '/src/logger/logger.dart';
import '../errno/errno.dart';
import 'aio.ffi.dart' hide iocb;
import 'aio.ffi.dart' as aio_ffi show iocb;

class AioBindings {
  AioBindings._();

  static final Aio _instance = Aio(ffi.DynamicLibrary.open('libaio.so'));

  static Aio get instance => _instance;
}

// ============================================================================
// Resource Pool - Reusable buffers
// ============================================================================

final class BufferPool {
  BufferPool(this.bufferSize, this.poolSize) {
    _pool = List.generate(poolSize, (_) => calloc<ffi.Uint8>(bufferSize));
  }

  final int bufferSize;
  final int poolSize;
  late final List<ffi.Pointer<ffi.Uint8>> _pool;
  final Set<ffi.Pointer<ffi.Uint8>> _inUse = {};

  ffi.Pointer<ffi.Uint8>? acquire() {
    final available = _pool.where((p) => !_inUse.contains(p));
    if (available.isEmpty) return null;

    final buffer = available.first;
    _inUse.add(buffer);
    return buffer;
  }

  void release(ffi.Pointer<ffi.Uint8> buffer) {
    _inUse.remove(buffer);
  }

  void dispose() {
    _pool
      ..forEach(calloc.free)
      ..clear();
    _inUse.clear();
  }

  int get available => poolSize - _inUse.length;

  int get inUse => _inUse.length;
}

// ============================================================================
// Operation Tracking - Proper lifecycle management
// ============================================================================

@immutable
final class OperationId {
  const OperationId(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is OperationId && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

enum OperationType { read, write }

final class TrackedOperation {
  TrackedOperation({
    required this.id,
    required this.type,
    required this.buffer,
    required this.size,
    required this.offset,
    required this.iocb,
    this.userData,
  });

  final OperationId id;
  final OperationType type;
  final ffi.Pointer<ffi.Uint8> buffer;
  final int size;
  final int offset;
  final ffi.Pointer<aio_ffi.iocb> iocb;
  final Object? userData;

  void free() {
    calloc.free(iocb);
  }
}

// ============================================================================
// AIO Context - Event-driven completion handling
// ============================================================================

final class AioContext with PlatformLogger {
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

  int get maxConcurrent => _maxConcurrent;

  int get inFlightCount => _inFlight.length;

  bool get isDisposed => _disposed;

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

  /// Cancel all in-flight operations
  void cancelAll() {
    _checkNotDisposed();

    for (final op in _inFlight.values) {
      op.free();
    }
    _inFlight.clear();
  }

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

@immutable
final class CompletedOperation {
  const CompletedOperation({
    required this.operation,
    required this.bytesTransferred,
    required this.errorCode,
  });

  final TrackedOperation operation;
  final int bytesTransferred;
  final int errorCode;

  bool get isSuccess => errorCode == 0;

  bool get isEof => isSuccess && bytesTransferred == 0;

  OSError? get error => isSuccess ? null : OSError('I/O error', errorCode);

  void throwIfError() {
    if (!isSuccess) {
      throw Errno.toOSError(errorCode, 'I/O operation failed');
    }
  }
}
