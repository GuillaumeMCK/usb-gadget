import 'dart:async';
import 'dart:collection' show Queue;
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:using/using.dart';

/// A simple async semaphore that serialises access to a fixed number of
/// permits.  Waiters are queued in FIFO order and woken one-at-a-time as
/// permits are released, providing natural backpressure without busy-waiting.
final class _Semaphore {
  _Semaphore(int permits) : _permits = permits;

  int _permits;
  final Queue<Completer<void>> _waiters = Queue();

  /// Acquires one permit, suspending asynchronously if none are available.
  Future<void> acquire() {
    if (_permits > 0) {
      _permits--;
      return Future.value();
    }
    final c = Completer<void>.sync();
    _waiters.add(c);
    return c.future;
  }

  /// Tries to acquire one permit immediately.
  /// Returns true and decrements the counter when a permit is available;
  /// returns false and leaves the queue unchanged when it is not.
  bool tryAcquire() {
    if (_permits > 0) {
      _permits--;
      return true;
    }
    return false;
  }

  /// Releases one permit and wakes the next waiter, if any.
  void release() {
    if (_waiters.isNotEmpty) {
      // Hand the permit directly to the next waiter — keeps _permits accurate.
      _waiters.removeFirst().complete();
    } else {
      _permits++;
    }
  }

  /// Fails all pending waiters with [error].  Called during disposal so
  /// callers do not hang forever after the pool is torn down.
  void cancelAll(Object error) {
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().completeError(error);
    }
    _permits = 0;
  }
}

/// Buffer pool with backpressure: [acquireAsync] suspends the caller when all
/// buffers are in use and resumes it as soon as one becomes available again.
///
/// The synchronous [acquire] is still available for callers that can tolerate
/// a `null` result (e.g. [AioStream] which simply skips a window-fill cycle),
/// but write paths **must** prefer [acquireAsync] to avoid [AioQueueFullException].
final class BufferPool with Releasable {
  BufferPool(this.bufferSize, this.poolSize) {
    _buffers = .generate(poolSize, (_) => calloc<ffi.Uint8>(bufferSize));
    _available = .generate(poolSize, (i) => i);
    _semaphore = _Semaphore(poolSize);
  }

  final int bufferSize;
  final int poolSize;
  late final List<ffi.Pointer<ffi.Uint8>> _buffers;
  late final List<int> _available;
  late final _Semaphore _semaphore;

  int get available => _available.length;

  /// Acquires a buffer, **suspending** the caller if the pool is temporarily
  /// exhausted.  Resumes as soon as a buffer is returned via [free].
  ///
  /// Throws [StateError] if the pool has been released while waiting.
  Future<ffi.Pointer<ffi.Uint8>> acquireAsync() async {
    if (isReleased) throw StateError('BufferPool has been released');
    await _semaphore
        .acquire(); // Yields until a slot is available or the pool is released.
    if (isReleased) throw StateError('BufferPool released while waiting');
    // The semaphore guarantees a slot is available at this point.
    return _buffers[_available.removeLast()];
  }

  /// Tries to acquire a buffer immediately.  Returns `null` if the pool is
  /// exhausted or has been released.  Write paths should prefer [acquireAsync].
  ffi.Pointer<ffi.Uint8>? acquire() {
    if (isReleased || !_semaphore.tryAcquire()) return null;
    return _buffers[_available.removeLast()];
  }

  /// Returns [ptr] to the pool and wakes the next suspended [acquireAsync]
  /// waiter, if any.
  void free(ffi.Pointer<ffi.Uint8> ptr) {
    final idx = _buffers.indexOf(ptr);
    if (idx != -1 && !_available.contains(idx)) {
      _available.add(idx);
      _semaphore.release(); // wake a waiter *after* the slot is re-listed
    }
  }

  @override
  void release() {
    if (isReleased) return;
    super.release();
    // Unblock any callers suspended in acquireAsync so they do not hang.
    _semaphore.cancelAll(StateError('BufferPool has been released'));
    for (final buf in _buffers) {
      calloc.free(buf);
    }
  }
}
