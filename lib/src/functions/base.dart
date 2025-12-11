import '/usb_gadget.dart';

/// Core abstraction for all USB gadget functions.
///
/// A function represents a specific USB capability that can be exposed to
/// the host (e.g., mass storage, serial port, ADB). Functions follow a
/// three-phase lifecycle to ensure proper initialization before the gadget
/// is bound to hardware.
///
/// ## Lifecycle Phases
///
/// 1. **prepare()**: Initialize resources asynchronously (mount filesystems,
///    write configuration attributes, open files).
/// 2. **waitState()**: Wait until the function is ready for UDC binding.
///    This ensures all setup is complete before hardware activation.
/// 3. **dispose()**: Clean up resources when the gadget is unbound (close
///    files, unmount filesystems, release handles).
abstract class GadgetFunction {
  /// Creates a gadget function with the specified name.
  ///
  /// Parameters:
  /// - [name]: Unique identifier for this function instance. Must be non-empty.
  GadgetFunction({required this.name})
    : assert(name.isNotEmpty, 'Name cannot be empty');

  /// Unique identifier for this function instance.
  ///
  /// Used to create the configfs directory and identify the function in logs.
  final String name;

  /// Type of this function (FFS or kernel-based).
  ///
  /// FunctionFs functions require userspace descriptors and endpoint handling.
  /// Kernel functions are implemented entirely in the kernel and only require
  /// configuration attribute setup.
  GadgetFunctionType get type;

  /// Returns the configfs instance name for this function.
  ///
  /// The format depends on the function type:
  /// - FFS functions: "ffs.{name}" (e.g., "ffs.adb")
  /// - Kernel functions: "{type}.{name}" (e.g., "mass_storage.storage")
  ///
  /// This name is used to create the function directory under
  /// `/sys/kernel/config/usb_gadget/{gadget}/functions/`.
  String get configfsName;

  /// Phase 1: Initialize function resources at the given configfs path.
  ///
  /// This method is called after the function directory is created but before
  /// it's linked to a configuration. It should perform all necessary setup:
  ///
  /// **For FunctionFs functions:**
  /// - Mount the functionfs filesystem
  /// - Write USB descriptors (device, endpoint, string descriptors)
  /// - Open endpoint files for I/O
  ///
  /// **For kernel functions:**
  /// - Write configuration attributes (LUN paths, serial numbers, etc.)
  /// - Validate configuration parameters
  ///
  /// The [path] parameter is the full configfs path where the function should
  /// write its attributes (e.g., `/sys/kernel/config/usb_gadget/g1/functions/ffs.adb`).
  ///
  /// **Important:** This method must be synchronous in execution but can
  /// initiate asynchronous operations. Use [waitState] to wait for completion.
  ///
  /// Throws:
  /// - [FileSystemException] if configuration files cannot be written
  /// - [ArgumentError] if invalid configuration is provided
  void prepare(String path);

  /// Phase 2: Wait until function is ready for UDC binding.
  ///
  /// This method blocks until the function has reached the specified [state].
  /// The gadget will only bind to the UDC after ALL functions signal ready.
  ///
  /// **For FunctionFs functions:**
  /// - Wait for [FunctionFsState.ready]: descriptors written, endpoints opened
  /// - This ensures the kernel has parsed descriptors before UDC binding
  ///
  /// **For kernel functions:**
  /// - Return immediately (always ready after [prepare])
  ///
  /// The [state] parameter specifies the target state. Common states:
  /// - [FunctionFsState.ready]: Function is fully initialized and ready
  ///
  /// Throws:
  /// - [StateError] if the function enters an error state
  /// - [TimeoutException] if the state is not reached within a reasonable time
  Future<void> waitState(FunctionFsState state);

  /// Phase 3: Clean up function resources.
  ///
  /// Called during gadget unbind to release all resources acquired during
  /// [prepare]. This method should never throw exceptions; log warnings
  /// instead.
  ///
  /// **Cleanup tasks:**
  /// - Close all open file descriptors (endpoint files, control socket)
  /// - Unmount functionfs filesystems
  /// - Stop any background threads or async operations
  /// - Release any allocated memory or buffers
  ///
  /// After this method completes, the function should be in a clean state
  /// and ready for garbage collection.
  void dispose();
}
