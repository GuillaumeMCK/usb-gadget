import 'dart:io';

import 'errno.ffi.dart' as errno_ffi;

/// POSIX errno values and utilities
///
/// This class provides constants for common errno values and utilities
/// for converting between errno codes and Dart OSError objects.
abstract final class Errno {
  // Permission and access errors

  /// Operation not permitted
  static const eperm = 1;

  /// No such file or directory
  static const enoent = 2;

  /// No such process
  static const esrch = 3;

  /// Interrupted system call
  static const eintr = 4;

  /// Input/output error
  static const eio = 5;

  /// No such device or address
  static const enxio = 6;

  /// Bad file descriptor
  static const ebadf = 9;

  /// Resource temporarily unavailable (would block)
  static const eagain = 11;

  /// Cannot allocate memory
  static const enomem = 12;

  /// Permission denied
  static const eacces = 13;

  /// Bad address
  static const efault = 14;

  // Resource errors

  /// Device or resource busy
  static const ebusy = 16;

  /// File exists
  static const eexist = 17;

  /// No such device
  static const enodev = 19;

  /// Not a directory
  static const enotdir = 20;

  /// Is a directory
  static const eisdir = 21;

  /// Invalid argument
  static const einval = 22;

  /// Too many open files
  static const emfile = 24;

  /// No space left on device
  static const enospc = 28;

  /// Read-only file system
  static const erofs = 30;

  /// Broken pipe
  static const epipe = 32;

  // Network errors

  /// Operation not supported
  static const eopnotsupp = 95;

  /// Connection reset by peer
  static const econnreset = 104;

  /// Cannot send after transport endpoint shutdown
  static const eshutdown = 108;

  /// Connection timed out
  static const etimedout = 110;

  /// Connection refused
  static const econnrefused = 111;

  // Additional common errors

  /// Cross-device link
  static const exdev = 18;

  /// Not a terminal
  static const enotty = 25;

  /// File too large
  static const efbig = 27;

  /// Function not implemented
  static const enosys = 38;

  /// Directory not empty
  static const enotempty = 39;

  /// Too many levels of symbolic links
  static const eloop = 40;

  /// Operation would block (same as EAGAIN on Linux)
  static const ewouldblock = eagain;

  /// No message of desired type
  static const enomsg = 42;

  /// Identifier removed
  static const eidrm = 43;

  /// Protocol error
  static const eproto = 71;

  /// Multihop attempted
  static const emultihop = 72;

  /// Not a data message
  static const ebadmsg = 74;

  /// Value too large for defined data type
  static const eoverflow = 75;

  /// Illegal byte sequence
  static const eilseq = 84;

  /// Socket operation on non-socket
  static const enotsock = 88;

  /// Destination address required
  static const edestaddrreq = 89;

  /// Message too long
  static const emsgsize = 90;

  /// Protocol wrong type for socket
  static const eprototype = 91;

  /// Protocol not available
  static const enoprotoopt = 92;

  /// Protocol not supported
  static const eprotonosupport = 93;

  /// Socket type not supported
  static const esocktnosupport = 94;

  /// Address family not supported by protocol
  static const eafnosupport = 97;

  /// Address already in use
  static const eaddrinuse = 98;

  /// Cannot assign requested address
  static const eaddrnotavail = 99;

  /// Network is down
  static const enetdown = 100;

  /// Network is unreachable
  static const enetunreach = 101;

  /// Network dropped connection on reset
  static const enetreset = 102;

  /// Software caused connection abort
  static const econnaborted = 103;

  /// No buffer space available
  static const enobufs = 105;

  /// Transport endpoint is already connected
  static const eisconn = 106;

  /// Transport endpoint is not connected
  static const enotconn = 107;

  /// Connection timed out
  static const etimedout110 = 110;

  /// Host is down
  static const ehostdown = 112;

  /// No route to host
  static const ehostunreach = 113;

  /// Operation already in progress
  static const ealready = 114;

  /// Operation now in progress
  static const einprogress = 115;

  /// Stale file handle
  static const estale = 116;

  /// Quota exceeded
  static const edquot = 122;

  /// Operation canceled
  static const ecanceled = 125;

  /// Gets the current errno value from the C runtime
  ///
  /// Returns 0 if errno cannot be accessed.
  static int get current {
    try {
      return errno_ffi.getErrno();
    } catch (err) {
      return 0;
    }
  }

  /// Sets the errno value (rarely needed in application code)
  static set current(int value) {
    try {
      errno_ffi.setErrno(value);
    } catch (_) {
      // Ignore if not available
    }
  }

  /// Gets a human-readable description for an errno value
  static String describe(int code) => switch (code) {
    eperm => 'Operation not permitted',
    enoent => 'No such file or directory',
    esrch => 'No such process',
    eintr => 'Interrupted system call',
    eio => 'Input/output error',
    enxio => 'No such device or address',
    ebadf => 'Bad file descriptor',
    eagain => 'Resource temporarily unavailable',
    enomem => 'Cannot allocate memory',
    eacces => 'Permission denied',
    efault => 'Bad address',
    ebusy => 'Device or resource busy',
    eexist => 'File exists',
    exdev => 'Cross-device link',
    enodev => 'No such device',
    enotdir => 'Not a directory',
    eisdir => 'Is a directory',
    einval => 'Invalid argument',
    emfile => 'Too many open files',
    enotty => 'Not a terminal',
    efbig => 'File too large',
    enospc => 'No space left on device',
    erofs => 'Read-only file system',
    epipe => 'Broken pipe',
    enosys => 'Function not implemented',
    enotempty => 'Directory not empty',
    eloop => 'Too many levels of symbolic links',
    enomsg => 'No message of desired type',
    eidrm => 'Identifier removed',
    eproto => 'Protocol error',
    emultihop => 'Multihop attempted',
    ebadmsg => 'Not a data message',
    eoverflow => 'Value too large for defined data type',
    eilseq => 'Illegal byte sequence',
    enotsock => 'Socket operation on non-socket',
    edestaddrreq => 'Destination address required',
    emsgsize => 'Message too long',
    eprototype => 'Protocol wrong type for socket',
    enoprotoopt => 'Protocol not available',
    eprotonosupport => 'Protocol not supported',
    esocktnosupport => 'Socket type not supported',
    eopnotsupp => 'Operation not supported',
    eafnosupport => 'Address family not supported by protocol',
    eaddrinuse => 'Address already in use',
    eaddrnotavail => 'Cannot assign requested address',
    enetdown => 'Network is down',
    enetunreach => 'Network is unreachable',
    enetreset => 'Network dropped connection on reset',
    econnaborted => 'Software caused connection abort',
    econnreset => 'Connection reset by peer',
    enobufs => 'No buffer space available',
    eisconn => 'Transport endpoint is already connected',
    enotconn => 'Transport endpoint is not connected',
    eshutdown => 'Cannot send after transport endpoint shutdown',
    etimedout => 'Connection timed out',
    econnrefused => 'Connection refused',
    ehostdown => 'Host is down',
    ehostunreach => 'No route to host',
    ealready => 'Operation already in progress',
    einprogress => 'Operation now in progress',
    estale => 'Stale file handle',
    edquot => 'Quota exceeded',
    ecanceled => 'Operation canceled',
    _ => 'Unknown error ($code)',
  };

  /// Creates an OSError from an errno code
  static OSError toOSError(int code) => OSError(describe(code), code);

  /// Gets an OSError for the current errno value
  static OSError get currentOSError => toOSError(current);

  /// Checks if an error code is a "try again" error
  ///
  /// Returns true for EAGAIN, EWOULDBLOCK, and EINTR.
  static bool isRetryable(int code) {
    return code == eagain || code == ewouldblock || code == eintr;
  }

  /// Checks if an error code is a network error
  static bool isNetworkError(int code) {
    return code == enetdown ||
        code == enetunreach ||
        code == enetreset ||
        code == econnaborted ||
        code == econnreset ||
        code == etimedout ||
        code == econnrefused ||
        code == ehostdown ||
        code == ehostunreach;
  }

  /// Checks if an error code indicates a missing resource
  static bool isNotFound(int code) {
    return code == enoent || code == enodev || code == esrch;
  }

  /// Checks if an error code indicates a permission problem
  static bool isPermissionError(int code) {
    return code == eperm || code == eacces || code == erofs;
  }

  /// Checks if an error code indicates resource exhaustion
  static bool isResourceError(int code) {
    return code == enomem ||
        code == enospc ||
        code == emfile ||
        code == enobufs ||
        code == edquot;
  }

  /// Executes a function and converts errno to OSError on failure
  ///
  /// [operation] - The operation to execute
  /// [isError] - Function to check if result indicates error (default: < 0)
  static T check<T>(
    T Function() operation, {
    bool Function(T result)? isError,
  }) {
    final result = operation();

    final checkError = isError ?? (r) => (r as int) < 0;

    if (checkError(result)) {
      throw currentOSError;
    }

    return result;
  }

  /// Retries an operation on retryable OSErrors
  ///
  /// [operation] - The operation to execute
  /// [maxRetries] - Maximum number of retries (default: 5)
  /// [retryDelay] - Delay between retries (default: 50ms)
  /// [retryOn] - Optional function to determine if error is retryable
  /// [quiet] - If true, suppresses rethrowing after max retries (default: false)
  static T retry<T>(
    T Function() operation, {
    required List<int> retryOn,
    int maxRetries = 3,
    Duration retryDelay = const Duration(milliseconds: 50),
    bool quiet = false,
  }) {
    var attempt = 0;
    while (true) {
      try {
        return operation();
      } on OSError catch (e) {
        attempt++;
        if (attempt > maxRetries || !retryOn.contains(e.errorCode)) {
          if (!quiet) {
            rethrow;
          }
        }
        sleep(retryDelay);
      }
    }
  }
}

/// Extension for checking OSError codes
extension OSErrorExt on OSError {
  /// Whether this is a retryable error
  bool get isRetryable => Errno.isRetryable(errorCode);

  /// Whether this is a network error
  bool get isNetworkError => Errno.isNetworkError(errorCode);

  /// Whether this indicates a missing resource
  bool get isNotFound => Errno.isNotFound(errorCode);

  /// Whether this is a permission error
  bool get isPermissionError => Errno.isPermissionError(errorCode);

  /// Whether this indicates resource exhaustion
  bool get isResourceError => Errno.isResourceError(errorCode);
}
