import 'dart:io';
import 'errno.ffi.dart' as errno_ffi;

/// A utility class for working with Linux `errno` values via FFI.
///
/// ## Usage pattern
///
/// The cardinal rule of errno: **read it immediately after the syscall.**
/// Any intervening function call — even innocent-looking ones — can
/// overwrite it. Use [call] or [capture] to guarantee safe reads:
///
/// ```dart
/// // Safe: errno is captured atomically with the native call result.
/// final fd = Errno.call(() => open(path, O_RDONLY));
///
/// // Safe: inspect both the result and errno yourself.
/// final (result, code) = Errno.capture(() => read(fd, buf, len));
/// if (result < 0) { ... }
/// ```
///
/// Do **not** do this:
/// ```dart
/// final result = nativeCall();
/// // ← anything here can clobber errno
/// final code = Errno.current; // may be wrong
/// ```
///
/// ## Platform
///
/// Linux only. Errno values mirror `asm-generic/errno-base.h` and
/// `asm-generic/errno.h`.
// ---------------------------------------------------------------------------
// Standard POSIX / Generic Errors (1–40)
// ---------------------------------------------------------------------------

/// Operation not permitted (EPERM) — 1
const int eperm = 1;

/// No such file or directory (ENOENT) — 2
const int enoent = 2;

/// No such process (ESRCH) — 3
const int esrch = 3;

/// Interrupted system call (EINTR) — 4
///
/// Most blocking syscalls return EINTR when a signal is delivered.
const int eintr = 4;

/// I/O error (EIO) — 5
const int eio = 5;

/// No such device or address (ENXIO) — 6
const int enxio = 6;

/// Argument list too long (E2BIG) — 7
const int e2big = 7;

/// Exec format error (ENOEXEC) — 8
const int enoexec = 8;

/// Bad file descriptor (EBADF) — 9
const int ebadf = 9;

/// No child processes (ECHILD) — 10
const int echild = 10;

/// Resource temporarily unavailable (EAGAIN / EWOULDBLOCK) — 11
///
/// On Linux, EWOULDBLOCK is an alias for EAGAIN (both equal 11).
const int eagain = 11;

/// EWOULDBLOCK is an alias for [eagain] on Linux.
const int ewouldblock = eagain;

/// Out of memory (ENOMEM) — 12
const int enomem = 12;

/// Permission denied (EACCES) — 13
const int eacces = 13;

/// Bad address (EFAULT) — 14
const int efault = 14;

/// Block device required (ENOTBLK) — 15
const int enotblk = 15;

/// Device or resource busy (EBUSY) — 16
const int ebusy = 16;

/// File exists (EEXIST) — 17
const int eexist = 17;

/// Cross-device link (EXDEV) — 18
const int exdev = 18;

/// No such device (ENODEV) — 19
const int enodev = 19;

/// Not a directory (ENOTDIR) — 20
const int enotdir = 20;

/// Is a directory (EISDIR) — 21
const int eisdir = 21;

/// Invalid argument (EINVAL) — 22
const int einval = 22;

/// File table overflow (ENFILE) — 23
const int enfile = 23;

/// Too many open files (EMFILE) — 24
const int emfile = 24;

/// Inappropriate ioctl for device (ENOTTY) — 25
const int enotty = 25;

/// Text file busy (ETXTBSY) — 26
const int etxtbsy = 26;

/// File too large (EFBIG) — 27
const int efbig = 27;

/// No space left on device (ENOSPC) — 28
const int enospc = 28;

/// Illegal seek (ESPIPE) — 29
const int espipe = 29;

/// Read-only file system (EROFS) — 30
const int erofs = 30;

/// Too many links (EMLINK) — 31
const int emlink = 31;

/// Broken pipe (EPIPE) — 32
const int epipe = 32;

/// Math argument out of domain (EDOM) — 33
const int edom = 33;

/// Math result not representable (ERANGE) — 34
const int erange = 34;

/// Resource deadlock avoided (EDEADLK) — 35
const int edeadlk = 35;

/// File name too long (ENAMETOOLONG) — 36
const int enametoolong = 36;

/// No locks available (ENOLCK) — 37
const int enolck = 37;

/// Function not implemented (ENOSYS) — 38
const int enosys = 38;

/// Directory not empty (ENOTEMPTY) — 39
const int enotempty = 39;

/// Too many symbolic links (ELOOP) — 40
const int eloop = 40;

// ---------------------------------------------------------------------------
// Linux-specific / Legacy STREAMS Errors (45–57)
// ---------------------------------------------------------------------------

/// Level 2 not synchronized (EL2NSYNC) — 45
const int el2nsync = 45;

/// Level 3 halted (EL3HLT) — 46
const int el3hlt = 46;

/// Level 3 reset (EL3RST) — 47
const int el3rst = 47;

/// Link number out of range (ELNRNG) — 48
const int elnrng = 48;

/// Protocol driver not attached (EUNATCH) — 49
const int eunatch = 49;

/// No CSI structure available (ENOCSI) — 50
const int enocsi = 50;

/// Level 2 halted (EL2HLT) — 51
const int el2hlt = 51;

/// Invalid request code (EBADRQC) — 56
const int ebadrqc = 56;

/// Invalid slot (EBADSLT) — 57
const int ebadslt = 57;

// ---------------------------------------------------------------------------
// Network / Socket Errors (88–116)
// ---------------------------------------------------------------------------

/// Socket operation on non-socket (ENOTSOCK) — 88
const int enotsock = 88;

/// Destination address required (EDESTADDRREQ) — 89
const int edestaddrreq = 89;

/// Message too long (EMSGSIZE) — 90
const int emsgsize = 90;

/// Protocol wrong type for socket (EPROTOTYPE) — 91
const int eprototype = 91;

/// Protocol not available (ENOPROTOOPT) — 92
const int enoprotoopt = 92;

/// Protocol not supported (EPROTONOSUPPORT) — 93
const int eprotonosupport = 93;

/// Socket type not supported (ESOCKTNOSUPPORT) — 94
const int esocktnosupport = 94;

/// Operation not supported on transport endpoint (EOPNOTSUPP) — 95
const int eopnotsupp = 95;

/// Address family not supported by protocol (EAFNOSUPPORT) — 97
const int eafnosupport = 97;

/// Address already in use (EADDRINUSE) — 98
const int eaddrinuse = 98;

/// Cannot assign requested address (EADDRNOTAVAIL) — 99
const int eaddrnotavail = 99;

/// Network is down (ENETDOWN) — 100
const int enetdown = 100;

/// Network is unreachable (ENETUNREACH) — 101
const int enetunreach = 101;

/// Network dropped connection on reset (ENETRESET) — 102
const int enetreset = 102;

/// Software caused connection abort (ECONNABORTED) — 103
const int econnaborted = 103;

/// Connection reset by peer (ECONNRESET) — 104
const int econnreset = 104;

/// No buffer space available (ENOBUFS) — 105
const int enobufs = 105;

/// Transport endpoint is already connected (EISCONN) — 106
const int eisconn = 106;

/// Transport endpoint is not connected (ENOTCONN) — 107
const int enotconn = 107;

/// Cannot send after transport endpoint shutdown (ESHUTDOWN) — 108
const int eshutdown = 108;

/// Connection timed out (ETIMEDOUT) — 110
const int etimedout = 110;

/// Connection refused (ECONNREFUSED) — 111
const int econnrefused = 111;

/// Host is down (EHOSTDOWN) — 112
const int ehostdown = 112;

/// No route to host (EHOSTUNREACH) — 113
const int ehostunreach = 113;

/// Operation already in progress (EALREADY) — 114
const int ealready = 114;

/// Operation now in progress (EINPROGRESS) — 115
const int einprogress = 115;

/// Stale file handle (ESTALE) — 116
///
/// Common with NFS mounts; the file handle is no longer valid.
const int estale = 116;

abstract final class Errno {
  static const Map<int, String> _descriptions = {
    eperm: 'Operation not permitted',
    enoent: 'No such file or directory',
    esrch: 'No such process',
    eintr: 'Interrupted system call',
    eio: 'Input/output error',
    enxio: 'No such device or address',
    e2big: 'Argument list too long',
    enoexec: 'Exec format error',
    ebadf: 'Bad file descriptor',
    echild: 'No child processes',
    eagain: 'Resource temporarily unavailable',
    enomem: 'Out of memory',
    eacces: 'Permission denied',
    efault: 'Bad address',
    enotblk: 'Block device required',
    ebusy: 'Device or resource busy',
    eexist: 'File exists',
    exdev: 'Cross-device link',
    enodev: 'No such device',
    enotdir: 'Not a directory',
    eisdir: 'Is a directory',
    einval: 'Invalid argument',
    enfile: 'File table overflow',
    emfile: 'Too many open files',
    enotty: 'Inappropriate ioctl for device',
    etxtbsy: 'Text file busy',
    efbig: 'File too large',
    enospc: 'No space left on device',
    espipe: 'Illegal seek',
    erofs: 'Read-only file system',
    emlink: 'Too many links',
    epipe: 'Broken pipe',
    edom: 'Math argument out of domain',
    erange: 'Math result not representable',
    edeadlk: 'Resource deadlock avoided',
    enametoolong: 'File name too long',
    enolck: 'No locks available',
    enosys: 'Function not implemented',
    enotempty: 'Directory not empty',
    eloop: 'Too many symbolic links',
    el2nsync: 'Level 2 not synchronized',
    el3hlt: 'Level 3 halted',
    el3rst: 'Level 3 reset',
    elnrng: 'Link number out of range',
    eunatch: 'Protocol driver not attached',
    enocsi: 'No CSI structure available',
    el2hlt: 'Level 2 halted',
    ebadrqc: 'Invalid request code',
    ebadslt: 'Invalid slot',
    enotsock: 'Socket operation on non-socket',
    edestaddrreq: 'Destination address required',
    emsgsize: 'Message too long',
    eprototype: 'Protocol wrong type for socket',
    enoprotoopt: 'Protocol not available',
    eprotonosupport: 'Protocol not supported',
    esocktnosupport: 'Socket type not supported',
    eopnotsupp: 'Operation not supported',
    eafnosupport: 'Address family not supported by protocol',
    eaddrinuse: 'Address already in use',
    eaddrnotavail: 'Cannot assign requested address',
    enetdown: 'Network is down',
    enetunreach: 'Network unreachable',
    enetreset: 'Network dropped connection on reset',
    econnaborted: 'Software caused connection abort',
    econnreset: 'Connection reset by peer',
    enobufs: 'No buffer space available',
    eisconn: 'Transport endpoint is already connected',
    enotconn: 'Transport endpoint is not connected',
    eshutdown: 'Cannot send after transport endpoint shutdown',
    etimedout: 'Connection timed out',
    econnrefused: 'Connection refused',
    ehostdown: 'Host is down',
    ehostunreach: 'No route to host',
    ealready: 'Operation already in progress',
    einprogress: 'Operation now in progress',
    estale: 'Stale file handle',
  };

  // ---------------------------------------------------------------------------
  // Raw errno access
  // ---------------------------------------------------------------------------

  /// The current thread-local errno value.
  ///
  /// Prefer [capture] or [call] over reading this directly — by the time
  /// Dart executes code after a native call, errno may already be stale.
  static int get current => errno_ffi.getErrno();

  /// Overwrites the current thread-local errno value.
  ///
  /// Rarely needed in application code.
  static set current(int value) => errno_ffi.setErrno(value);

  // ---------------------------------------------------------------------------
  // Core safe-call API
  // ---------------------------------------------------------------------------

  /// Runs [operation] and returns its result alongside the errno value
  /// captured **immediately** after the call — before any other code runs.
  ///
  /// This is the lowest-level safe building block. Prefer [call] for the
  /// common case where you only need to throw on error.
  ///
  /// ```dart
  /// final (fd, err) = Errno.capture(() => open(path, O_RDONLY));
  /// if (fd < 0) {
  ///   throw Errno.toOSError(err, 'open($path)');
  /// }
  /// ```
  static (T result, int errno) capture<T>(T Function() operation) =>
      errno_ffi.captureErrno(operation);

  /// Runs [operation], captures errno atomically, and throws an [OSError]
  /// if [isError] returns true for the result.
  ///
  /// The default [isError] predicate treats any negative [int] as an error,
  /// which matches the POSIX convention. Supply a custom predicate for
  /// functions that signal errors differently (e.g. returning `null` or `-1`
  /// specifically).
  ///
  /// ```dart
  /// // Standard POSIX: negative return → error.
  /// final fd = Errno.call(() => open(path, O_RDONLY));
  ///
  /// // Custom predicate: only -1 is an error (not other negatives).
  /// final n = Errno.call(
  ///   () => read(fd, buf, len),
  ///   isError: (r) => r == -1,
  ///   message: 'read',
  /// );
  /// ```
  ///
  /// Throws [OSError] with the captured errno code on failure.
  static T call<T>(
    T Function() operation, {
    bool Function(T result)? isError,
    String? message,
  }) {
    final (result, errnoCode) = errno_ffi.captureErrno(operation);
    final predicate = isError ?? (r) => r is int && (r as int) < 0;

    if (predicate(result)) {
      throw toOSError(errnoCode, message);
    }

    return result;
  }

  /// Returns a human-readable description for errno [code].
  ///
  /// Falls back to `'Unknown error (N)'` for unrecognised codes.
  static String describe(int code) =>
      _descriptions[code] ?? 'Unknown error ($code)';

  /// Wraps errno [code] in a Dart [OSError].
  ///
  /// [message] defaults to [describe(code)] if omitted.
  static OSError toOSError(int code, [String? message]) =>
      OSError(message ?? describe(code), code);

  /// An [OSError] for the [current] errno value.
  ///
  /// Only reliable immediately after a failed native call and before any
  /// other code runs. Prefer [call] or [capture] in new code.
  static OSError get currentOSError => toOSError(current);
}
