import 'dart:ffi' as ffi;

// Bind explicitly to the current process (resolves via glibc on Linux).
// Using ffi.DynamicLibrary.process() avoids relying on implicit resolution.
final _lib = ffi.DynamicLibrary.process();

// __errno_location() returns a pointer to the calling thread's errno cell.
// We cache the *function* pointer, not the errno cell itself —
// the cell address is thread-local and must be resolved per-call.
final _errnoLocation = _lib
    .lookupFunction<
      ffi.Pointer<ffi.Int> Function(),
      ffi.Pointer<ffi.Int> Function()
    >('__errno_location');

/// Reads the current thread-local errno value.
///
/// **Call this immediately after the native call whose errno you care about.**
/// Any intervening Dart or C call may overwrite errno.
int getErrno() => _errnoLocation().value;

/// Overwrites the current thread-local errno value.
///
/// Rarely needed in application code; useful when implementing
/// wrappers that must preserve errno across calls.
void setErrno(int value) => _errnoLocation().value = value;

/// Runs [operation] and returns both its result and the errno value
/// captured immediately after the call returns — before any other
/// Dart code can clobber it.
///
/// This is the only safe way to use errno in Dart FFI code.
(T result, int errno) captureErrno<T>(T Function() operation) {
  // Clear errno first so we don't mistake a stale value for a new error.
  setErrno(0);
  final result = operation();
  return (result, getErrno());
}
