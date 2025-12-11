import 'dart:io';

import '/src/logger/logger.dart';
import '/src/platform/platform.dart';

/// Configuration for FunctionFs mount behavior.
class FunctionFsMountConfig {
  const FunctionFsMountConfig({
    this.mountDelay = const Duration(milliseconds: 50),
    this.cleanupOnClose = true,
  });

  /// Delay after mounting before opening endpoint files.
  /// Gives kernel time to create endpoint files.
  ///
  /// Note: This uses async delay to avoid blocking the isolate.
  final Duration mountDelay;

  /// Automatically unmount when closing if we mounted it.
  final bool cleanupOnClose;
}

/// Manages FunctionFs filesystem mounting and unmounting.
///
/// This class encapsulates all mount-related operations for FunctionFs,
/// including mounting, unmounting, remounting, and checking mount status.
class FunctionFsMount with USBGadgetLogger {
  FunctionFsMount({
    required this.mountPoint,
    required this.mountSource,
    required this.ep0Path,
    FunctionFsMountConfig? config,
  }) : config = config ?? const FunctionFsMountConfig();

  /// Mount point for FunctionFs filesystem.
  final String mountPoint;

  /// Mount source name (used as filesystem label).
  final String mountSource;

  /// Path to EP0 file (used for mount detection).
  final String ep0Path;

  /// Mount configuration.
  final FunctionFsMountConfig config;

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
  /// 4. Waits for the mount delay
  /// 5. Verifies the mount succeeded
  ///
  /// Throws [StateError] if:
  /// - Mount point directory cannot be created
  /// - Mount operation fails
  /// - EP0 file doesn't exist after mount
  Future<void> ensureMounted() async {
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
      await Future<void>.delayed(config.mountDelay);
    }

    // Mount if not mounted
    if (!isMounted) {
      mount(); // Throws on failure
      await Future<void>.delayed(config.mountDelay);
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
      Errno.retry(
        () => Mount.umount(mountPoint),
        retryOn: [Errno.ebusy],
        maxRetries: 2,
      );
      log?.info('Unmounted FunctionFs from $mountPoint');
    } catch (_) {
      log?.warn('Normal unmount failed, attempting force unmount (MNT_DETACH)');
      try {
        Errno.retry(
          () => Mount.umount2(mountPoint, [.detach]),
          retryOn: [Errno.ebusy],
          maxRetries: 2,
          quiet: true,
        );
        log?.info('Force unmounted FunctionFs from $mountPoint');
      } catch (e) {
        log?.error('Failed to unmount FunctionFs: $e');
      }
    }
  }

  /// Unmounts if cleanup is enabled in config.
  ///
  /// This is a convenience method for use in close() methods.
  void cleanupIfNeeded() {
    if (config.cleanupOnClose) {
      unmount();
    }
  }
}
