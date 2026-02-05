// ignore_for_file: unintended_html_in_doc_comment

import 'dart:io';

/// Parses an Obsidian monthly log markdown and sums hours per project code.
/// Expected structure:
/// ## February '26
/// - [[2026-02-02]]
///   - [CODE] Some work [8h]
///
/// Notes:
/// - Counts only entries that appear under the selected month header.
/// - By default selects the first month header in the file.
/// - You can select a month header by passing --month "February '26".
/// - Project line format: - [CODE] description [<number>h]
///   (spaces around brackets are flexible)
///
/// Usage:
///   dart run obsidian_worklog_counter.dart <file.md>
///   dart run obsidian_worklog_counter.dart <file.md> --month "February '26"
///   dart run obsidian_worklog_counter.dart <file.md> --json
///   dart run obsidian_worklog_counter.dart <file.md> --month "February '26" --json
void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run obsidian_worklog_counter.dart <file.md> '
      '[--month "February \'26"] [--json]',
    );
    exit(64);
  }

  final filePath = args.first;
  final wantJson = args.contains('--json');

  String? monthFilter;
  final monthFlagIndex = args.indexOf('--month');
  if (monthFlagIndex != -1) {
    if (monthFlagIndex + 1 >= args.length) {
      stderr.writeln(
        'Error: --month requires a value, e.g. --month "February \'26"',
      );
      exit(64);
    }
    monthFilter = args[monthFlagIndex + 1].trim();
  }

  final file = File(filePath);
  if (!await file.exists()) {
    stderr.writeln('Error: file not found: $filePath');
    exit(66);
  }

  final lines = await file.readAsLines();

  final totals = _sumHoursByProject(lines, monthFilter: monthFilter);
  if (totals.isEmpty) {
    stderr.writeln(
      'No project hours found.'
      '${monthFilter != null ? ' (Month filter: "$monthFilter")' : ''}',
    );
    exit(0);
  }

  if (wantJson) {
    // Lightweight JSON without extra deps.
    final keys = totals.keys.toList()..sort();
    final json =
        '{' +
        keys.map((k) => '"$k": ${_formatDouble(totals[k]!)}').join(', ') +
        '}';
    stdout.writeln(json);
  } else {
    final keys = totals.keys.toList()..sort();
    final monthShown = _selectedMonthHeader(lines, monthFilter);
    if (monthShown != null) {
      stdout.writeln('Month: $monthShown');
    }
    stdout.writeln('Totals by project:');
    for (final code in keys) {
      stdout.writeln('  $code: ${_formatDouble(totals[code]!)}h');
    }
    stdout.writeln(
      'Grand total: ${_formatDouble(totals.values.fold(0.0, (a, b) => a + b))}h',
    );
  }
}

Map<String, double> _sumHoursByProject(
  List<String> lines, {
  String? monthFilter,
}) {
  // Month header: "## February '26" (any H2)
  final monthHeaderRe = RegExp(r'^\s*##\s+(.+?)\s*$');
  // Date line: "- [[2026-02-02]]" (optionally other link text)
  final dateLineRe = RegExp(r'^\s*-\s*\[\[(\d{4}-\d{2}-\d{2})\]\]\s*$');
  // Project entry line (flexible spacing):
  // "- [CODE] Something [8h]" or "- [CODE] Something[8h]"
  final projectLineRe = RegExp(
    r'^\s*-\s*\[([A-Za-z0-9_-]+)\]\s*(.*?)\s*\[\s*([0-9]*\.?[0-9]+)\s*h\s*\]\s*$',
  );

  bool inSelectedMonth = false;
  bool monthSelectedAtLeastOnce = false;

  String? selectedMonthName;

  final totals = <String, double>{};

  for (final rawLine in lines) {
    final line = rawLine.replaceAll(
      '\u00A0',
      ' ',
    ); // normalize non-breaking spaces

    final mh = monthHeaderRe.firstMatch(line);
    if (mh != null) {
      final header = mh.group(1)!.trim();
      if (monthFilter == null) {
        // select the first month header and keep collecting until next month header
        if (!monthSelectedAtLeastOnce) {
          inSelectedMonth = true;
          monthSelectedAtLeastOnce = true;
          selectedMonthName = header;
        } else {
          // reached next month; stop collecting
          inSelectedMonth = false;
        }
      } else {
        inSelectedMonth = header == monthFilter;
        if (inSelectedMonth) selectedMonthName = header;
      }
      continue;
    }

    if (!inSelectedMonth) continue;

    // (Optional) Validate we're within date blocks. Not strictly needed for summing.
    if (dateLineRe.hasMatch(line)) {
      continue;
    }

    final pm = projectLineRe.firstMatch(line);
    if (pm != null) {
      final code = pm.group(1)!.trim();
      final hoursStr = pm.group(3)!.trim();
      final hours = double.tryParse(hoursStr);
      if (hours != null) {
        totals[code] = (totals[code] ?? 0) + hours;
      }
    }
  }

  // If monthFilter was provided but never matched any header, return empty.
  if (monthFilter != null && selectedMonthName == null) return {};

  return totals;
}

String? _selectedMonthHeader(List<String> lines, String? monthFilter) {
  final monthHeaderRe = RegExp(r'^\s*##\s+(.+?)\s*$');
  if (monthFilter != null) return monthFilter;

  for (final line in lines) {
    final mh = monthHeaderRe.firstMatch(line);
    if (mh != null) return mh.group(1)!.trim();
  }
  return null;
}

String _formatDouble(double v) {
  // Show integers without .0, otherwise keep up to 2 decimals.
  if (v == v.roundToDouble()) return v.toInt().toString();
  final s = v.toStringAsFixed(2);
  return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}
