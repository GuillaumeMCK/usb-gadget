import 'dart:io';

import '/src/platform/errno/errno.dart';

/// Writes [value] to the configfs attribute file at [path].
///
/// No-ops when [value] is `null`. Wraps any [FileSystemException] with a
/// message that includes both the value and the target path.
void writeAttr(String path, String? value) {
  if (value == null) return;
  try {
    File(path).writeAsStringSync(value);
  } catch (err) {
    throw FileSystemException('Failed to write "$value" → $path: $err');
  }
}

/// Tears down a gadget's configfs tree using [ConfigFsTree.absorb].
void removeAt(Directory dir) {
  final tree = ConfigFsTree();
  // Insert the root dir BEFORE absorbing children, so it sits at index 0
  // in _dirs. sweep() iterates _dirs.reversed, meaning the root is visited
  // last — after all its children have already been deleted.
  tree._dirs.add(dir.path);
  tree.absorb(dir);
  tree.sweep();
}

/// Tracks directories and symlinks created under a configfs subtree so they
/// can be torn down in safe bottom-up order without a hand-written mirror of
/// the setup logic.
///
/// ## Usage
/// ```dart
/// final tree = ConfigFsTree();
/// tree.mkdirp('$base/streaming/class/fs');
/// tree.symlink('$base/streaming/class/fs/h', '$base/streaming/header/h');
/// // ... later:
/// tree.sweep();
/// ```
final class ConfigFsTree {
  final _dirs = <String>[];
  final _links = <String>[];

  /// Creates [path] and all missing ancestors, recording only new dirs.
  ///
  /// Parents are always recorded before children, so [sweep] can reverse the
  /// list to get guaranteed bottom-up deletion order.
  void mkdirp(String path) {
    final parts = path.split('/');
    for (var i = 1; i <= parts.length; i++) {
      final partial = parts.sublist(0, i).join('/');
      if (partial.isEmpty) continue;
      final d = Directory(partial);
      if (!d.existsSync()) {
        d.createSync();
        _dirs.add(partial);
      }
    }
  }

  /// Creates a symlink at [path] → [target] and records it.
  ///
  /// No-ops if [path] already exists (idempotent).
  void symlink(String path, String target) {
    if (Link(path).existsSync()) return;
    Link(path).createSync(target);
    _links.add(path);
  }

  /// Scans [dir] depth-first and absorbs any pre-existing entries into the
  /// tracker so that [sweep] will clean them up too.
  ///
  /// Useful for dirs created outside of [mkdirp] (e.g. by the kernel on
  /// function creation) that still need to be removed during teardown.
  void absorb(Directory dir) {
    if (!dir.existsSync()) return;
    for (final e in dir.listSync(followLinks: false)) {
      switch (e) {
        case Link():
          _links.add(e.path);
        case Directory():
          absorb(e);
          _dirs.add(e.path);
      }
    }
  }

  /// Deletes all recorded symlinks, then all recorded directories in reverse
  /// creation order (children before parents).
  ///
  /// EPERM / EBUSY / ENOTEMPTY on rmdir are silently ignored — a dir blocked
  /// by kernel pseudo-files will be cleaned up by the kernel once its parent
  /// is gone.
  void sweep() {
    for (final p in _links) {
      try {
        Link(p).deleteSync();
      } catch (_) {}
    }
    _links.clear();

    for (final p in _dirs.reversed) {
      try {
        Directory(p).deleteSync();
      } on FileSystemException catch (e) {
        if (e.osError?.errorCode case eperm || ebusy || enotempty || enoent) {
          continue;
        }
        rethrow;
      }
    }
    _dirs.clear();
  }
}
