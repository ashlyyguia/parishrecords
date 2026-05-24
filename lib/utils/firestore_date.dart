import 'package:cloud_firestore/cloud_firestore.dart';

/// Parses Firestore [Timestamp], [DateTime], ISO strings, or epoch millis.
DateTime? parseFirestoreDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  if (value is Timestamp) return value.toDate().toLocal();
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim())?.toLocal();
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
  }
  return null;
}
