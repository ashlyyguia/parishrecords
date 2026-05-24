import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/record.dart';
import '../models/register_ocr_entry.dart';
import '../providers/records_provider.dart';

RecordType sacramentToRecordType(String type) {
  switch (type.toLowerCase()) {
    case 'marriage':
      return RecordType.marriage;
    case 'confirmation':
      return RecordType.confirmation;
    case 'death':
      return RecordType.funeral;
    default:
      return RecordType.baptism;
  }
}

/// Creates official Firestore records from verified register OCR rows.
Future<int> saveRegisterOcrEntries({
  required WidgetRef ref,
  required List<RegisterOcrEntry> entries,
  required String recordType,
  required String volNumber,
  required String seriesNumber,
  String source = 'register_ocr_verify',
}) async {
  final toSave = entries.where((e) => e.selected && e.isValid).toList();
  if (toSave.isEmpty) return 0;

  final type = sacramentToRecordType(recordType);
  final drafts = toSave.map((e) {
    final notes = jsonEncode({
      'source': source,
      'sacramentType': recordType,
      'volNo': volNumber,
      'seriesNo': seriesNumber,
      'lineNo': e.lineNo,
      'nameOfChild': e.name.trim(),
      'placeAndBirthDate': e.placeAndBirthDate,
      'parents': e.parents,
      'residentsOf': e.residentsOf,
      'dateOfBaptism': e.baptismDateText,
      'minister': e.minister,
      'sponsors': e.sponsors,
      'rawLine': e.rawLine,
    });
    return RegisterRecordDraft(
      type: type,
      name: e.name.trim(),
      date: e.date!,
      parish: e.residentsOf.trim().isNotEmpty
          ? e.residentsOf.trim()
          : 'Parish Register',
      notes: notes,
    );
  }).toList();

  return ref.read(recordsProvider.notifier).addRecordsBatch(drafts);
}
