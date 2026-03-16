part of 'core.dart';

// ---------------------------------------------------------------------------
// File system utilities (private to the library)
// ---------------------------------------------------------------------------

/// Writes [value] to the configfs attribute at [path].
void _writeAttr(String path, String? value) {
  if (value == null) return;
  try {
    File(path).writeAsStringSync(value);
  } catch (err) {
    throw FileSystemException('Failed to write "$value" → $path: $err');
  }
}

/// Tears down a gadget's configfs tree.
///
/// Deletion order satisfies configfs constraints:
///   1. Symlinks in `os_desc/` and each `configs/c.X/`.
///   2. Each `configs/c.X/` directory (strings/ swept first).
///   3. All `functions/` subdirectories, depth-first.
///   4. All `strings/` subdirectories.
///   5. The gadget directory itself.
///
/// The kernel auto-removes top-level groups (functions/, configs/, strings/,
/// os_desc/) once their contents are gone — no explicit rmdir needed.
void _removeAt(Directory dir) {
  _sweep(Directory('${dir.path}/os_desc'));

  final configs = Directory('${dir.path}/configs');
  if (configs.existsSync()) {
    for (final e in configs.listSync(followLinks: false)) {
      if (e is! Directory) continue;
      _sweep(e);
      _rmdir(e, strict: true);
    }
  }

  _sweep(Directory('${dir.path}/functions'));
  _sweep(Directory('${dir.path}/strings'));
  _rmdir(dir, strict: true);
}

/// Depth-first sweep of [dir]: unlinks symlinks, recurses into sub-directories.
///
/// A single pass replaces the former _deleteLinks / _deleteDirs /
/// _deleteDirRecursive trio. Kernel-managed pseudo-files are skipped — they
/// vanish automatically when their parent directory is rmdir'd.
///
/// `followLinks: false` is mandatory so that config→function symlinks are
/// surfaced as [Link] entities rather than followed as [Directory].
void _sweep(Directory dir) {
  if (!dir.existsSync()) return;
  for (final e in dir.listSync(followLinks: false)) {
    switch (e) {
      case Link():
        _unlink(e);
      case Directory():
        _sweep(e);
        _rmdir(e);
    }
  }
}

void _unlink(Link link) {
  try {
    link.deleteSync();
  } on FileSystemException catch (err) {
    throw FileSystemException(
      'Failed to delete symlink "${link.path}": ${err.message}',
      link.path,
      err.osError,
    );
  }
}

/// Removes [dir], with optional strict error handling.
///
/// When [strict] is `false` (default), EPERM / EBUSY / ENOTEMPTY are silently
/// ignored — useful deep inside function subtrees where configfs pseudo-files
/// can transiently block rmdir. Pass `strict: true` for top-level dirs where
/// failure is always unexpected.
void _rmdir(Directory dir, {bool strict = false}) {
  try {
    dir.deleteSync();
  } on FileSystemException catch (err) {
    if (!strict) {
      if (err.osError?.errorCode case eperm || ebusy || enotempty) return;
    }
    throw FileSystemException(
      'Failed to remove dir "${dir.path}": ${err.message}',
      dir.path,
      err.osError,
    );
  }
}

RegFunction? _parseFunction(String name) {
  final dot = name.indexOf('.');
  if (dot < 0) return null;
  return RegFunction(
    driver: name.substring(0, dot),
    instance: name.substring(dot + 1),
  );
}
