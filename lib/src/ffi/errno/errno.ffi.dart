import 'dart:ffi' as ffi;

@ffi.Native<ffi.Pointer<ffi.Int> Function()>(symbol: '__errno_location')
external ffi.Pointer<ffi.Int> _errnoLocation();

/// Gets the current errno value.
int getErrno() {
  try {
    return _errnoLocation().value;
  } catch (e) {
    // Fallback if __errno_location is not available
    return 0;
  }
}

/// Sets the errno value (rarely needed).
void setErrno(int value) {
  try {
    _errnoLocation().value = value;
  } catch (e) {
    // Ignore if not available
  }
}
