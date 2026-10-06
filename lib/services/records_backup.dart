import '../models/record.dart';

/// Serializes parish records into JSON-ready maps for the records-page
/// backup download. Shape matches the existing AdminBackupPage export.
List<Map<String, dynamic>> recordsToBackupJson(List<ParishRecord> records) {
  return records
      .map(
        (r) => <String, dynamic>{
          'id': r.id,
          'type': r.type.name,
          'name': r.name,
          'date': r.date.toIso8601String(),
          'imagePath': r.imagePath,
          'parish': r.parish,
          'notes': r.notes,
          'certificateStatus': r.certificateStatus.name,
        },
      )
      .toList();
}
