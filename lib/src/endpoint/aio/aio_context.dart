import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:using/using.dart';

import '/src/platform/platform.dart';
import '/src/platform/epoll/epoll.dart';
import '/src/platform/libaio/libaio.ffi.dart';
import 'exceptions.dart';

// ---------------------------------------------------------------------------
// Watcher isolate
// ---------------------------------------------------------------------------

/// Payload exchanged between [_watcherEntry] and the main isolate.
///
/// The watcher sends back the raw pointer address of the iocb that completed
/// together with the kernel result (positive = bytes, negative = −errno).
typedef _CompletionMsg = (int opId, int res);

/// Watcher isolate entry-point.
///
/// Blocks on `epoll_wait`, drains the completion eventfd, harvests completed
/// AIO events with `io_getevents`, and forwards [_CompletionMsg] records to
/// the main isolate.  Exits cleanly when the shutdown eventfd fires.
void _watcherEntry(_WatcherArgs args) {
  final libaio = Aio(ffi.DynamicLibrary.open('libaio.so'));
  final ctx = ffi.Pointer<io_context>.fromAddress(args.ctxAddr);

  // Reuse a single native event buffer for the lifetime of the isolate.
  const maxHarvest = 128;
  final buf = calloc<io_event>(maxHarvest);

  try {
    while (true) {
      final ready = Epoll.wait(args.epfd, maxEvents: 2, timeoutMs: -1);

      for (final (:data, events: _) in ready) {
        if (data == args.shutdownFd) {
          try {
            Epoll.eventfdRead(args.shutdownFd);
          } catch (_) {}
          return;
        }

        if (data != args.efd) continue;

        // Drain the counter — value unused, we harvest via io_getevents.
        try {
          Epoll.eventfdRead(args.efd);
        } catch (_) {}

        // Harvest in a loop: a single epoll wake may cover many completions.
        int n;
        while ((n = libaio.io_getevents(ctx, 0, maxHarvest, buf, ffi.nullptr)) >
            0) {
          for (var i = 0; i < n; i++) {
            final evt = buf[i];
            args.sendPort.send((
              evt.data.address,
              evt.res.toSigned(64), // UnsignedLong → signed for errno check
            ));
          }
        }
      }
    }
  } finally {
    calloc.free(buf);
  }
}

final class _WatcherArgs {
  const _WatcherArgs({
    required this.epfd,
    required this.efd,
    required this.ctxAddr,
    required this.shutdownFd,
    required this.sendPort,
  });

  final int epfd;
  final int efd;
  final int ctxAddr;
  final int shutdownFd;
  final SendPort sendPort;
}

// ---------------------------------------------------------------------------
// AioContext
// ---------------------------------------------------------------------------

/// Kernel AIO context with an event-driven completion loop.
///
/// A background [Isolate] blocks on `epoll_wait`; the kernel signals the
/// completion `eventfd` (stored in every submitted `iocb`) when an operation
/// finishes, waking the isolate with zero busy-waiting.
///
/// Multiple iocbs submitted within the same event-loop turn are batched into a
/// single `io_submit` syscall via a microtask-scheduled flush.
///
/// **Lifecycle**
/// ```dart
/// final ctx = AioContext(128);
/// final bytes = await ctx.submit(iocb, opId);
/// ctx.release();
/// ```
final class AioContext with Releasable {
  AioContext(int maxEvents) {
    // 1. Kernel AIO context.
    final ctxp = calloc<ffi.Pointer<io_context>>()..value = ffi.nullptr;
    try {
      final res = libaio.io_setup(maxEvents, ctxp);
      if (res != 0) throw LibaioException.fromErrno(-res, 'io_setup');
      _ctx = ctxp.value;
    } finally {
      calloc.free(ctxp);
    }

    // 2. Completion eventfd — posted to by the kernel on iocb completion.
    _efd = Epoll.eventfd(closeOnExec: true);

    // 3. Shutdown eventfd — written from [release] for a clean isolate exit.
    _shutdownFd = Epoll.eventfd(closeOnExec: true);

    // 4. epoll instance watching both eventfds.
    _epfd = Epoll.create();
    Epoll.add(_epfd, _efd, EPOLLIN, data: _efd);
    Epoll.add(_epfd, _shutdownFd, EPOLLIN, data: _shutdownFd);

    // 5. Watcher isolate.
    _completionPort = ReceivePort()..listen(_onCompletion);
    Isolate.spawn(
      _watcherEntry,
      _WatcherArgs(
        epfd: _epfd,
        efd: _efd,
        ctxAddr: _ctx.address,
        shutdownFd: _shutdownFd,
        sendPort: _completionPort.sendPort,
      ),
      debugName: 'AioContext.watcher',
    ).then((isolate) => _watcher = isolate);
  }

  late final ffi.Pointer<io_context> _ctx;
  late final int _efd;
  late final int _shutdownFd;
  late final int _epfd;
  late final ReceivePort _completionPort;

  /// Handle to the watcher isolate, set asynchronously after spawn completes.
  /// Used as a last-resort kill if the shutdown eventfd signal is lost.
  Isolate? _watcher;

  /// opId → completer for every in-flight kernel operation.
  final Map<int, Completer<int>> _pending = {};

  /// Queue of iocbs accumulated within the current event-loop turn.
  ///
  /// Kept as a plain [List] that is handed directly to [_flushQueue] without
  /// copying; a fresh list is swapped in atomically at flush time.
  List<ffi.Pointer<iocb>> _queue = [];

  /// Pre-allocated native pointer array reused across flushes to avoid
  /// per-flush [calloc] / [free] overhead.
  ///
  /// Grown (but never shrunk) as the batch size increases.
  ///
  /// null sentinel; allocated on first flush
  ffi.Pointer<ffi.Pointer<iocb>> _arr = ffi.Pointer.fromAddress(0);
  int _arrCap = 0;

  // ---------------------------------------------------------------------------
  // Completion handler
  // ---------------------------------------------------------------------------

  void _onCompletion(dynamic msg) {
    if (isReleased) return;
    final (opId, res) = msg as _CompletionMsg;
    final completer = _pending.remove(opId);
    if (completer == null) return;

    if (res >= 0) {
      completer.complete(res);
    } else {
      final errno = -res;
      if (_usbDisconnectErrnos.contains(errno)) {
        completer.complete(0); // treat as EOF
      } else {
        completer.completeError(LibaioException.fromErrno(errno, 'io_event'));
      }
    }
  }

  /// O(1) membership test — a [Set] instead of a [List].
  static const _usbDisconnectErrnos = {
    Errno.enxio,
    Errno.enodev,
    Errno.epipe,
    Errno.econnreset,
    Errno.eshutdown,
  };

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// IOCB_FLAG_RESFD — instructs the kernel to post to [iocb.u.c.resfd].
  static const int _iocbFlagResfd = 1 << 0;

  /// Enqueues [op] for the next batched `io_submit` call and returns a
  /// [Future] that resolves with the number of bytes transferred (or 0 on USB
  /// EOF / disconnect).
  ///
  /// Throws [AioDisposedException] if called after [release].
  Future<int> submit(ffi.Pointer<iocb> op, int opId) {
    if (isReleased) throw const AioDisposedException();

    op.ref
      ..u.c.resfd = _efd
      ..u.c.flags = op.ref.u.c.flags | _iocbFlagResfd;

    final completer = Completer<int>();
    _pending[opId] = completer;
    _queue.add(op);

    // Schedule one microtask flush per event-loop turn regardless of how many
    // ops are enqueued — they all get batched into a single io_submit call.
    if (_queue.length == 1) scheduleMicrotask(_flushQueue);

    return completer.future;
  }

  /// Submits all queued iocbs in one `io_submit` syscall.
  ///
  /// Swaps out [_queue] atomically so any ops enqueued during the flush
  /// (unlikely but possible) are deferred to the next microtask.
  ///
  /// The native pointer array [_arr] is grown-only and reused across calls,
  /// eliminating per-flush allocation for steady-state batch sizes.
  void _flushQueue() {
    if (_queue.isEmpty || isReleased) return;

    // Atomic swap — take ownership of the current batch.
    final batch = _queue;
    _queue = [];

    final n = batch.length;

    // Grow the reusable native array if needed (never shrunk).
    if (n > _arrCap) {
      if (_arrCap > 0) calloc.free(_arr);
      _arr = calloc<ffi.Pointer<iocb>>(n);
      _arrCap = n;
    }

    for (var i = 0; i < n; i++) {
      _arr[i] = batch[i];
    }

    final submitted = libaio.io_submit(_ctx, n, _arr);

    if (submitted == n) return; // fast path — everything accepted

    if (submitted < 0) {
      // Total failure: fail every op in this batch.
      final errno = -submitted;
      for (var i = 0; i < n; i++) {
        _failOp(batch[i], errno, 'io_submit');
      }
    } else {
      // Partial submission: fail only the tail the kernel rejected.
      for (var i = submitted; i < n; i++) {
        _failOp(batch[i], Errno.eagain, 'io_submit: partial submission');
      }
    }
  }

  void _failOp(ffi.Pointer<iocb> op, int errno, String message) {
    final c = _pending.remove(op.ref.data.address);
    c?.completeError(LibaioException.fromErrno(errno, message));
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void release() {
    if (isReleased) return;
    super.release();

    // Ask the watcher isolate to exit via the shutdown eventfd.
    try {
      Epoll.eventfdWrite(_shutdownFd, 1);
    } catch (_) {}

    // Last-resort kill if the isolate handle is already available.
    _watcher?.kill(priority: Isolate.beforeNextEvent);

    // Fail all in-flight operations.
    for (final c in _pending.values) {
      c.completeError(const AioDisposedException());
    }
    _pending.clear();
    _queue.clear();

    _completionPort.close();

    // Free the reusable native array.
    if (_arrCap > 0) {
      calloc.free(_arr);
      _arrCap = 0;
    }

    // Tear down kernel resources — AIO context before its eventfd.
    libaio.io_destroy(_ctx);
    Unistd.close(_efd);
    Unistd.close(_shutdownFd);
    Unistd.close(_epfd);
  }
}
