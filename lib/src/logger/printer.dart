import 'dart:io';

import 'logger.dart';

abstract class IPrinter {
  void onLog(LogRecord record);
}

final class DefaultPrinter extends IPrinter {
  static const _levelColors = {
    LogLevel.debug: '\x1b[90m',
    LogLevel.info: '\x1b[38;5;33m',
    LogLevel.warning: '\x1b[38;5;214m',
    LogLevel.success: '\x1b[38;5;34m',
    LogLevel.error: '\x1b[38;5;196m',
  };

  static const _rst = '\x1b[0m';

  @override
  void onLog(LogRecord record) {
    final color = levelColor(record.level);
    final type = '[${record.level.name}] $_rst';
    stdout.writeln('$color$type[${record.loggerName}] ${record.message}');
    if (record.stackTrace != null) {
      stderr.writeln('$color${record.stackTrace}$_rst');
    }
  }

  String levelColor(LogLevel level) => _levelColors[level]!;
}
