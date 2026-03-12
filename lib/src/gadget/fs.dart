part of 'core.dart';

// ---------------------------------------------------------------------------
// File system utilities (private to the library)
// ---------------------------------------------------------------------------

void _writeAttr(String path, String? value) {
  if (value == null) return;
  try {
    File(path).writeAsStringSync(value);
  } catch (err) {
    throw FileSystemException('Failed to write "$value" → $path: $err');
  }
}

void _removeAt(Directory dir) {
  _deleteLinks(Directory('${dir.path}/os_desc'));

  final configsDir = Directory('${dir.path}/configs');
  if (configsDir.existsSync()) {
    for (final e in configsDir.listSync()) {
      if (e is! Directory) continue;
      _deleteLinks(e);
      _deleteDirs(Directory('${e.path}/strings'));
      try {
        e.deleteSync();
      } catch (_) {}
    }
  }

  _deleteDirs(Directory('${dir.path}/functions'));
  _deleteDirs(Directory('${dir.path}/strings'));
  try {
    dir.deleteSync();
  } catch (_) {}
}

void _deleteLinks(Directory dir) {
  if (!dir.existsSync()) return;
  for (final e in dir.listSync()) {
    if (e is Link)
      try {
        e.deleteSync();
      } catch (_) {}
  }
}

void _deleteDirs(Directory parent) {
  if (!parent.existsSync()) return;
  for (final e in parent.listSync()) {
    if (e is Directory)
      try {
        e.deleteSync();
      } catch (_) {}
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
