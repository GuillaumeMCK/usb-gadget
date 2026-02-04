import 'dart:io';
import 'errno.ffi.dart' as errno_ffi;

/// A utility class for interacting with Linux `errno` values via FFI.
///
/// This class is **Linux-only** and mirrors the error definitions found in
/// the Linux kernel (`asm-generic/errno.h`).
abstract final class Errno {
  // ---------------------------------------------------------------------------
  // Standard POSIX / Generic Errors (1 - 40)
  // ---------------------------------------------------------------------------

  /// Operation not permitted (EPERM)
  static const int eperm = 1;

  /// No such file or directory (ENOENT)
  static const int enoent = 2;

  /// No such process (ESRCH)
  static const int esrch = 3;

  /// Interrupted system call (EINTR)
  static const int eintr = 4;

  /// I/O error (EIO)
  static const int eio = 5;

  /// No such device or address (ENXIO)
  static const int enxio = 6;

  /// Argument list too long (E2BIG)
  static const int e2big = 7;

  /// Exec format error (ENOEXEC)
  static const int enoexec = 8;

  /// Bad file descriptor (EBADF)
  static const int ebadf = 9;

  /// No child processes (ECHILD)
  static const int echild = 10;

  /// Try again / Resource temporarily unavailable (EAGAIN)
  static const int eagain = 11;

  /// Out of memory (ENOMEM)
  static const int enomem = 12;

  /// Permission denied (EACCES)
  static const int eacces = 13;

  /// Bad address (EFAULT)
  static const int efault = 14;

  /// Device or resource busy (EBUSY)
  static const int ebusy = 16;

  /// File exists (EEXIST)
  static const int eexist = 17;

  /// Cross-device link (EXDEV)
  static const int exdev = 18;

  /// No such device (ENODEV)
  static const int enodev = 19;

  /// Not a directory (ENOTDIR)
  static const int enotdir = 20;

  /// Is a directory (EISDIR)
  static const int eisdir = 21;

  /// Invalid argument (EINVAL)
  static const int einval = 22;

  /// File table overflow (ENFILE)
  static const int enfile = 23;

  /// Too many open files (EMFILE)
  static const int emfile = 24;

  /// Not a typewriter / Inappropriate ioctl for device (ENOTTY)
  static const int enotty = 25;

  /// File too large (EFBIG)
  static const int efbig = 27;

  /// No space left on device (ENOSP)
  static const int enospc = 28;

  /// Read-only file system (EROFS)
  static const int erofs = 30;

  /// Broken pipe (EPIPE)
  static const int epipe = 32;

  /// Math argument out of domain (EDOM)
  static const int edom = 33;

  /// Math result not representable (ERANGE)
  static const int erange = 34;

  /// File name too long (ENAMETOOLONG)
  static const int enametoolong = 36;

  /// Function not implemented (ENOSYS)
  static const int enosys = 38;

  /// Directory not empty (ENOTEMPTY)
  static const int enotempty = 39;

  /// Too many symbolic links (ELOOP)
  static const int eloop = 40;

  // ---------------------------------------------------------------------------
  // Linux-specific / Legacy STREAMS Errors (45 - 87)
  // ---------------------------------------------------------------------------

  /// Level 2 not synchronized (EL2NSYNC)
  static const int el2nsync = 45;

  /// Level 3 halted (EL3HLT)
  static const int el3hlt = 46;

  /// Level 3 reset (EL3RST)
  static const int el3rst = 47;

  /// Link number out of range (ELNRNG)
  static const int elnrng = 48;

  /// Protocol driver not attached (EUNATCH)
  static const int eunatch = 49;

  /// No CSI structure available (ENOCSI)
  static const int enocsi = 50;

  /// Level 2 halted (EL2HLT)
  static const int el2hlt = 51;

  /// Invalid request code (EBADRQC)
  static const int ebadrqc = 56;

  /// Invalid slot (EBADSLT)
  static const int ebadslt = 57;

  // ---------------------------------------------------------------------------
  // Network / Socket Errors (88 - 115)
  // ---------------------------------------------------------------------------

  /// Socket operation on non-socket (ENOTSOCK)
  static const int enotsock = 88;

  /// Destination address required (EDESTADDRREQ)
  static const int edestaddrreq = 89;

  /// Message too long (EMSGSIZE)
  static const int emsgsize = 90;

  /// Protocol wrong type for socket (EPROTOTYPE)
  static const int eprototype = 91;

  /// Protocol not available (ENOPROTOOPT)
  static const int enoprotoopt = 92;

  /// Protocol not supported (EPROTONOSUPPORT)
  static const int eprotonosupport = 93;

  /// Socket type not supported (ESOCKTNOSUPPORT)
  static const int esocktnosupport = 94;

  /// Operation not supported on transport endpoint (EOPNOTSUPP)
  static const int eopnotsupp = 95;

  /// Address family not supported by protocol (EAFNOSUPPORT)
  static const int eafnosupport = 97;

  /// Address already in use (EADDRINUSE)
  static const int eaddrinuse = 98;

  /// Cannot assign requested address (EADDRNOTAVAIL)
  static const int eaddrnotavail = 99;

  /// Network is down (ENETDOWN)
  static const int enetdown = 100;

  /// Network is unreachable (ENETUNREACH)
  static const int enetunreach = 101;

  /// Network dropped connection on reset (ENETRESET)
  static const int enetreset = 102;

  /// Software caused connection abort (ECONNABORTED)
  static const int econnaborted = 103;

  /// Connection reset by peer (ECONNRESET)
  static const int econnreset = 104;

  /// No buffer space available (ENOBUFS)
  static const int enobufs = 105;

  /// Transport endpoint is already connected (EISCONN)
  static const int eisconn = 106;

  /// Transport endpoint is not connected (ENOTCONN)
  static const int enotconn = 107;

  /// Cannot send after transport endpoint shutdown (ESHUTDOWN)
  static const int eshutdown = 108;

  /// Connection timed out (ETIMEDOUT)
  static const int etimedout = 110;

  /// Connection refused (ECONNREFUSED)
  static const int econnrefused = 111;

  /// Host is down (EHOSTDOWN)
  static const int ehostdown = 112;

  /// No route to host (EHOSTUNREACH)
  static const int ehostunreach = 113;

  /// Operation already in progress (EALREADY)
  static const int ealready = 114;

  /// Operation now in progress (EINPROGRESS)
  static const int einprogress = 115;

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
    ebusy: 'Device or resource busy',
    eexist: 'File exists',
    exdev: 'Cross-device link',
    enodev: 'No such device',
    enotdir: 'Not a directory',
    eisdir: 'Is a directory',
    einval: 'Invalid argument',
    emfile: 'Too many open files',
    enfile: 'File table overflow',
    enotty: 'Not a terminal',
    efbig: 'File too large',
    enospc: 'No space left on device',
    erofs: 'Read-only file system',
    epipe: 'Broken pipe',
    edom: 'Math argument out of domain',
    erange: 'Math result not representable',
    enosys: 'Function not implemented',
    enotempty: 'Directory not empty',
    eloop: 'Too many symbolic links',
    enametoolong: 'File name too long',

    // Legacy / STREAMS
    el2nsync: 'Level 2 not synchronized',
    el3hlt: 'Level 3 halted',
    el3rst: 'Level 3 reset',
    elnrng: 'Link number out of range',
    eunatch: 'Protocol driver not attached',
    enocsi: 'No CSI structure available',
    el2hlt: 'Level 2 halted',
    ebadrqc: 'Invalid request code',
    ebadslt: 'Invalid slot',

    // Network / Sockets
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
  };

  /// Returns the current thread-local `errno` value.
  static int get current {
    try {
      return errno_ffi.getErrno();
    } catch (_) {
      return 0;
    }
  }

  /// Sets the current thread-local `errno` value.
  static set current(int value) {
    try {
      errno_ffi.setErrno(value);
    } catch (_) {}
  }

  /// Returns a descriptive string for a given errno [code].
  static String describe(int code) =>
      _descriptions[code] ?? 'Unknown error ($code)';

  /// Converts an errno [code] into a Dart [OSError].
  static OSError toOSError(int code, [String? message]) =>
      OSError(message ?? describe(code), code);

  /// Returns an [OSError] for the [current] errno value.
  static OSError get currentOSError => toOSError(current);

  /// Wraps a native call and throws [currentOSError] if the return value satisfies [isError].
  static T check<T>(
    T Function() operation, {
    bool Function(T result)? isError,
  }) {
    final result = operation();
    final checkError = isError ?? (r) => (r is int && r < 0);

    if (checkError(result)) {
      throw currentOSError;
    }

    return result;
  }

  /// Retries the [operation] if an [OSError] with a code in [retryOn] occurs.
  static T retry<T>(
    T Function() operation, {
    required List<int> retryOn,
    int maxRetries = 3,
    Duration retryDelay = const Duration(milliseconds: 50),
  }) {
    var attempt = 0;
    while (true) {
      try {
        return operation();
      } on OSError catch (e) {
        attempt++;
        if (attempt > maxRetries || !retryOn.contains(e.errorCode)) {
          rethrow;
        }
        sleep(retryDelay);
      }
    }
  }
}
