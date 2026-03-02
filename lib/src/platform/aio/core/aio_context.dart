import 'dart:async';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:using/using.dart';

import '/src/platform/aio/aio.dart';
import '/src/platform/errno/errno.dart';
import '../aio.ffi.dart' as ffi_aio;

/// FFI bindings for Linux kernel AIO, loaded from libaio.so.
final _libaio = ffi_aio.Aio(ffi.DynamicLibrary.open('libaio.so'));

/// Kernel AIO context with event loop.
final class AioContext with Releasable {
  AioContext(
    int maxEvents, [
    this.pollInterval = const Duration(milliseconds: 1),
  ]) {
    final ctxp = calloc<ffi.Pointer<ffi_aio.io_context>>()..value = ffi.nullptr;
    try {
      final res = _libaio.io_setup(maxEvents, ctxp);
      if (res != 0) throw AioKernelException.fromErrno(-res, 'io_setup');
      _ctx = ctxp.value;
    } finally {
      calloc.free(ctxp);
    }
  }

  late final ffi.Pointer<ffi_aio.io_context> _ctx;
  final Map<int, Completer<int>> _pending = {};
  final List<ffi.Pointer<ffi_aio.iocb>> _queue = [];
  final Duration pollInterval;
  Timer? _timer;

  /// Errno values that indicate the USB device is disconnecting or suspended.
  static const _usbDisconnectErrnos = [
    Errno.enxio,
    Errno.enodev,
    Errno.epipe,
    Errno.econnreset,
    Errno.eshutdown,
  ];

  /// Submits an operation and returns when complete.
  Future<int> submit(ffi.Pointer<ffi_aio.iocb> op, int opId) {
    if (isReleased) throw const AioDisposedException();

    final completer = Completer<int>();
    _pending[opId] = completer;
    _queue.add(op);

    _ensureLoop();
    return completer.future;
  }

  void _ensureLoop() {
    _timer ??= .periodic(pollInterval, (_) => _poll());
  }

  void _poll() {
    // Submit queued operations
    while (_queue.isNotEmpty) {
      final batch = _queue.take(32).toList();
      _queue.removeRange(0, batch.length);

      final arr = calloc<ffi.Pointer<ffi_aio.iocb>>(batch.length);
      try {
        for (var i = 0; i < batch.length; i++) {
          arr[i] = batch[i];
        }
        _libaio.io_submit(_ctx, batch.length, arr);
      } finally {
        calloc.free(arr);
      }
    }

    // Retrieve completed events
    if (_pending.isEmpty) {
      _timer?.cancel();
      _timer = null;
      return;
    }

    final events = calloc<ffi_aio.io_event>(128);
    try {
      final n = _libaio.io_getevents(_ctx, 0, 128, events, ffi.nullptr);
      if (n < 0) return;

      for (var i = 0; i < n; i++) {
        final evt = events[i];
        final id = evt.data.address;
        final completer = _pending.remove(id);

        if (completer != null) {
          final res = evt.res;
          if (res >= 0) {
            completer.complete(res);
          } else {
            final errno = -res;
            if (_usbDisconnectErrnos.contains(errno)) {
              // USB suspend / unplug: signal EOF rather than propagating an
              // unhandled error
              completer.complete(0);
            } else {
              completer.completeError(
                AioKernelException.fromErrno(errno, 'io_event'),
              );
            }
          }
        }
      }
    } finally {
      calloc.free(events);
    }
  }

  @override
  void release() {
    if (isReleased) return;
    super.release();

    _timer?.cancel();
    for (final c in _pending.values) {
      c.completeError(const AioDisposedException());
    }
    _pending.clear();
    _queue.clear();

    _libaio.io_destroy(_ctx);
  }
}
