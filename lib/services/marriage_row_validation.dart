import '../models/record.dart';
import '../models/register_marriage_entry.dart';

/// One problem found in a marriage row. [blocking] issues prevent saving;
/// non-blocking ones (duplicates) are warnings the user may knowingly override.
class MarriageRowIssue {
  const MarriageRowIssue({
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

/// The couple key used to detect a duplicate against already-saved records:
/// "<groom> & <bride>", case-insensitive. A marriage record's `name` is stored
/// in exactly that form (see [RegisterMarriageEntry.recordDisplayName]).
String _coupleKey(String name) => name.trim().toLowerCase();

/// Validates the selected marriage rows before they are saved.
///
/// Blocking rules: both the groom and bride name must be present (min length
/// 2). The date is optional -- it defaults to today at save -- so it never
/// blocks. Non-blocking: a couple whose "<groom> & <bride>" name already exists
/// among saved marriage records is flagged as a possible duplicate.
///
/// Nothing here touches Firestore or the UI, so it is cheap to test.
List<MarriageRowIssue> validateMarriageRows(
  List<RegisterMarriageEntry> entries, {
  List<ParishRecord> existing = const [],
  DateTime? now,
}) {
  final issues = <MarriageRowIssue>[];

  final seen = <String>{
    for (final r in existing)
      if (r.type == RecordType.marriage) _coupleKey(r.name),
  };

  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    if (!entry.selected) continue;

    final groom = entry.groom.name.trim();
    final bride = entry.bride.name.trim();

    if (groom.length < 2) {
      issues.add(MarriageRowIssue(
        rowIndex: i,
        field: 'groomName',
        message: "Groom's name is required.",
        blocking: true,
      ));
    }
    if (bride.length < 2) {
      issues.add(MarriageRowIssue(
        rowIndex: i,
        field: 'brideName',
        message: "Bride's name is required.",
        blocking: true,
      ));
    }

    if (groom.length >= 2 && bride.length >= 2) {
      final key = _coupleKey(entry.recordDisplayName);
      if (seen.contains(key)) {
        issues.add(MarriageRowIssue(
          rowIndex: i,
          field: 'groomName',
          message: 'A marriage for this couple already exists.',
          blocking: false,
        ));
      } else {
        seen.add(key);
      }
    }
  }

  return issues;
}
