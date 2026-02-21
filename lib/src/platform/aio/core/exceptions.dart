import '/src/platform/errno/errno.dart';

sealed class AioException implements Exception {
  const AioException(this.message);

  final String message;

  @override
  String toString() => 'AioException: $message';
}

final class AioDisposedException extends AioException {
  const AioDisposedException() : super('Resource disposed');
}

final class AioKernelException extends AioException {
  const AioKernelException(super.message, this.errno);

  factory AioKernelException.fromErrno(int errno, String op) {
    final osError = Errno.toOSError(errno, op);
    return AioKernelException('$osError', errno);
  }

  final int errno;
}

final class AioQueueFullException extends AioException {
  AioQueueFullException(this.queueLength, this.maxQueueSize)
    : super('Queue full ($queueLength/$maxQueueSize)');

  final int queueLength;
  final int maxQueueSize;
}
