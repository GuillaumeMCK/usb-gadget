## 0.6.0

* **FIX**: Refresh OUT endpoints on enable to recover from host de-configuration, replacing dead `AioStream` instances without requiring consumers to re-subscribe.
* **REFACTOR**: Restructure endpoint directory layout — move `functionfs/endpoint.dart` to `endpoint/core.dart` and relocate descriptors/events under `functions/ffs/`.
* **REFACTOR**: Simplify `Aio` initialization in `EndpointInFile` and `EndpointOutFile` by passing file descriptors directly to `Aio.fromEndpointConfig`.
* **REFACTOR**: Refactor `EndpointOutFile` to use a `StreamController` proxy for a stable broadcast stream across USB enable/disable cycles.
* **REFACTOR**: Restructure kernel AIO bindings — rename `platform/aio` to `platform/libaio`, introduce a `Libaio` wrapper with scratch arrays to minimize allocations, and add an `Iocb` owning wrapper with factory methods for read/write ops.
* **REFACTOR**: Relocate `AioStream` and `BufferPool` to `lib/src/endpoint/aio/`; remove seek offsets and ensure data is copied from native buffers before pool return to prevent use-after-free.
* **REFACTOR**: Remove `AioSink`, old `AioContext`, and other high-level AIO abstractions in favor of the more direct `libaio` interface.
* **FEAT**: Add FFI bindings and `Epoll` wrapper for Linux `epoll` and `eventfd` system calls, supporting I/O multiplexing with `create`, `add`, `modify`, `delete`, and `wait`, plus `eventfd` notification helpers.
* **REFACTOR**: Use `DynamicLibrary.process()` to access libc in errno handling.

## 0.5.0

* **FIX**: Various endpoint lifecycle and resource management fixes across `FunctionFs` and `HIDFunctionFs`.
* **FIX**: Several reliability improvements to `AioSink` around write queue and resource release.
* **REFACTOR**: Consolidate endpoint and resource lifecycle management into base classes.

## 0.4.3

* **FIX**: Add missing `fatal` method to `Logger` class
* **CHORE**: Update logger exports to include the `Logger` class
* **CHORE**: Remove the `PlatformLogger` export

## 0.4.2

* **CHORE**: Export `ILogger` as public to allow custom mixin creation outside the library.
* **FIX**: Release endpoints on disable to prevent resource leaks.

## 0.4.1

* **FEAT**: Add compile-time environment-based logging configuration.
* **REFACTOR**: Simplify log level representation.
* **REFACTOR**: Enhance log formatting and color handling.
* **FIX**: Replace hardcoded log level with environment-based constant.

## 0.4.0

* **FEAT**: Initial release of the package.
