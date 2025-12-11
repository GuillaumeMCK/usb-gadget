import 'dart:isolate';
import 'dart:typed_data';
import 'aio.dart';

/// Base class for all AIO isolate messages
sealed class AioMessage {}

/// Messages for reader isolate
sealed class ReaderMessage extends AioMessage {}

/// Configuration for reader isolate
final class ReaderConfig extends ReaderMessage {
  ReaderConfig({
    required this.fd,
    required this.bufferSize,
    required this.numBuffers,
    required this.sendPort,
    this.handleError,
  });

  final int fd;
  final int bufferSize;
  final int numBuffers;
  final SendPort sendPort;
  final AioErrorAction Function(int errorCode)? handleError;
}

/// Request to stop reading
final class StopReading extends ReaderMessage {}

/// Messages from reader isolate to main isolate
sealed class ReaderResponse extends AioMessage {}

/// Reader isolate is ready
final class ReaderReady extends ReaderResponse {
  ReaderReady(this.sendPort);
  final SendPort sendPort;
}

/// Data chunk read from file
final class ReadData extends ReaderResponse {
  ReadData(this.data);
  final Uint8List data;
}

/// Error occurred during reading
final class ReadError extends ReaderResponse {
  ReadError(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

/// Reading completed (EOF or stopped)
final class ReadDone extends ReaderResponse {}

/// Messages for writer isolate
sealed class WriterMessage extends AioMessage {}

/// Configuration for writer isolate
final class WriterConfig extends WriterMessage {
  WriterConfig({
    required this.fd,
    required this.bufferSize,
    required this.numBuffers,
    required this.autoFlushThreshold,
    required this.sendPort,
  });

  final int fd;
  final int bufferSize;
  final int numBuffers;
  final int autoFlushThreshold;
  final SendPort sendPort;
}

/// Request to write data
final class WriteData extends WriterMessage {
  WriteData(this.id, this.data);
  final int id;
  final Uint8List data;
}

/// Request to flush pending writes
final class WriteFlush extends WriterMessage {
  WriteFlush(this.id);
  final int id;
}

/// Request to stop writing
final class StopWriting extends WriterMessage {}

/// Messages from writer isolate to main isolate
sealed class WriterResponse extends AioMessage {}

/// Writer isolate is ready
final class WriterReady extends WriterResponse {
  WriterReady(this.sendPort);
  final SendPort sendPort;
}

/// Write operation completed
final class WriteResult extends WriterResponse {
  WriteResult(this.id, this.bytesWritten, this.error);
  final int id;
  final int bytesWritten;
  final Object? error;
}

/// Flush operation completed
final class FlushComplete extends WriterResponse {
  FlushComplete(this.id);
  final int id;
}

/// Writer error (fatal)
final class WriterError extends WriterResponse {
  WriterError(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}
