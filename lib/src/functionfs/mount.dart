import 'dart:io';

import '/src/logger/logger.dart';
import '/src/platform/platform.dart';

/// Delay after mounting before opening endpoint files.
///
/// Gives the kernel time to create endpoint files in the FunctionFs mount
/// point. Using a synchronous sleep here avoids a race with `ensure`.
const Duration functionFsMountDelay = Duration(milliseconds: 50);

/// Manages FunctionFs filesystem mounting and unmounting.
///
/// This class encapsulates all mount-related operations for FunctionFs,
/// including mounting, unmounting, remounting, and checking mount status.
class FunctionFsMount with USBGadgetLogger {
  FunctionFsMount({
    required this.mountPoint,
    required this.mountSource,
    required this.ep0Path,
  });

  /// Mount point for FunctionFs filesystem.
  final String mountPoint;

  /// Mount source name (used as filesystem label).
  final String mountSource;

  /// Path to EP0 file (used for mount detection).
  final String ep0Path;

  /// Whether the mount point exists and appears to be mounted.
  ///
  /// Note: This checks if the EP0 file exists. For production use,
  /// consider checking /proc/mounts or using statfs() for more reliable
  /// mount detection.
  bool get isMounted => File(ep0Path).existsSync();

  /// Ensures that FunctionFs is mounted at the specified mount point.
  ///
  /// This method:
  /// 1. Creates the mount point directory if it doesn't exist
  /// 2. Remounts if already mounted (to ensure clean state)
  /// 3. Mounts if not mounted
  /// 4. Waits for [functionFsMountDelay]
  /// 5. Verifies the mount succeeded
  ///
  /// Throws [StateError] if:
  /// - Mount point directory cannot be created
  /// - Mount operation fails
  /// - EP0 file doesn't exist after mount
  void ensure() {
    // Create mount point directory if needed
    final dir = Directory(mountPoint);
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } on FileSystemException catch (e) {
        throw StateError(
          'Failed to create mount point directory $mountPoint: ${e.message}',
        );
      }
    }

    // Remount if already mounted (ensures clean state)
    if (isMounted) {
      log?.warn('Already mounted at $mountPoint, remounting');
      remount();
      sleep(functionFsMountDelay);
    }

    // Mount if not mounted
    if (!isMounted) {
      mount(); // Throws on failure
      sleep(functionFsMountDelay);
    }
  }

  /// Mounts the FunctionFs filesystem.
  ///
  /// Common failure reasons:
  /// - EPERM: No root/CAP_SYS_ADMIN permissions
  /// - ENODEV: FunctionFS not compiled into kernel (CONFIG_USB_FUNCTIONFS_F_FS)
  /// - ENOENT: Mount source name doesn't match any registered FunctionFS instance
  /// - EBUSY: Already mounted at this location
  /// - ENOTDIR: Mount point is not a directory
  ///
  /// Throws [StateError] if already mounted or if mount operation fails.
  void mount() {
    if (isMounted) {
      throw StateError('FunctionFs is already mounted at $mountPoint');
    }

    try {
      Mount.mount(
        source: mountSource,
        target: mountPoint,
        filesystemType: .functionfs,
      );
    } on OSError catch (e) {
      final reason = switch (e.errorCode) {
        Errno.eperm => 'Permission denied (need root or CAP_SYS_ADMIN)',
        Errno.enodev =>
          'FunctionFS not available in kernel (check CONFIG_USB_FUNCTIONFS)',
        Errno.enoent =>
          'Mount source "$mountSource" not found (check configfs setup)',
        Errno.ebusy => 'Already mounted or device busy',
        Errno.enotdir => 'Mount point "$mountPoint" is not a directory',
        _ => e.message,
      };

      throw StateError(
        'Failed to mount FunctionFs at $mountPoint: $reason '
        '(errno: ${e.errorCode})',
      );
    }
  }

  /// Remounts the FunctionFs filesystem.
  ///
  /// This performs a remount operation without unmounting first.
  /// Useful for resetting the filesystem state.
  void remount() {
    try {
      Mount.remount(target: mountPoint);
    } on OSError catch (e) {
      log?.error('Failed to remount FunctionFs: ${e.message}');
      throw StateError(
        'Failed to remount FunctionFs at $mountPoint: ${e.message} '
        '(errno: ${e.errorCode})',
      );
    }
  }

  /// Unmounts the FunctionFs filesystem.
  ///
  /// Attempts normal unmount first, then force unmount (MNT_DETACH) if needed.
  /// Safe to call multiple times (idempotent).
  ///
  /// This method does not throw on failure - it logs warnings instead.
  void unmount() {
    if (!isMounted) {
      log?.debug('FunctionFs not mounted at $mountPoint, skipping unmount');
      return;
    }

    try {
      Mount.umount(mountPoint);
      log?.info('Unmounted FunctionFs from $mountPoint');
    } catch (_) {
      log?.warn('Unmount failed, attempting force unmount (MNT_DETACH)');
    }
    if (isMounted) {
      try {
        Mount.umount2(mountPoint, const [.detach]);
        log?.info('Force unmounted FunctionFs from $mountPoint');
      } catch (e) {
        log?.error('Failed to unmount FunctionFs: $e');
      }
    }
  }
}
