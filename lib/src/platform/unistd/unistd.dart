import 'dart:ffi' as ffi;
import 'dart:io' show OSError;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '/src/utils/bitwise.dart';
import '../errno/errno.dart';
import 'unistd.ffi.dart' as unistd_ffi;

final _process = ffi.DynamicLibrary.process();
final _unistd = unistd_ffi.Unistd(_process);

/// `fcntl(2)` is variadic, but the generated binding fixes it to two
/// arguments and so cannot pass the optional third argument. Bind a 3-arg
/// form directly so commands that take an int argument (F_SETFD, F_SETFL,
/// F_DUPFD, F_SETOWN, ...) actually receive it. Passing an unused extra
/// argument to commands that ignore it (e.g. F_GETFL) is harmless.
final _fcntl3 = _process.lookupFunction<
    ffi.Int Function(ffi.Int, ffi.Int, ffi.Int),
    int Function(int, int, int)>('fcntl');

/// POSIX open() flags
enum OpenFlag implements BitFlag {
  /// Open for reading only
  rdOnly(unistd_ffi.O_RDONLY),

  /// Open for writing only
  wrOnly(unistd_ffi.O_WRONLY),

  /// Open for reading and writing
  rdWr(unistd_ffi.O_RDWR),

  /// Create file if it doesn't exist
  create(unistd_ffi.O_CREAT),

  /// Fail if file exists (with O_CREAT)
  excl(unistd_ffi.O_EXCL),

  /// Don't make this the controlling terminal
  noCtty(unistd_ffi.O_NOCTTY),

  /// Truncate file to zero length
  trunc(unistd_ffi.O_TRUNC),

  /// Append mode - writes always go to end
  append(unistd_ffi.O_APPEND),

  /// Non-blocking mode
  nonBlock(unistd_ffi.O_NONBLOCK),

  /// Synchronous writes
  sync(unistd_ffi.O_SYNC),

  /// Synchronous data writes only
  dsync(unistd_ffi.O_DSYNC),

  /// Synchronous reads (same as O_SYNC on Linux)
  rsync(unistd_ffi.O_RSYNC),

  /// Fail if path is not a directory
  directory(unistd_ffi.O_DIRECTORY),

  /// Don't follow symbolic links
  noFollow(unistd_ffi.O_NOFOLLOW),

  /// Set close-on-exec flag
  cloExec(unistd_ffi.O_CLOEXEC),

  /// Async I/O notification
  async(unistd_ffi.O_ASYNC);

  const OpenFlag(this.value);

  @override
  final int value;
}

/// fcntl() commands
enum FcntlCommand {
  /// Duplicate file descriptor
  dupFd(unistd_ffi.F_DUPFD),

  /// Get file descriptor flags
  getFd(unistd_ffi.F_GETFD),

  /// Set file descriptor flags
  setFd(unistd_ffi.F_SETFD),

  /// Get file status flags
  getFl(unistd_ffi.F_GETFL),

  /// Set file status flags
  setFl(unistd_ffi.F_SETFL),

  /// Get owner (process receiving SIGIO)
  getOwn(unistd_ffi.F_GETOWN),

  /// Set owner (process receiving SIGIO)
  setOwn(unistd_ffi.F_SETOWN),

  /// Duplicate file descriptor with close-on-exec
  dupFdCloExec(unistd_ffi.F_DUPFD_CLOEXEC),

  /// Get record lock info
  getLk(unistd_ffi.F_GETLK),

  /// Set record lock
  setLk(unistd_ffi.F_SETLK),

  /// Set record lock (blocking)
  setLkW(unistd_ffi.F_SETLKW);

  const FcntlCommand(this.value);

  final int value;
}

/// Wrapper for POSIX unistd functions
///
/// Provides safe, validated wrappers around low-level system calls.
abstract final class Unistd {
  /// Opens a file and returns a file descriptor
  ///
  /// [path] - Path to the file
  /// [flags] - Open flags controlling behavior
  /// [mode] - File permissions (only used with O_CREAT)
  ///
  /// Returns a non-negative file descriptor on success.
  /// Throws [OSError] on failure.
  /// Throws [ArgumentError] if path is empty.
  static int open(String path, List<OpenFlag> flags, {int mode = 0644}) {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'Cannot be empty');
    }

    final pathPtr = path.toNativeUtf8();
    try {
      return Errno.call(
        () => _unistd.open(pathPtr.cast(), flags.toBitmask()),
        isError: (r) => r == -1,
        message: 'open($path)',
      );
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Closes a file descriptor
  ///
  /// [fd] - File descriptor to close
  ///
  /// This method does not throw on error, as double-closes are common
  /// and usually harmless. Use [closeStrict] if you need error checking.
  static void close(int fd) {
    _unistd.close(fd);
  }

  /// Closes a file descriptor with error checking
  ///
  /// Throws [OSError] if close fails.
  /// Throws [ArgumentError] if fd is negative.
  static void closeStrict(int fd) {
    if (fd < 0) {
      throw ArgumentError.value(fd, 'fd', 'Must be non-negative');
    }

    Errno.call(
      () => _unistd.close(fd),
      isError: (r) => r == -1,
      message: 'close',
    );
  }

  /// Reads up to [count] bytes from a file descriptor
  ///
  /// [fd] - File descriptor to read from
  /// [count] - Maximum number of bytes to read
  ///
  /// Returns a [Uint8List] with the bytes read. May be shorter than [count].
  /// Returns empty list if EAGAIN/EWOULDBLOCK (for non-blocking I/O).
  /// Returns empty list on EOF.
  ///
  /// Throws [OSError] on error (except EAGAIN).
  /// Throws [ArgumentError] if fd is negative or count is negative.
  static Uint8List read(int fd, int count) {
    if (fd < 0) {
      throw ArgumentError.value(fd, 'fd', 'Must be non-negative');
    }
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'Must be positive');
    }

    final bufferPtr = malloc<ffi.Uint8>(count);
    try {
      final (bytesRead, errnoCode) = Errno.capture(
        () => _unistd.read(fd, bufferPtr.cast(), count),
      );

      if (bytesRead < 0) {
        // Non-blocking read would block
        if (errnoCode == eagain) {
          return Uint8List(0);
        }

        // Interrupted by signal - retry handled by caller
        if (errnoCode == eintr) {
          return Uint8List(0);
        }

        throw Errno.toOSError(errnoCode);
      }

      // EOF or successful read
      return Uint8List.fromList(bufferPtr.asTypedList(bytesRead));
    } finally {
      malloc.free(bufferPtr);
    }
  }

  /// Reads exactly [count] bytes from a file descriptor
  ///
  /// Keeps reading until exactly [count] bytes are read or EOF/error occurs.
  ///
  /// Returns a [Uint8List] with exactly [count] bytes, or fewer if EOF.
  /// Throws [OSError] on error.
  static Uint8List readExact(int fd, int count) {
    if (count == 0) return Uint8List(0);

    final result = Uint8List(count);
    var totalRead = 0;

    while (totalRead < count) {
      final chunk = read(fd, count - totalRead);

      if (chunk.isEmpty) {
        // EOF reached
        return Uint8List.sublistView(result, 0, totalRead);
      }

      result.setRange(totalRead, totalRead + chunk.length, chunk);
      totalRead += chunk.length;
    }

    return result;
  }

  /// Writes data to a file descriptor
  ///
  /// [fd] - File descriptor to write to
  /// [data] - Data to write
  ///
  /// Returns the number of bytes actually written (may be less than data.length).
  ///
  /// Throws [OSError] on error.
  /// Throws [ArgumentError] if fd is negative.
  static int write(int fd, Uint8List data) {
    if (fd < 0) {
      throw ArgumentError.value(fd, 'fd', 'Must be non-negative');
    }

    // Handle zero-length writes
    if (data.isEmpty) {
      return _unistd.write(fd, ffi.nullptr, 0);
    }

    final bufferPtr = malloc<ffi.Uint8>(data.length);
    try {
      bufferPtr.asTypedList(data.length).setAll(0, data);

      return Errno.call(
        () => _unistd.write(fd, bufferPtr.cast(), data.length),
        isError: (r) => r == -1,
        message: 'write',
      );
    } finally {
      malloc.free(bufferPtr);
    }
  }

  /// Writes all data to a file descriptor
  ///
  /// Keeps writing until all data is written or an error occurs.
  /// Automatically retries on EINTR.
  ///
  /// Throws [OSError] on error.
  static void writeAll(int fd, Uint8List data) {
    // Handle zero-length writes
    if (data.isEmpty) {
      write(fd, data);
      return;
    }

    var offset = 0;

    while (offset < data.length) {
      final chunk = Uint8List.view(
        data.buffer,
        data.offsetInBytes + offset,
        data.length - offset,
      );

      try {
        final written = write(fd, chunk);
        offset += written;
      } on OSError catch (e) {
        // Retry on interrupted system call
        if (e.errorCode == eintr) {
          continue;
        }
        rethrow;
      }
    }
  }

  /// Manipulate file descriptor
  ///
  /// [fd] - File descriptor
  /// [cmd] - Command to execute
  /// [arg] - Optional argument (interpretation depends on cmd)
  ///
  /// Returns command-specific value.
  /// Throws [OSError] on error.
  static int fcntl(int fd, FcntlCommand cmd, [int arg = 0]) {
    if (fd < 0) {
      throw ArgumentError.value(fd, 'fd', 'Must be non-negative');
    }

    return Errno.call(
      () => _fcntl3(fd, cmd.value, arg),
      isError: (r) => r == -1,
      message: 'fcntl',
    );
  }

  /// Get file status flags
  ///
  /// Returns the flags used when the file was opened.
  static int getFlags(int fd) {
    return fcntl(fd, FcntlCommand.getFl);
  }

  /// Set file status flags
  static void setFlags(int fd, List<OpenFlag> flags) {
    fcntl(fd, FcntlCommand.setFl, flags.toBitmask());
  }

  /// Set non-blocking mode on a file descriptor
  static void setNonBlocking(int fd, bool nonBlocking) {
    final currentFlags = getFlags(fd);

    final newFlags = nonBlocking
        ? currentFlags | OpenFlag.nonBlock.value
        : currentFlags & ~OpenFlag.nonBlock.value;

    fcntl(fd, FcntlCommand.setFl, newFlags);
  }
}
