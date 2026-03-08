import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import '../errno/errno.dart';
import 'libaio.ffi.dart' as ffi_aio;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------
/// FFI bindings for Linux kernel AIO, loaded from libaio.so.
final libaio = ffi_aio.Aio(ffi.DynamicLibrary.open('libaio.so'));


/// A completed AIO event: opaque operation id and signed kernel result.
///
/// [res] is positive (bytes transferred), zero (USB EOF / disconnect), or
/// negative (−errno).
typedef AioCompletion = (int opId, int res);

/// Thrown when a `libaio` syscall returns an error.
///
/// [errno] is the raw Linux error number. [message] is a human-readable
/// description built from [Errno.toOSError].
final class LibaioException implements Exception {
  const LibaioException(this.message, this.errno);

  factory LibaioException.fromErrno(int errno, String op) {
    final osError = Errno.toOSError(errno, op);
    return LibaioException('$osError', errno);
  }

  final String message;
  final int errno;

  @override
  String toString() => 'LibaioException: $message';
}

// ---------------------------------------------------------------------------
// Iocb
// ---------------------------------------------------------------------------

/// Owning wrapper around a native `iocb` allocation.
///
/// Factory constructors prepare the struct for a read or write operation.
/// Call [free] when the kernel has finished with the iocb (i.e. inside the
/// `whenComplete` callback of `AioContext.submit`).
final class Iocb {
  Iocb._() : _ptr = calloc<ffi_aio.iocb>();

  /// Prepares a read iocb: reads [len] bytes from [fd] into [buf].
  factory Iocb.read(int fd, ffi.Pointer<ffi.Uint8> buf, int len) {
    final iocb = Iocb._();
    iocb._ptr.ref
      ..aio_fildes = fd
      ..aio_lio_opcode =
          0 // IOCB_CMD_PREAD
      ..data = ffi.Pointer.fromAddress(iocb.address)
      ..u.c.buf = buf.cast()
      ..u.c.nbytes = len
      ..u.c.offset = 0; // USB endpoints are not seekable
    return iocb;
  }

  /// Prepares a write iocb: writes [len] bytes from [buf] to [fd].
  factory Iocb.write(int fd, ffi.Pointer<ffi.Uint8> buf, int len) {
    final iocb = Iocb._();
    iocb._ptr.ref
      ..aio_fildes = fd
      ..aio_lio_opcode =
          1 // IOCB_CMD_PWRITE
      ..data = ffi.Pointer.fromAddress(iocb.address)
      ..u.c.buf = buf.cast()
      ..u.c.nbytes = len
      ..u.c.offset = 0;
    return iocb;
  }

  final ffi.Pointer<ffi_aio.iocb> _ptr;

  /// Address of the native iocb — used as an opaque operation identifier.
  int get address => _ptr.address;

  /// Wires the completion [eventfd] into this iocb so the kernel posts to it
  /// when the operation finishes (IOCB_FLAG_RESFD).
  void setResfd(int efd) {
    _ptr.ref
      ..u.c.resfd = efd
      ..u.c.flags = _ptr.ref.u.c.flags | _iocbFlagResfd;
  }

  /// Releases the native memory. Must be called exactly once per [Iocb].
  void free() => calloc.free(_ptr);

  static const int _iocbFlagResfd = 1 << 0;
}

// ---------------------------------------------------------------------------
// Libaio
// ---------------------------------------------------------------------------

/// Thin Dart wrapper over `libaio.so`.
///
/// One instance is needed per isolate — [ffi.DynamicLibrary] is not
/// transferable, so the watcher isolate creates its own instance.
///
/// AIO context handles are passed as plain [int] addresses so they cross
/// isolate boundaries without any wrapper object.
final class Libaio {
  Libaio() : _lib = ffi_aio.Aio(ffi.DynamicLibrary.open('libaio.so'));

  final ffi_aio.Aio _lib;

  // --- context lifecycle ---------------------------------------------------

  /// Creates a kernel AIO context and returns its address.
  ///
  /// Throws [LibaioException] on failure.
  int setup(int maxEvents) {
    final ctxp = calloc<ffi.Pointer<ffi_aio.io_context>>()..value = ffi.nullptr;
    try {
      final res = _lib.io_setup(maxEvents, ctxp);
      if (res != 0) throw _kernelException(-res, 'io_setup');
      return ctxp.value.address;
    } finally {
      calloc.free(ctxp);
    }
  }

  /// Destroys the kernel AIO context at [ctxAddr].
  void destroy(int ctxAddr) => _lib.io_destroy(_ctx(ctxAddr));

  // --- submission ----------------------------------------------------------

  /// Submits [batch] to the kernel AIO context at [ctxAddr].
  ///
  /// Uses a grown-only internal scratch array to avoid per-call allocation.
  /// Returns the number of iocbs accepted (negative value = −errno).
  int submit(int ctxAddr, List<Iocb> batch) {
    final n = batch.length;
    if (n == 0) return 0;

    _growArr(n);
    for (var i = 0; i < n; i++) {
      _arr[i] = batch[i]._ptr;
    }

    return _lib.io_submit(_ctx(ctxAddr), n, _arr);
  }

  // --- harvesting ----------------------------------------------------------

  /// Harvests up to [max] completed events from [ctxAddr].
  ///
  /// Returns an empty list when no events are ready (non-blocking: min_nr=0).
  /// The list is freshly allocated per call — callers may hold it.
  List<AioCompletion> getevents(int ctxAddr, int max) {
    _growEventBuf(max);

    final n = _lib.io_getevents(_ctx(ctxAddr), 0, max, _eventBuf, ffi.nullptr);
    if (n <= 0) return const [];

    return List<AioCompletion>.generate(n, (i) {
      final evt = _eventBuf[i];
      return (evt.data.address, evt.res.toSigned(64));
    }, growable: false);
  }

  // --- internal helpers ----------------------------------------------------

  ffi.Pointer<ffi_aio.io_context> _ctx(int addr) =>
      ffi.Pointer<ffi_aio.io_context>.fromAddress(addr);

  // Grown-only scratch array for io_submit batches.
  ffi.Pointer<ffi.Pointer<ffi_aio.iocb>> _arr = ffi.Pointer.fromAddress(0);
  int _arrCap = 0;

  void _growArr(int n) {
    if (n <= _arrCap) return;
    if (_arrCap > 0) calloc.free(_arr);
    _arr = calloc<ffi.Pointer<ffi_aio.iocb>>(n);
    _arrCap = n;
  }

  // Grown-only buffer for io_getevents results.
  ffi.Pointer<ffi_aio.io_event> _eventBuf = ffi.Pointer.fromAddress(0);
  int _eventBufCap = 0;

  void _growEventBuf(int n) {
    if (n <= _eventBufCap) return;
    if (_eventBufCap > 0) calloc.free(_eventBuf);
    _eventBuf = calloc<ffi_aio.io_event>(n);
    _eventBufCap = n;
  }

  /// Releases the scratch arrays. Call when the surrounding context is torn down.
  void dispose() {
    if (_arrCap > 0) {
      calloc.free(_arr);
      _arrCap = 0;
    }
    if (_eventBufCap > 0) {
      calloc.free(_eventBuf);
      _eventBufCap = 0;
    }
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

Never _kernelException(int errno, String op) =>
    throw LibaioException.fromErrno(errno, op);
