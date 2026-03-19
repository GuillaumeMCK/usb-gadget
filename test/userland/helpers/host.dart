import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class UsbHostError extends StateError {
  UsbHostError(super.message);
}

class UsbStallError extends UsbHostError {
  UsbStallError([String detail = ''])
    : super('STALL${detail.isEmpty ? "" : ": $detail"}');
}

class HostDevice {
  HostDevice._(this._process, this._lines, this.maxPacketSize);

  final Process _process;
  final StreamIterator<String> _lines;
  final int maxPacketSize;

  bool _alive = true;

  Future<void> _chain = Future<void>.value();

  static String get _defaultDriverScript => [
    Directory.current.path,
    'test',
    'userland',
    'helpers',
    'usb_driver.py',
  ].join(Platform.pathSeparator);

  static Future<HostDevice> open({
    required int vid,
    required int pid,
    int epIn = 0x81,
    String? driverScript,
  }) async {
    final script = driverScript ?? _defaultDriverScript;

    final process = await Process.start('python3', [script]);

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => stderr.writeln('[usb_driver] $line'));

    final lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );

    final host = HostDevice._(process, lines, 0 /* temporary */);

    final resp = await host._send({
      'cmd': 'find',
      'vid': '0x${vid.toRadixString(16).padLeft(4, '0')}',
      'pid': '0x${pid.toRadixString(16).padLeft(4, '0')}',
      'ep_in': epIn,
    });

    if (resp['ok'] != true) {
      process.kill();
      throw UsbHostError(resp['error']?.toString() ?? 'find: unknown error');
    }
    final mps = (resp['mps'] as num).toInt();
    return HostDevice._(process, lines, mps);
  }

  Future<void> claim() async => _check(await _send({'cmd': 'claim'}));

  Future<void> release() async => _check(await _send({'cmd': 'release'}));

  Future<Uint8List> echo(
    Uint8List payload, {
    int? pktSize,
    int epOut = 0x02,
    int epIn = 0x81,
    int timeoutMs = 2000,
  }) async {
    final resp = await _send({
      'cmd': 'echo',
      'hex': _toHex(payload),
      'pkt_size': pktSize ?? maxPacketSize,
      'ep_out': epOut,
      'ep_in': epIn,
      'timeout': timeoutMs,
    });
    _check(resp);
    return _fromHex(resp['hex'] as String);
  }

  Future<int> write(int ep, Uint8List data, {int timeoutMs = 2000}) async {
    final resp = await _send({
      'cmd': 'write',
      'ep': ep,
      'hex': _toHex(data),
      'timeout': timeoutMs,
    });
    _check(resp);
    return (resp['sent'] as num).toInt();
  }

  Future<Uint8List> read(int ep, {int size = 512, int timeoutMs = 2000}) async {
    final resp = await _send({
      'cmd': 'read',
      'ep': ep,
      'size': size,
      'timeout': timeoutMs,
    });
    _check(resp);
    return _fromHex(resp['hex'] as String);
  }

  Future<Uint8List> controlIn({
    required int bmRequestType,
    required int bRequest,
    int wValue = 0,
    int wIndex = 0,
    required int wLength,
  }) async {
    final resp = await _send({
      'cmd': 'control_in',
      'bm': bmRequestType,
      'br': bRequest,
      'wv': wValue,
      'wi': wIndex,
      'wl': wLength,
    });
    _check(resp);
    if (resp['stall'] == true) throw UsbStallError(resp['error'] ?? '');
    return _fromHex(resp['hex'] as String);
  }

  Future<int> controlOut({
    required int bmRequestType,
    required int bRequest,
    int wValue = 0,
    int wIndex = 0,
    Uint8List? data,
  }) async {
    final resp = await _send({
      'cmd': 'control_out',
      'bm': bmRequestType,
      'br': bRequest,
      'wv': wValue,
      'wi': wIndex,
      'hex': _toHex(data ?? Uint8List(0)),
    });
    _check(resp);
    if (resp['stall'] == true) throw UsbStallError(resp['error'] ?? '');
    return (resp['sent'] as num).toInt();
  }

  Future<void> setHalt(int ep) async =>
      _check(await _send({'cmd': 'set_halt', 'ep': ep}));

  Future<void> clearHalt(int ep) async =>
      _check(await _send({'cmd': 'clear_halt', 'ep': ep}));

  Future<bool> getHalted(int ep) async {
    final resp = await _send({'cmd': 'get_status', 'ep': ep});
    _check(resp);
    return resp['halted'] as bool;
  }

  Future<void> sleep(double seconds) async =>
      _check(await _send({'cmd': 'sleep', 'seconds': seconds}));

  Future<Map<String, dynamic>> _send(Map<String, dynamic> cmd) {
    final completer = Completer<Map<String, dynamic>>();
    final prev = _chain;
    _chain = Future(() async {
      await prev.catchError((_) {});
      await _doSend(cmd, completer);
    }).catchError((_) {});
    return completer.future;
  }

  Future<void> _doSend(
    Map<String, dynamic> cmd,
    Completer<Map<String, dynamic>> completer,
  ) async {
    if (!_alive) {
      if (!completer.isCompleted) {
        completer.completeError(UsbHostError('Host device is disposed'));
      }
      return;
    }
    try {
      _process.stdin.writeln(jsonEncode(cmd));
      if (!await _lines.moveNext()) {
        completer.completeError(
          UsbHostError('USB driver process closed unexpectedly'),
        );
        return;
      }
      completer.complete(jsonDecode(_lines.current) as Map<String, dynamic>);
    } catch (err, st) {
      if (!completer.isCompleted) completer.completeError(err, st);
    }
  }

  static void _check(Map<String, dynamic> resp) {
    if (resp['ok'] != true) {
      throw UsbHostError(resp['error']?.toString() ?? 'unknown error');
    }
  }

  static String _toHex(Uint8List data) =>
      data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _fromHex(String hex) {
    if (hex.isEmpty) return Uint8List(0);
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
