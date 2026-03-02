import 'logger.dart';

mixin USBGadgetLogger implements ILogger {
  @override
  late final Logger? log = kLogEnabled ? .new('$runtimeType') : null;
}

mixin PlatformLogger implements ILogger {
  @override
  late final Logger? log = kLogEnabled ? .new('$runtimeType') : null;
}
