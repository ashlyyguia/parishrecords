import 'firestore_date.dart';

/// Inclusive date-range filtering for parish records and related lists.
class RecordDateFilter {
  RecordDateFilter._();

  /// Normalizes [date] to local calendar day for comparisons.
  static DateTime dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// True when [date] falls within optional [from] / [to] (inclusive by day).
  static bool matches(
    DateTime date, {
    DateTime? from,
    DateTime? to,
  }) {
    if (from == null && to == null) return true;
    final d = dayOnly(date.toLocal());
    if (from != null) {
      final f = dayOnly(from.toLocal());
      if (d.isBefore(f)) return false;
    }
    if (to != null) {
      final t = dayOnly(to.toLocal());
      if (d.isAfter(t)) return false;
    }
    return true;
  }

  /// Parses ISO-8601 or [DateTime] values from API maps.
  static bool matchesValue(
    Object? raw, {
    DateTime? from,
    DateTime? to,
  }) {
    if (from == null && to == null) return true;
    final dt = parseFirestoreDate(raw);
    if (dt == null) return false;
    return matches(dt, from: from, to: to);
  }
}
