import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'aio_reader_isolate.dart';
import 'aio_write_isolate.dart';

@immutable
final class AioConfig {
  const AioConfig({this.bufferSize = 64 * 1024, this.windowSize = 4})
    : assert(bufferSize > 0 && windowSize > 0);

  final int bufferSize;
  final int windowSize;
}

final class AioReader {
  AioReader(this.fd, [this.config = const AioConfig()]) : assert(fd >= 0);

  final int fd;
  final AioConfig config;

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  StreamController<Uint8List>? _controller;
  bool _started = false;

  Stream<Uint8List> get stream {
    if (_started) throw StateError('Stream already created');
    _started = true;

    _controller = StreamController<Uint8List>(
      onListen: _start,
      onPause: () => _sendDemand(0),
      onResume: () => _sendDemand(config.windowSize),
      onCancel: dispose,
    );

    return _controller!.stream;
  }

  Future<void> _start() async {
    _receivePort = ReceivePort();
    _receivePort!.listen(_handleMessage);

    _isolate = await Isolate.spawn(
      readerIsolateEntry,
      _receivePort!.sendPort,
      debugName: 'AioReader-$fd',
    );
  }

  void _handleMessage(dynamic message) {
    switch (message) {
      case ReaderReady(:final sendPort):
        _sendPort = sendPort;
        _sendPort!.send(ReaderInit(fd, config.bufferSize, config.windowSize));
        _sendDemand(config.windowSize);

      case ReaderData(:final data):
        _controller?.add(data);
        _sendDemand(1); // Request one more

      case ReaderEof():
        _controller?.close();
        dispose();

      case ReaderError(:final error, :final stackTrace):
        _controller?.addError(error, stackTrace);
        dispose();
    }
  }

  void _sendDemand(int count) {
    _sendPort?.send(ReaderDemand(count));
  }

  void dispose() {
    _sendPort?.send(ReaderStop());
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _controller?.close();
  }
}

final class AioWriter {
  AioWriter(this.fd, [this.config = const AioConfig()]) : assert(fd >= 0);

  final int fd;
  final AioConfig config;

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  bool _initialized = false;
  int _nextId = 0;

  final Completer<void> _ready = Completer();
  final Map<int, Completer<int>> _pending = {};

  Future<int> write(Uint8List data) async {
    await _ensureInitialized();

    final id = _nextId++;
    final completer = Completer<int>();
    _pending[id] = completer;

    _sendPort!.send(WriterWrite(id, data));
    return completer.future;
  }

  Future<void> flush() async {
    await _ensureInitialized();

    final id = _nextId++;
    final completer = Completer<int>();
    _pending[id] = completer;

    _sendPort!.send(WriterFlush(id));
    await completer.future;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    _receivePort = ReceivePort();
    _receivePort!.listen(_handleMessage);

    _isolate = await Isolate.spawn(
      writerIsolateEntry,
      _receivePort!.sendPort,
      debugName: 'AioWriter-$fd',
    );

    await _ready.future;
  }

  void _handleMessage(dynamic message) {
    switch (message) {
      case WriterReady(:final sendPort):
        _sendPort = sendPort;
        _sendPort!.send(WriterInit(fd, config.bufferSize, config.windowSize));
        _ready.complete();

      case WriterComplete(:final id, :final bytesWritten, :final error):
        final completer = _pending.remove(id);
        if (error != null) {
          completer?.completeError(error);
        } else {
          completer?.complete(bytesWritten);
        }

      case WriterFlushed(:final id):
        _pending.remove(id)?.complete(0);

      case WriterError(:final error, :final stackTrace):
        for (final completer in _pending.values) {
          completer.completeError(error, stackTrace);
        }
        _pending.clear();
        dispose();
    }
  }

  void dispose() {
    _sendPort?.send(WriterStop());
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
  }
}
