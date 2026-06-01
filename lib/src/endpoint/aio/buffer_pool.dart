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
    _indexOf = {for (var i = 0; i < poolSize; i++) _buffers[i].address: i};
    _free = .generate(poolSize, (i) => i);
    _isFree = .filled(poolSize, true);
    _semaphore = _Semaphore(poolSize);
  }

  final int bufferSize;
  final int poolSize;
  late final List<ffi.Pointer<ffi.Uint8>> _buffers;

  /// Maps a buffer's native address back to its pool index, giving [free] an
  /// O(1) lookup instead of a linear scan of [_buffers].
  late final Map<int, int> _indexOf;

  /// Stack of currently-available buffer indices.
  late final List<int> _free;

  /// Per-index membership flag, guarding against double-free in O(1).
  late final List<bool> _isFree;

  late final _Semaphore _semaphore;

  int get available => _free.length;

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
    return _buffers[_take()];
  }

  /// Tries to acquire a buffer immediately.  Returns `null` if the pool is
  /// exhausted or has been released.  Write paths should prefer [acquireAsync].
  ffi.Pointer<ffi.Uint8>? acquire() {
    if (isReleased || !_semaphore.tryAcquire()) return null;
    return _buffers[_take()];
  }

  /// Pops the next free index off the stack and marks it in use.
  int _take() {
    final idx = _free.removeLast();
    _isFree[idx] = false;
    return idx;
  }

  /// Returns [ptr] to the pool and wakes the next suspended [acquireAsync]
  /// waiter, if any.
  void free(ffi.Pointer<ffi.Uint8> ptr) {
    final idx = _indexOf[ptr.address];
    if (idx != null && !_isFree[idx]) {
      _isFree[idx] = true;
      _free.add(idx);
      _semaphore.release(); // wake a waiter *after* the slot is re-listed
    }
  }

  @override
  void release() {
    if (isReleased) return;
    super.release();
    // Unblock any callers suspended in acquireAsync so they do not hang.
    _semaphore.cancelAll(StateError('BufferPool has been released'));
    _buffers.forEach(calloc.free);
  }
}
