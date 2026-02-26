import 'dart:ffi' as ffi;

// On Android, Bionic libc is the target. Use libc.so explicitly for clarity
// and to avoid ambiguity across API levels.
final _lib = ffi.DynamicLibrary.open('libc.so');

typedef _ErrnoFn = ffi.Pointer<ffi.Int> Function();

// Bionic exposes __errno on API 21–28 and adds __errno_location as an alias
// on API 29+. We try the modern name first and fall back to the legacy one
// so this file works across all supported Android API levels without any
// conditional compilation.
final _errnoLocation = _resolveErrnoFn();

_ErrnoFn _resolveErrnoFn() {
  try {
    // Android API 29+ / glibc-compatible name.
    return _lib.lookupFunction<_ErrnoFn, _ErrnoFn>('__errno_location');
  } catch (_) {
    // Bionic legacy name — API 21–28.
    return _lib.lookupFunction<_ErrnoFn, _ErrnoFn>('__errno');
  }
}

/// Reads the current thread-local errno value.
///
/// **Call this immediately after the native call whose errno you care about.**
/// Any intervening Dart or C call may overwrite errno.
int getErrno() => _errnoLocation().value;

/// Overwrites the current thread-local errno value.
///
/// Rarely needed in application code; useful when implementing wrappers
/// that must preserve errno across calls.
void setErrno(int value) => _errnoLocation().value = value;

/// Runs [operation] and returns both its result and the errno value captured
/// immediately after the call returns — before any other Dart code can
/// clobber it.
(T result, int errno) captureErrno<T>(T Function() operation) {
  // Clear errno first so we don't mistake a stale value for a new error.
  setErrno(0);
  return (operation(), getErrno());
}
