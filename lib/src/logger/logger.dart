export 'core.dart';
export 'mixin.dart';
export 'printer.dart';

const bool kLogEnabled = .fromEnvironment('USB_GADGET_LOG');
const bool kLogColors = .fromEnvironment('USB_GADGET_LOG_COLORS');
const int kLogLevel = .fromEnvironment('USB_GADGET_LOG_LEVEL', defaultValue: 3);
