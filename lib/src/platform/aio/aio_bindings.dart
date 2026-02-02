import 'dart:ffi' as ffi;

import 'aio.ffi.dart';

/// Internal bindings for Linux kernel AIO (libaio).
///
/// Provides a singleton instance of the FFI bindings to the libaio library.
/// This class should not be instantiated directly; use [AioBindings.instance]
/// instead.
class AioBindings {
  AioBindings._();

  static final Aio _instance = Aio(ffi.DynamicLibrary.open('libaio.so'));

  /// The singleton instance of the [Aio] bindings.
  static Aio get instance => _instance;
}
