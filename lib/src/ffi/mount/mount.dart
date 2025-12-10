/// Linux mount system calls wrapper
///
/// Provides safe, idiomatic Dart interfaces for filesystem mounting
/// and unmounting operations.
///
/// Example:
/// ```dart
/// // Mount a tmpfs
/// Mount.mount(
///   target: '/mnt/tmp',
///   filesystemType: FilesystemType.tmpfs,
///   mountFlags: [MountFlag.noSuid, MountFlag.noDev],
/// );
///
/// // Bind mount
/// Mount.bindMount(source: '/src', target: '/dst');
///
/// // Unmount
/// Mount.umount('/mnt/tmp');
/// ```
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../errno/errno.dart';
import '../utils.dart';
import 'mount.ffi.dart' as mount_lib;

/// Singleton library loader for mount
class MountLibrary {
  MountLibrary._();

  static final instance = MountLibrary._();

  final mount_lib.Mount lib = mount_lib.Mount(ffi.DynamicLibrary.process());
}

/// Filesystem types recognized by the Linux kernel mount() syscall
///
/// Availability depends on kernel configuration and loaded modules.
enum FilesystemType {
  // Native Linux filesystems
  ext2('ext2'),
  ext3('ext3'),
  ext4('ext4'),
  xfs('xfs'),
  btrfs('btrfs'),
  f2fs('f2fs'),
  jfs('jfs'),
  reiserfs('reiserfs'),

  // Pseudo / virtual filesystems
  proc('proc'),
  sysfs('sysfs'),
  devtmpfs('devtmpfs'),
  devpts('devpts'),
  tmpfs('tmpfs'),
  ramfs('ramfs'),
  mqueue('mqueue'),
  pstore('pstore'),
  debugfs('debugfs'),
  tracefs('tracefs'),
  configfs('configfs'),
  securityfs('securityfs'),
  cgroup('cgroup'),
  cgroup2('cgroup2'),
  binderfs('binderfs'),
  rpcPipefs('rpc_pipefs'),
  hugetlbfs('hugetlbfs'),
  bpf('bpf'),
  kernfs('kernfs'),
  functionfs('functionfs'),

  // ROM / compressed filesystems
  iso9660('iso9660'),
  udf('udf'),
  squashfs('squashfs'),
  cramfs('cramfs'),
  romfs('romfs'),
  erofs('erofs'),

  // Legacy/uncommon filesystems
  minix('minix'),
  minix2('minix2'),
  minix3('minix3'),
  ufs('ufs'),
  sysv('sysv'),
  hpfs('hpfs'),
  hfs('hfs'),
  hfsplus('hfsplus'),
  affs('affs'),
  bfs('bfs'),
  efs('efs'),
  qnx4('qnx4'),
  qnx6('qnx6'),
  adfs('adfs'),
  vxfs('vxfs'),

  // Network filesystems
  nfs('nfs'),
  nfs4('nfs4'),
  cifs('cifs'),
  smb3('smb3'),
  ceph('ceph'),
  ninep('9p'),
  afs('afs'),
  kafs('kafs'),
  ocfs2('ocfs2'),
  gfs('gfs'),
  gfs2('gfs2'),
  pvfs2('pvfs2'),

  // Union / layered filesystems
  overlay('overlay'),
  aufs('aufs'),
  unionfs('unionfs'),

  // Encryption / integrity
  ecryptfs('ecryptfs'),
  fsverity('fsverity'),

  // FAT / Windows / removable media
  vfat('vfat'),
  msdos('msdos'),
  fat('fat'),
  exfat('exfat'),
  ntfs('ntfs');

  const FilesystemType(this._value);

  final String _value;

  @override
  String toString() => _value;
}

/// Flags for filesystem mount operations
enum MountFlag implements Flag {
  /// Mount read-only
  rdOnly(mount_lib.MS_RDONLY),

  /// Ignore suid and sgid bits
  noSuid(mount_lib.MS_NOSUID),

  /// Disallow access to device special files
  noDev(mount_lib.MS_NODEV),

  /// Disallow program execution
  noExec(mount_lib.MS_NOEXEC),

  /// Write synchronously
  synchronous(mount_lib.MS_SYNCHRONOUS),

  /// Alter flags of a mounted filesystem
  remount(mount_lib.MS_REMOUNT),

  /// Allow mandatory locks on filesystem
  mandlock(mount_lib.MS_MANDLOCK),

  /// All directory changes are synchronous
  dirsync(mount_lib.MS_DIRSYNC),

  /// Do not follow symlinks
  noSymFollow(mount_lib.MS_NOSYMFOLLOW),

  /// Do not update access times
  noAtime(mount_lib.MS_NOATIME),

  /// Do not update directory access times
  noDirAtime(mount_lib.MS_NODIRATIME),

  /// Create a bind mount
  bind(mount_lib.MS_BIND),

  /// Atomically move mount
  move(mount_lib.MS_MOVE),

  /// Create a recursive bind mount
  rec(mount_lib.MS_REC),

  /// Update atime relative to mtime/ctime
  relAtime(mount_lib.MS_RELATIME),

  /// Always update atime
  strictAtime(mount_lib.MS_STRICTATIME),

  /// Update atime lazily
  lazyTime(mount_lib.MS_LAZYTIME),

  /// Make mount private (don't share)
  private(mount_lib.MS_PRIVATE),

  /// Make mount shared
  shared(mount_lib.MS_SHARED),

  /// Make mount slave
  slave(mount_lib.MS_SLAVE),

  /// Make mount unbindable
  unbindable(mount_lib.MS_UNBINDABLE);

  const MountFlag(this.value);

  @override
  final int value;
}

/// Flags for unmount operations
enum UnmountFlag implements Flag {
  /// Force unmount (even if busy)
  force(mount_lib.MNT_FORCE),

  /// Detach from namespace (lazy unmount)
  detach(mount_lib.MNT_DETACH),

  /// Mark for expiration
  expire(mount_lib.MNT_EXPIRE),

  /// Don't follow symlinks
  noFollow(mount_lib.UMOUNT_NOFOLLOW);

  const UnmountFlag(this.value);

  @override
  final int value;
}

/// Options for mount operations
class MountOptions {
  const MountOptions({
    this.source,
    required this.target,
    this.filesystemType,
    this.mountFlags = const [],
    this.data,
  });

  /// Source device or directory (null for pseudo-filesystems)
  final String? source;

  /// Target mount point
  final String target;

  /// Filesystem type (null to auto-detect)
  final FilesystemType? filesystemType;

  /// Mount flags
  final List<MountFlag> mountFlags;

  /// Filesystem-specific options string (e.g., "size=10M,mode=755")
  final String? data;

  /// Validate the options
  void validate() {
    if (target.isEmpty) {
      throw ArgumentError.value(target, 'target', 'Cannot be empty');
    }

    // Check for conflicting flags
    final flags = mountFlags.toSet();

    if (flags.contains(MountFlag.rdOnly) && flags.contains(MountFlag.remount)) {
      // This is actually valid - remounting as read-only
    }

    // Bind mounts don't need a filesystem type
    if (flags.contains(MountFlag.bind) && filesystemType != null) {
      // Filesystem type is ignored for bind mounts, but not an error
    }
  }
}

/// Wrapper for mount system calls
///
/// Provides safe, validated wrappers for mounting and unmounting filesystems.
abstract final class Mount {
  /// Mounts a filesystem
  ///
  /// See [MountOptions] for parameter details.
  ///
  /// Throws [ArgumentError] for invalid options.
  /// Throws [OSError] if mount fails.
  ///
  /// Example:
  /// ```dart
  /// Mount.mount(
  ///   target: '/mnt/data',
  ///   source: '/dev/sda1',
  ///   filesystemType: FilesystemType.ext4,
  ///   mountFlags: [MountFlag.rdOnly],
  /// );
  /// ```
  static void mount({
    String? source,
    required String target,
    FilesystemType? filesystemType,
    List<MountFlag> mountFlags = const [],
    String? data,
  }) {
    final options = MountOptions(
      source: source,
      target: target,
      filesystemType: filesystemType,
      mountFlags: mountFlags,
      data: data,
    );

    options.validate();

    final sourcePtr = (options.source ?? '').toNativeUtf8();
    final targetPtr = options.target.toNativeUtf8();
    final fsTypePtr = (options.filesystemType?.toString() ?? '').toNativeUtf8();
    final dataPtr = options.data?.toNativeUtf8();
    final flagValue = options.mountFlags.toBitmask();

    try {
      final result = MountLibrary.instance.lib.mount(
        sourcePtr.cast(),
        targetPtr.cast(),
        fsTypePtr.cast(),
        flagValue,
        dataPtr?.cast() ?? ffi.nullptr,
      );

      if (result != 0) {
        throw Errno.currentOSError;
      }
    } finally {
      malloc
        ..free(sourcePtr)
        ..free(targetPtr)
        ..free(fsTypePtr);
      if (dataPtr != null) {
        malloc.free(dataPtr);
      }
    }
  }

  /// Unmounts a filesystem
  ///
  /// [target] - Path to the mount point
  ///
  /// Throws [ArgumentError] if target is empty.
  /// Throws [OSError] if unmount fails.
  static void umount(String target) {
    if (target.isEmpty) {
      throw ArgumentError.value(target, 'target', 'Cannot be empty');
    }

    final targetPtr = target.toNativeUtf8();
    try {
      final result = MountLibrary.instance.lib.umount(targetPtr.cast());

      if (result != 0) {
        throw Errno.currentOSError;
      }
    } finally {
      malloc.free(targetPtr);
    }
  }

  /// Unmounts a filesystem with additional flags
  ///
  /// [target] - Path to the mount point
  /// [flags] - Unmount flags controlling behavior
  ///
  /// Throws [ArgumentError] if target is empty.
  /// Throws [OSError] if unmount fails.
  ///
  /// Example:
  /// ```dart
  /// // Lazy unmount (detach even if busy)
  /// Mount.umount2('/mnt/data', [UnmountFlag.detach]);
  /// ```
  static void umount2(String target, List<UnmountFlag> flags) {
    if (target.isEmpty) {
      throw ArgumentError.value(target, 'target', 'Cannot be empty');
    }

    final targetPtr = target.toNativeUtf8();
    try {
      final result = MountLibrary.instance.lib.umount2(
        targetPtr.cast(),
        flags.toBitmask(),
      );

      if (result != 0) {
        throw Errno.currentOSError;
      }
    } finally {
      malloc.free(targetPtr);
    }
  }

  /// Creates a bind mount
  ///
  /// A bind mount makes a directory tree visible at another location.
  ///
  /// [source] - Source directory
  /// [target] - Target mount point
  /// [readOnly] - Whether to mount read-only
  /// [recursive] - Whether to recursively bind submounts
  ///
  /// Example:
  /// ```dart
  /// Mount.bindMount(
  ///   source: '/var/data',
  ///   target: '/mnt/shared',
  ///   recursive: true,
  /// );
  /// ```
  static void bindMount({
    required String source,
    required String target,
    bool readOnly = false,
    bool recursive = false,
  }) {
    if (source.isEmpty) {
      throw ArgumentError.value(source, 'source', 'Cannot be empty');
    }

    final flags = [MountFlag.bind];
    if (recursive) flags.add(MountFlag.rec);

    mount(source: source, target: target, mountFlags: flags);

    // Bind mounts require a remount to set read-only
    if (readOnly) {
      remount(target: target, mountFlags: [MountFlag.rdOnly]);
    }
  }

  /// Remounts a filesystem with new flags
  ///
  /// Used to change mount options on an already-mounted filesystem.
  ///
  /// [target] - Mount point to remount
  /// [mountFlags] - New mount flags
  ///
  /// Example:
  /// ```dart
  /// // Remount as read-only
  /// Mount.remount(
  ///   target: '/mnt/data',
  ///   mountFlags: [MountFlag.rdOnly],
  /// );
  /// ```
  static void remount({
    required String target,
    List<MountFlag> mountFlags = const [],
  }) {
    mount(target: target, mountFlags: [MountFlag.remount, ...mountFlags]);
  }

  /// Moves a mount point
  ///
  /// Atomically moves an existing mount to a new location.
  ///
  /// [source] - Current mount point
  /// [target] - New mount point
  static void moveMount({required String source, required String target}) {
    mount(source: source, target: target, mountFlags: [MountFlag.move]);
  }

  /// Mounts a tmpfs (temporary filesystem in RAM)
  ///
  /// [target] - Where to mount
  /// [size] - Maximum size (e.g., "10M", "1G") - null for half of RAM
  /// [mode] - Directory permissions in octal (e.g., "755")
  /// [readOnly] - Whether to mount read-only
  ///
  /// Example:
  /// ```dart
  /// Mount.mountTmpfs(
  ///   target: '/mnt/tmp',
  ///   size: '100M',
  ///   mode: '1777', // Sticky bit + world writable
  /// );
  /// ```
  static void mountTmpfs({
    required String target,
    String? size,
    String mode = '755',
    bool readOnly = false,
  }) {
    final options = <String>[];
    if (size != null) options.add('size=$size');
    options.add('mode=$mode');

    final flags = <MountFlag>[];
    if (readOnly) flags.add(MountFlag.rdOnly);

    mount(
      target: target,
      filesystemType: FilesystemType.tmpfs,
      mountFlags: flags,
      data: options.join(','),
    );
  }

  /// Mounts proc filesystem
  ///
  /// Typically mounted at /proc
  static void mountProc(String target) {
    mount(target: target, filesystemType: FilesystemType.proc);
  }

  /// Mounts sysfs filesystem
  ///
  /// Typically mounted at /sys
  static void mountSysfs(String target) {
    mount(target: target, filesystemType: FilesystemType.sysfs);
  }

  /// Mounts devtmpfs filesystem
  ///
  /// Typically mounted at /dev
  static void mountDevtmpfs(String target) {
    mount(target: target, filesystemType: FilesystemType.devtmpfs);
  }

  /// Safely unmounts with retry on busy
  ///
  /// Attempts normal unmount first, then lazy unmount if busy.
  /// Returns true if unmounted, false if still mounted.
  static bool unmountSafe(String target, {int maxRetries = 3}) {
    for (var i = 0; i < maxRetries; i++) {
      try {
        umount(target);
        return true;
      } on OSError catch (e) {
        if (e.errorCode == Errno.ebusy && i < maxRetries - 1) {
          // Wait a bit and retry
          sleep(Duration(milliseconds: 100 * (i + 1)));
          continue;
        }

        if (e.errorCode == Errno.ebusy) {
          // Last retry - try lazy unmount
          try {
            umount2(target, [UnmountFlag.detach]);
            return true;
          } catch (_) {
            return false;
          }
        }

        rethrow;
      }
    }

    return false;
  }
}
