# Changelog
All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog],
and this project adheres to [Semantic Versioning].

## 1.0.1
### Changed
- Update `lints` to 6.1.0 and include `package:lints/recommended.yaml`

### Fixed
- Add missing curly braces to control flow statements in `aio_stream.dart` and `net.dart`
- Remove unnecessary `await` on non-future in `gadget/core.dart`
- Remove redundant `this.` qualifier in `endpoint/core.dart`
- Simplify `getConfigAttributes` in `NetworkFunction` using null-aware syntax

## 1.0.0
### Added
- `UsbGadget.remove()` to clean up configfs registrations without holding a `RegGadget` handle
- Integration tests for bulk transfers, ZLP, and endpoint halt via Python USB host driver

### Changed
- **BREAKING**: `RegGadget.bind()` is now `void` (was `Future<void>`) — call sites no longer need `await`
- **BREAKING**: Remove `RegGadget.unbindAll()`
- Move `gadget.register()` inside `try` block; use `gadget.remove()` in `finally` for simplified lifecycle
- Move USB Chapter 9 definitions (`descriptors`, `speeds`, `types`) to `lib/src/usb/ch9/` sub-package
- Simplify `Future.delayed` calls — remove redundant `<void>` type arguments
- Simplify doc comments in `Errno` and `FunctionFs`

### Fixed
- HID endpoint poll and report intervals corrected to 8ms for High-Speed USB compatibility (was 10ms, which is invalid for HS)
- `UDC` binding error now includes the target UDC name in the log message

## 0.7.0
### Added
- `writeWhile` method for continuous AIO writes
- `isDummyUDC` property on UDC
- `usb-gadget` CLI tool for managing Linux USB gadgets
- Comprehensive UVC frame and control configuration support
- Expanded UAC1 and UAC2 audio function attributes
- `devicePath()` method to `HIDFunction`
- Unit and integration tests for kernel USB functions
- Integration tests for bulk transfers, ZLP, and endpoint halt

### Changed
- Rename `ffs` module to `userland`
- Rename `GadgetFunctionType` to `FunctionType`
- Rename `USBDeviceState` to `DeviceState`
- Rename `USBHIDDescriptor` to `HIDDescriptor`
- Remove legacy `USBSpeed` typedef
- Overhaul gadget and configuration management
- Delegate UDC state management and simplify Gadget API
- Improve `Id`, `Class`, and `Config` API stability and validation
- Introduce `FunctionFsInterface` and improve descriptor handling
- Introduce `ConfigFsTree` for robust gadget teardown
- Make `prepare()` asynchronous
- Make `write()` asynchronous and implement backpressure
- Make `onDisable` a synchronous method on HID
- Replace `Comparable` implementation with comparison operators in `Speed` enum
- Tune AIO buffer sizing
- Update examples to use `writeWhile` and improve lifecycle handling
- Rewrite ping/pong example to support large transfers and benchmarking

### Fixed
- Add state checks to `write()` and `flush()`
- Ignore `EINVAL` in read loop and include stack traces
- Support zero-length packets in `AioStream`
- Default HID endpoint intervals for high-speed compatibility
- Use numeric value for `MaxPower` attribute in gadget configfs

## 0.6.0
### Added
- FFI bindings and `Epoll` wrapper for Linux `epoll` and `eventfd` system calls,
  supporting I/O multiplexing with `create`, `add`, `modify`, `delete`, and `wait`,
  plus `eventfd` notification helpers

### Changed
- Restructure kernel AIO bindings — rename `platform/aio` to `platform/libaio`,
  introduce a `Libaio` wrapper with scratch arrays to minimize allocations, and
  add an `Iocb` owning wrapper with factory methods for read/write ops
- Restructure endpoint directory and simplify AIO initialization
- Relocate `AioStream` and `BufferPool` to `lib/src/endpoint/aio/`; remove seek
  offsets and ensure data is copied from native buffers before pool return to
  prevent use-after-free
- Remove `AioSink`, old `AioContext`, and other high-level AIO abstractions in
  favor of the more direct `libaio` interface
- Rename `DeviceClass.composite` to `perInterface`
- Use `DynamicLibrary.process()` to access libc in errno handling

### Fixed
- Refresh OUT endpoints on enable to recover from host de-configuration,
  replacing dead `AioStream` instances without requiring consumers to re-subscribe
- Rename `restart()` to `refresh()` on FunctionFS

## 0.5.0
### Changed
- Use `release()` instead of `close()` for endpoint lifecycle
- Move `Releasable` mixin and `release()` to `EndpointFile` base class
- Remove `droppedWrites` tracking from `AioSink`

### Fixed
- Add disabled state and fix `onDisable` transition in FunctionFS
- Await `_releaseEndpoints` to prevent concurrent map modification
- Do not release endpoints on disable or release in HID
- Prevent removing from empty write queue in `AioSink`
- Await close during resource release in `AioSink`
- Handle writing to closed sink gracefully in `AioSink`

## 0.4.3
### Changed
- Export `Logger` class and remove `PlatformLogger` export

### Fixed
- Add missing `fatal` log method to `Logger` class
- Prevent double release of resources
- Log stack trace when present in printer function

## 0.4.2
### Changed
- Export `ILogger` as public to allow custom mixin creation outside the library

### Fixed
- Release endpoints on disable to prevent resource leaks

## 0.4.1
### Added
- Compile-time environment-based logging configuration

### Changed
- Simplify log level representation
- Enhance log formatting and color handling

### Fixed
- Replace hardcoded log level with environment-based constant

## 0.4.0
### Added
- Initial release of the package