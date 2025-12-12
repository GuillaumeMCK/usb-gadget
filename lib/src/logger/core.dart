import 'logger.dart';

final class Logger {
  const Logger(this.name);

  static IPrinter? _printer;

  static int _logLevel = LogLevel.debug.value;

  static const root = Logger('root');

  static void init({IPrinter? printer, LogLevel? level}) {
    _printer = printer ?? DefaultPrinter();
    if (level != null) {
      _logLevel = level.value;
    }
  }

  final String name;

  LogLevel get level => LogLevel.values.firstWhere(
    (l) => l.value == _logLevel,
    orElse: () => LogLevel.debug,
  );

  static bool logPlatformDispatcherError(Object error, StackTrace stackTrace) {
    root.error('Uncaught error in PlatformDispatcher', error, stackTrace);
    return true;
  }

  void debug(String message, [Object? error, StackTrace? stack]) {
    _log(.debug, message, error, stack);
  }

  void info(String message, [Object? error, StackTrace? stack]) {
    _log(.info, message, error, stack);
  }

  void success(String message, [Object? error, StackTrace? stack]) {
    _log(.success, message, error, stack);
  }

  void warn(String message, [Object? error, StackTrace? stack]) {
    _log(.warning, message, error, stack);
  }

  void error(String message, [Object? error, StackTrace? stack]) {
    _log(.error, message, error, stack);
  }

  void _log(
    LogLevel level,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) {
    if (level.value < _logLevel) {
      return;
    }
    _printer?.onLog(
      LogRecord(
        loggerName: name,
        level: level,
        message: message,
        error: error,
        stackTrace: stack,
      ),
    );
  }
}

enum LogLevel {
  debug(0, '?'),
  info(1, '*'),
  success(1, '+'),
  warning(2, '!'),
  error(3, 'x');

  const LogLevel(this.value, this.name);

  final int value;
  final String name;
}

final class LogRecord {
  const LogRecord({
    required this.loggerName,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final String loggerName;
  final LogLevel level;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
}

abstract class ILogger {
  Logger? get log;
}
