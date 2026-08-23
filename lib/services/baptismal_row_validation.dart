import '../models/baptismal_register_row.dart';
import '../models/record.dart';
import 'register_ocr_parser.dart';

/// One problem found in a row. [blocking] issues prevent saving; non-blocking
/// ones (duplicates) are warnings the user may knowingly override.
class RowIssue {
  const RowIssue({
    required this.rowIndex,
    required this.field,
    required this.message,
    required this.blocking,
  });

  final int rowIndex;
  final String field;
  final String message;
  final bool blocking;
}

/// Parses the baptism date out of a row, or null when it isn't readable.
DateTime? baptismDateOf(BaptismalRegisterRow row) {
  final text = row.field('dateOfBaptism').value.trim();
  if (text.isEmpty) return null;
  return RegisterOcrParser.parseDate(text);
}

/// Pulls a birth date out of the free-text "place & date of birth" cell.
/// Returns null when no date is present — that is normal, not an error.
DateTime? _birthDateOf(BaptismalRegisterRow row) {
  final text = row.field('placeAndBirthDate').value.trim();
  if (text.isEmpty) return null;
  return RegisterOcrParser.parseDate(text);
}

String _dupKey(String name, DateTime date) =>
    '${name.trim().toLowerCase()}|${date.year}-${date.month}-${date.day}';

/// Validates the selected rows before they are saved.
///
/// Nothing here touches Firestore or the UI, so it is cheap to test.
List<RowIssue> validateBaptismalRows(
  List<BaptismalRegisterRow> rows, {
  List<ParishRecord> existing = const [],
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final issues = <RowIssue>[];

  final seen = <String>{
    for (final r in existing)
      if (r.type == RecordType.baptism) _dupKey(r.name, r.date),
  };

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (!row.selected) continue;

    final name = row.field('nameOfChild').value.trim();
    if (name.isEmpty) {
      issues.add(RowIssue(
        rowIndex: i,
        field: 'nameOfChild',
        message: 'Name of child is required.',
        blocking: true,
      ));
    }

    final dateText = row.field('dateOfBaptism').value.trim();
    final date = baptismDateOf(row);
    if (dateText.isEmpty) {
      issues.add(RowIssue(
        rowIndex: i,
        field: 'dateOfBaptism',
        message: 'Date of baptism is required.',
        blocking: true,
      ));
      continue;
    }
    if (date == null) {
      issues.add(RowIssue(
        rowIndex: i,
        field: 'dateOfBaptism',
        message: 'Date of baptism is not a readable date (try "12 May 2016").',
        blocking: true,
      ));
      continue;
    }
    if (date.isAfter(today)) {
      issues.add(RowIssue(
        rowIndex: i,
        field: 'dateOfBaptism',
        message: 'Date of baptism is in the future.',
        blocking: true,
      ));
      continue;
    }
    if (date.year < 1900) {
      issues.add(RowIssue(
        rowIndex: i,
        field: 'dateOfBaptism',
        message: 'Date of baptism is before 1900 — check the year.',
        blocking: true,
      ));
      continue;
    }

    final birth = _birthDateOf(row);
    if (birth != null && birth.isAfter(date)) {
      issues.add(RowIssue(
        rowIndex: i,
        field: 'placeAndBirthDate',
        message: 'Date of birth is after the date of baptism.',
        blocking: true,
      ));
    }

    if (name.isNotEmpty) {
      final key = _dupKey(name, date);
      if (seen.contains(key)) {
        issues.add(RowIssue(
          rowIndex: i,
          field: 'nameOfChild',
          message: 'A baptism for this name and date already exists.',
          blocking: false,
        ));
      } else {
        seen.add(key);
      }
    }
  }

  return issues;
}
