import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Prints a register OCR response to the console (the browser console on
/// web, `flutter run` output on mobile) so a scan can be checked without the
/// review table. Debug builds only: release builds and the deployed web app
/// print nothing.
void logOcrScanResult(String kind, Map<String, dynamic> data) {
  if (!kDebugMode) return;
  final rows = data['rows'] is List ? data['rows'] as List : const [];
  final warnings = data['warnings'];
  debugPrint('[OCR $kind] scanId=${data['scanId']}  rows=${rows.length}'
      '  rotation=${data['rotation']}'
      '${warnings is List && warnings.isNotEmpty ? '  warnings=$warnings' : ''}');
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (row is! Map) continue;
    // Baptismal rows nest their cells under 'fields'; marriage rows keep
    // them on the row itself.
    final fields = row['fields'] is Map ? row['fields'] : row;
    final parts = <String>[];
    void add(String name, dynamic value) {
      if (value is Map && value.containsKey('value')) value = value['value'];
      if (value is Map) {
        // Marriage rows nest the groom's and bride's details one level down.
        value.forEach((k, v) => add('$name.$k', v));
        return;
      }
      if (value is List) return;
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) parts.add('$name="$text"');
    }

    if (fields is Map) fields.forEach((name, cell) => add('$name', cell));
    debugPrint('[OCR $kind] row ${i + 1} (line ${row['lineNo'] ?? '-'}): '
        '${parts.isEmpty ? '(empty)' : parts.join('  ')}');
  }
  debugPrint('[OCR $kind] raw JSON: ${jsonEncode(data)}');
}
