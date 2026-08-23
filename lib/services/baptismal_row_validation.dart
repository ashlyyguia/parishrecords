import '../models/baptismal_register_row.dart';
import '../models/record.dart';
import 'register_ocr_parser.dart';

/// Guards against `RegisterOcrParser.parseDate`'s silent rollover.
///
/// `RegisterOcrParser._safeDate` (in `register_ocr_parser.dart`, which is on
/// the do-not-modify list for this task -- the legacy OCR path must keep
/// working unchanged) builds dates with `DateTime(year, month, day)`. That
/// constructor never rejects an out-of-range day/month -- it silently ROLLS
/// OVER into the next period instead: `DateTime(2016, 2, 31)` does not throw,
/// it returns 2 March 2016. An OCR misread of "31 FEBRUARY 2016" (a smudged
/// "2" read as "3" on the day, or a genuine transcription error in the real
/// register) therefore validates cleanly as a plausible date and would save
/// silently as the WRONG calendar date with no error anywhere.
///
/// This mirrors (does not call -- those patterns are private to
/// `RegisterOcrParser`) the same written/ISO/slash date regexes
/// `RegisterOcrParser.parseDate` matches against, so the round-trip check
/// below compares the parsed result against the SAME literal digits the
/// parser consumed, not a re-interpretation of the input string. If the
/// parsed date's day/month don't match what the input literally asked for,
/// the date is treated as unparseable (null) here -- which routes through
/// the existing "not a readable date" blocking issue below, so a rolled-over
/// date can never silently reach Save.
final RegExp _writtenDateGuardPattern = RegExp(
  r'^(\d{1,2})\s+'
  r'(January|February|March|April|May|June|July|August|September|October|November|December)'
  r'\s+(\d{4})$',
  caseSensitive: false,
);
final RegExp _isoDateGuardPattern = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');
final RegExp _slashDateGuardPattern =
    RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})$');

const Map<String, int> _guardMonthNames = {
  'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5,
  'june': 6, 'july': 7, 'august': 8, 'september': 9, 'october': 10,
  'november': 11, 'december': 12,
};

/// Parses [text] the same way [RegisterOcrParser.parseDate] would, but
/// returns null (instead of a rolled-over date) when the constructed date's
/// day/month don't round-trip to what the input literally specified.
DateTime? _safeParseDate(String text) {
  final trimmed = text.trim();
  final parsed = RegisterOcrParser.parseDate(trimmed);
  if (parsed == null) return null;

  final written = _writtenDateGuardPattern.firstMatch(trimmed);
  if (written != null) {
    final day = int.parse(written.group(1)!);
    final month = _guardMonthNames[written.group(2)!.toLowerCase()];
    if (parsed.day != day || parsed.month != month) return null;
    return parsed;
  }

  final iso = _isoDateGuardPattern.firstMatch(trimmed);
  if (iso != null) {
    final month = int.parse(iso.group(2)!);
    final day = int.parse(iso.group(3)!);
    if (parsed.day != day || parsed.month != month) return null;
    return parsed;
  }

  final slash = _slashDateGuardPattern.firstMatch(trimmed);
  if (slash != null) {
    // Mirrors RegisterOcrParser.parseDate's own day/month disambiguation
    // heuristic for this format (whichever literal value exceeds 12 must be
    // the day) -- duplicated here rather than modified in place, since that
    // file is on the do-not-touch list.
    final a = int.parse(slash.group(1)!);
    final b = int.parse(slash.group(2)!);
    int month;
    int day;
    if (a > 12 && b <= 12) {
      day = a;
      month = b;
    } else if (b > 12 && a <= 12) {
      month = a;
      day = b;
    } else {
      month = a;
      day = b;
    }
    if (parsed.day != day || parsed.month != month) return null;
    return parsed;
  }

  // A format `parseDate` didn't recognize by any of the above patterns but
  // still returned non-null for is unexpected under the current parser; be
  // conservative and trust it rather than guessing at a format to validate.
  return parsed;
}

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
///
/// Uses [_safeParseDate], not `RegisterOcrParser.parseDate` directly, so an
/// invalid calendar date that the parser's `DateTime(y, m, d)` construction
/// would otherwise silently roll over (e.g. "31 FEBRUARY 2016" -> 2 March
/// 2016) comes back as null here -- which [validateBaptismalRows] already
/// turns into a blocking "not a readable date" issue below.
DateTime? baptismDateOf(BaptismalRegisterRow row) {
  final text = row.field('dateOfBaptism').value.trim();
  if (text.isEmpty) return null;
  return _safeParseDate(text);
}

/// Pulls a birth date out of the free-text "place & date of birth" cell.
/// Returns null when no date is present — that is normal, not an error.
DateTime? _birthDateOf(BaptismalRegisterRow row) {
  final text = row.field('placeAndBirthDate').value.trim();
  if (text.isEmpty) return null;
  return _safeParseDate(text);
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
