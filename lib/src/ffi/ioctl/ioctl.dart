/// ioctl system call wrapper
///
/// Provides safe, type-safe wrappers for device control operations.
///
/// Example:
/// ```dart
/// // Check FIFO status
/// final status = Ioctl.call(fd, FunctionFsIoctl.fifoStatus);
///
/// // Clear halt condition
/// Ioctl.call(fd, FunctionFsIoctl.clearHalt);
///
/// // Get endpoint descriptor
/// final desc = calloc<EndpointDescriptor>();
/// Ioctl.callPtr(fd, FunctionFsIoctl.endpointDesc, desc.cast());
/// ```
library;

import 'dart:ffi' as ffi;
import 'dart:io' show OSError;

import '../errno/errno.dart';
import '../utils.dart';
import 'ioctl.ffi.dart' as ioctl_lib;

/// Singleton library loader for ioctl
class IoctlLibrary {
  IoctlLibrary._();
  static final instance = IoctlLibrary._();

  final ioctl_lib.Ioctl lib = ioctl_lib.Ioctl(ffi.DynamicLibrary.process());
}

/// Direct FFI binding for ioctl with pointer argument
///
/// This handles the variadic nature of ioctl by providing
/// specific overloads for different argument types.
class _IoctlVariadic {
  static final _withPtr = ffi.DynamicLibrary.process()
      .lookupFunction<
        ffi.Int Function(ffi.Int, ffi.UnsignedLong, ffi.Pointer<ffi.Void>),
        int Function(int, int, ffi.Pointer<ffi.Void>)
      >('ioctl');

  static final _withInt = ffi.DynamicLibrary.process()
      .lookupFunction<
        ffi.Int Function(ffi.Int, ffi.UnsignedLong, ffi.Int),
        int Function(int, int, int)
      >('ioctl');

  static int callWithPtr(int fd, int request, ffi.Pointer<ffi.Void> arg) {
    return _withPtr(fd, request, arg);
  }

  static int callWithInt(int fd, int request, int arg) {
    return _withInt(fd, request, arg);
  }
}

/// Base class for ioctl request identifiers
///
/// Each ioctl request has a unique identifier that encodes:
/// - Direction (read, write, or both)
/// - Size of data
/// - Magic number
/// - Command number
abstract class IoctlRequest implements Flag {
  const IoctlRequest(this.value);

  @override
  final int value;

  /// Human-readable name for this request
  String get name;
}

/// FunctionFS ioctl request identifiers
///
/// These ioctls are used with the FunctionFS (USB Gadget) subsystem.
enum FunctionFsIoctl implements IoctlRequest {
  /// Get FIFO status
  fifoStatus(ioctl_lib.FUNCTIONFS_FIFO_STATUS, 'FIFO_STATUS'),

  /// Flush FIFO
  fifoFlush(ioctl_lib.FUNCTIONFS_FIFO_FLUSH, 'FIFO_FLUSH'),

  /// Clear halt condition on endpoint
  clearHalt(ioctl_lib.FUNCTIONFS_CLEAR_HALT, 'CLEAR_HALT'),

  /// Get interface reverse mapping
  interfaceRevmap(ioctl_lib.FUNCTIONFS_INTERFACE_REVMAP, 'INTERFACE_REVMAP'),

  /// Get endpoint reverse mapping
  endpointRevmap(ioctl_lib.FUNCTIONFS_ENDPOINT_REVMAP, 'ENDPOINT_REVMAP'),

  /// Get endpoint descriptor
  endpointDesc(ioctl_lib.FUNCTIONFS_ENDPOINT_DESC, 'ENDPOINT_DESC'),

  /// Attach DMA buffer
  dmabufAttach(ioctl_lib.FUNCTIONFS_DMABUF_ATTACH, 'DMABUF_ATTACH'),

  /// Detach DMA buffer
  dmabufDetach(ioctl_lib.FUNCTIONFS_DMABUF_DETACH, 'DMABUF_DETACH'),

  /// Transfer via DMA buffer
  dmabufTransfer(ioctl_lib.FUNCTIONFS_DMABUF_TRANSFER, 'DMABUF_TRANSFER');

  const FunctionFsIoctl(this.value, this.name);

  @override
  final int value;

  @override
  final String name;

  @override
  String toString() => 'FunctionFsIoctl.$name';
}

/// Result of an ioctl operation
class IoctlResult {
  const IoctlResult(this.value);

  final int value;

  /// Whether the operation succeeded
  bool get isSuccess => value >= 0;

  /// Whether the operation failed
  bool get isError => value < 0;

  /// Error code if operation failed (0 if successful)
  int get errorCode => isError ? Errno.current : 0;

  @override
  String toString() =>
      isSuccess ? 'IoctlResult($value)' : 'IoctlError($errorCode)';
}

/// Wrapper for ioctl system calls
///
/// Provides type-safe, validated wrappers for device control operations.
abstract final class Ioctl {
  /// Perform an ioctl call with no argument
  ///
  /// [fd] - File descriptor
  /// [request] - ioctl request identifier
  ///
  /// Returns the ioctl result value.
  /// Throws [ArgumentError] if fd is negative.
  /// Throws [OSError] if ioctl fails.
  ///
  /// Example:
  /// ```dart
  /// final status = Ioctl.call(fd, FunctionFsIoctl.fifoStatus);
  /// ```
  static int call(int fd, IoctlRequest request) {
    if (fd < 0) {
      throw ArgumentError.value(fd, 'fd', 'Must be non-negative');
    }

    final result = IoctlLibrary.instance.lib.ioctl(fd, request.value);

    if (result < 0) {
      throw Errno.currentOSError;
    }

    return result;
  }

  /// Perform an ioctl call with no argument (returns result without throwing)
  ///
  /// Same as [call] but returns an [IoctlResult] instead of throwing.
  static IoctlResult callSafe(int fd, IoctlRequest request) {
    if (fd < 0) {
      throw ArgumentError.value(fd, 'fd', 'Must be non-negative');
    }

    return IoctlResult(IoctlLibrary.instance.lib.ioctl(fd, request.value));
  }

  /// Perform an ioctl call with an integer argument
  ///
  /// [fd] - File descriptor
  /// [request] - ioctl request identifier
  /// [arg] - Integer argument
  ///
  /// Returns the ioctl result value.
  /// Throws [ArgumentError] if fd is negative.
  /// Throws [OSError] if ioctl fails.
  ///
  /// Example:
  /// ```dart
  /// Ioctl.callInt(fd, SomeIoctl.setValue, 42);
  /// ```
  static int callInt(int fd, IoctlRequest request, int arg) {
    if (fd < 0) {
      throw ArgumentError.value(fd, 'fd', 'Must be non-negative');
    }

    final result = _IoctlVariadic.callWithInt(fd, request.value, arg);

    if (result < 0) {
      throw Errno.currentOSError;
    }

    return result;
  }

  /// Perform an ioctl call with an integer argument (returns result without throwing)
  static IoctlResult callIntSafe(int fd, IoctlRequest request, int arg) {
    if (fd < 0) {
      throw ArgumentError.value(fd, 'fd', 'Must be non-negative');
    }

    return IoctlResult(_IoctlVariadic.callWithInt(fd, request.value, arg));
  }

  /// Perform an ioctl call with a pointer argument
  ///
  /// [fd] - File descriptor
  /// [request] - ioctl request identifier
  /// [arg] - Pointer to data structure
  ///
  /// Returns the ioctl result value.
  /// Throws [ArgumentError] if fd is negative or arg is nullptr.
  /// Throws [OSError] if ioctl fails.
  ///
  /// Example:
  /// ```dart
  /// final desc = calloc<EndpointDescriptor>();
  /// try {
  ///   Ioctl.callPtr(fd, FunctionFsIoctl.endpointDesc, desc.cast());
  ///   // Use desc...
  /// } finally {
  ///   calloc.free(desc);
  /// }
  /// ```
  static int callPtr(int fd, IoctlRequest request, ffi.Pointer<ffi.Void> arg) {
    if (fd < 0) {
      throw ArgumentError.value(fd, 'fd', 'Must be non-negative');
    }
    if (arg == ffi.nullptr) {
      throw ArgumentError.value(arg, 'arg', 'Cannot be nullptr');
    }

    final result = _IoctlVariadic.callWithPtr(fd, request.value, arg);

    if (result < 0) {
      throw Errno.currentOSError;
    }

    return result;
  }

  /// Perform an ioctl call with a pointer argument (returns result without throwing)
  static IoctlResult callPtrSafe(
    int fd,
    IoctlRequest request,
    ffi.Pointer<ffi.Void> arg,
  ) {
    if (fd < 0) {
      throw ArgumentError.value(fd, 'fd', 'Must be non-negative');
    }
    if (arg == ffi.nullptr) {
      throw ArgumentError.value(arg, 'arg', 'Cannot be nullptr');
    }

    return IoctlResult(_IoctlVariadic.callWithPtr(fd, request.value, arg));
  }

  /// Perform an ioctl call with typed pointer
  ///
  /// Type-safe version of [callPtr] that works with specific types.
  ///
  /// Example:
  /// ```dart
  /// final desc = calloc<EndpointDescriptor>();
  /// try {
  ///   Ioctl.callTyped<EndpointDescriptor>(
  ///     fd,
  ///     FunctionFsIoctl.endpointDesc,
  ///     desc,
  ///   );
  /// } finally {
  ///   calloc.free(desc);
  /// }
  /// ```
  static int callTyped<T extends ffi.NativeType>(
    int fd,
    IoctlRequest request,
    ffi.Pointer<T> arg,
  ) {
    return callPtr(fd, request, arg.cast());
  }

  /// Perform an ioctl call with typed pointer (returns result without throwing)
  static IoctlResult callTypedSafe<T extends ffi.NativeType>(
    int fd,
    IoctlRequest request,
    ffi.Pointer<T> arg,
  ) {
    return callPtrSafe(fd, request, arg.cast());
  }
}

/// Helper extensions for common ioctl operations
extension IoctlRequestExt on IoctlRequest {
  /// Execute this ioctl on a file descriptor
  int execute(int fd) => Ioctl.call(fd, this);

  /// Execute this ioctl on a file descriptor (safe version)
  IoctlResult executeSafe(int fd) => Ioctl.callSafe(fd, this);

  /// Execute this ioctl with an integer argument
  int executeInt(int fd, int arg) => Ioctl.callInt(fd, this, arg);

  /// Execute this ioctl with a pointer argument
  int executePtr(int fd, ffi.Pointer<ffi.Void> arg) =>
      Ioctl.callPtr(fd, this, arg);

  /// Execute this ioctl with a typed pointer argument
  int executeTyped<T extends ffi.NativeType>(int fd, ffi.Pointer<T> arg) =>
      Ioctl.callTyped(fd, this, arg);
}

/// High-level helpers for FunctionFS operations
abstract final class FunctionFsHelper {
  /// Get FIFO status for an endpoint
  static int getFifoStatus(int fd) {
    return Ioctl.call(fd, FunctionFsIoctl.fifoStatus);
  }

  /// Flush FIFO for an endpoint
  static void flushFifo(int fd) {
    Ioctl.call(fd, FunctionFsIoctl.fifoFlush);
  }

  /// Clear halt condition on an endpoint
  static void clearHalt(int fd) {
    Ioctl.call(fd, FunctionFsIoctl.clearHalt);
  }

  /// Get interface reverse mapping
  static int getInterfaceRevmap(int fd) {
    return Ioctl.call(fd, FunctionFsIoctl.interfaceRevmap);
  }

  /// Get endpoint reverse mapping
  static int getEndpointRevmap(int fd) {
    return Ioctl.call(fd, FunctionFsIoctl.endpointRevmap);
  }

  /// Check if endpoint is halted
  static bool isHalted(int fd) {
    try {
      final status = getFifoStatus(fd);
      // Implementation-specific status bit checking
      return status != 0;
    } catch (e) {
      return false;
    }
  }

  /// Reset endpoint (clear halt and flush FIFO)
  static void resetEndpoint(int fd) {
    try {
      clearHalt(fd);
    } catch (_) {
      // Ignore if already clear
    }

    try {
      flushFifo(fd);
    } catch (_) {
      // Ignore flush errors
    }
  }
}
