abstract final class Ansi {
  static const reset = '\x1B[0m';
  static const bold = '\x1B[1m';
  static const dim = '\x1B[2m';
  static const green = '\x1B[92m';
  static const red = '\x1B[91m';
  static const yellow = '\x1B[33m';
  static const cyan = '\x1B[36m';
}

abstract final class Fmt {
  /// Coloured `[LABEL]` badge.
  static String badge(String label, {bool ok = true}) {
    final color = ok ? Ansi.green : Ansi.red;
    return '$color[${label.padLeft(4)}]${Ansi.reset}';
  }

  static String bold(String s) => '${Ansi.bold}$s${Ansi.reset}';

  static String cyan(String s) => '${Ansi.cyan}$s${Ansi.reset}';

  static String bound(String udc) =>
      '${Ansi.green}bound${Ansi.reset} → ${Ansi.cyan}$udc${Ansi.reset}';

  static String unbound() => '${Ansi.dim}unbound${Ansi.reset}';

  /// Warning prefix for stderr.
  static const warn = '\x1B[33mwarning:\x1B[0m ';
}

/// Print a left-aligned table.  Cell strings may contain ANSI codes;
/// column widths are measured on their visible (stripped) content.
void printTable(List<String> headers, List<List<String>> rows) {
  if (rows.isEmpty) return;

  final cols = headers.length;
  final widths = List.of(headers.map(_visible));

  for (final row in rows) {
    for (var i = 0; i < cols && i < row.length; i++) {
      final w = _visible(row[i]);
      if (w > widths[i]) widths[i] = w;
    }
  }

  _printRow(headers.map((h) => '${Ansi.bold}$h${Ansi.reset}').toList(), widths);
  print(
    '${Ansi.dim}${'─' * (widths.fold(0, (s, w) => s + w) + (cols - 1) * 2)}${Ansi.reset}',
  );
  for (final row in rows) {
    _printRow(row, widths);
  }
}

void _printRow(List<String> cells, List<int> widths) {
  final line = StringBuffer();
  for (var i = 0; i < widths.length; i++) {
    final cell = i < cells.length ? cells[i] : '';
    line.write(cell);
    line.write(
      ' ' * (widths[i] - _visible(cell) + (i < widths.length - 1 ? 2 : 0)),
    );
  }
  print(line);
}

final _ansi = RegExp(r'\x1B\[[0-9;]*m');

int _visible(String s) => s.replaceAll(_ansi, '').length;
