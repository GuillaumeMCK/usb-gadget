import 'logger.dart';

const bool _isDebugMode = .fromEnvironment('USB_GADGET_DEBUG');

mixin USBGadgetLogger implements ILogger {
  @override
  late final Logger? log = _isDebugMode ? .new('$runtimeType') : null;
}

mixin PlatformLogger implements ILogger {
  @override
  late final Logger? log = Logger('$runtimeType');
}
