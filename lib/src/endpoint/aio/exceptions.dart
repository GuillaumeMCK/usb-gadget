sealed class AioException implements Exception {
  const AioException(this.message);

  final String message;

  @override
  String toString() => 'AioException: $message';
}

final class AioDisposedException extends AioException {
  const AioDisposedException() : super('Resource disposed');
}
