import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

/// A parish register entry offered when verifying a certificate request.
class RegisterRecordOption {
  const RegisterRecordOption({
    required this.id,
    required this.name,
    this.date,
    this.details = '',
    this.fields = const [],
  });

  final String id;
  final String name;
  final DateTime? date;

  /// Extra text to help tell entries apart (e.g. parents, Vol./Page).
  final String details;

  /// Every register detail stored for the entry (parents, sponsors,
  /// minister, Vol./Series/Line, ...), as label/value pairs in reading order.
  final List<MapEntry<String, String>> fields;
}

/// Turns a register record's stored details into readable label/value pairs.
/// Works for every register format the app writes (manual forms, baptismal
/// and marriage OCR, older entries): known keys get proper labels, unknown
/// ones are humanised, nested groom/bride details are prefixed, and internal
/// bookkeeping (scan ids, image paths, raw OCR lines) is left out.
List<MapEntry<String, String>> registerRecordFields(
  Map<String, dynamic> record,
) {
  final notes = _decodeNotes(record['notes']);
  final out = <MapEntry<String, String>>[];
  final seen = <String>{};

  void add(String label, Object? value) {
    final v = _plain(value);
    if (v.isEmpty) return;
    final key = '$label|$v';
    if (seen.add(key)) out.add(MapEntry(label, v));
  }

  void walk(Map<String, dynamic> map, String prefix) {
    final keys = map.keys.toList()
      ..sort((a, b) => _rank(a).compareTo(_rank(b)));
    for (final k in keys) {
      if (_skipKeys.contains(k) || _looksInternal(k)) continue;
      final v = map[k];
      final label = '$prefix${_labels[k] ?? _humanise(k)}';
      if (v is Map) {
        walk(Map<String, dynamic>.from(v), '$label — ');
      } else if (v is List) {
        add(label, v.map(_plain).where((e) => e.isNotEmpty).join(', '));
      } else {
        add(label, v);
      }
    }
  }

  if (notes != null) {
    walk(notes, '');
  } else {
    final raw = (record['notes'] ?? '').toString().trim();
    if (raw.isNotEmpty) add('Notes', raw);
  }
  final source = _plain(record['source']);
  if (source.isNotEmpty &&
      source != 'Parish Register' &&
      source != 'register_ocr') {
    add('Residence / source', source);
  }
  final status = _plain(record['record_status']);
  if (status.isNotEmpty) add('Record status', status);
  return out;
}

Map<String, dynamic>? _decodeNotes(Object? notes) {
  if (notes is Map) return Map<String, dynamic>.from(notes);
  if (notes is! String || notes.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(notes);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

String _plain(Object? v) {
  if (v == null) return '';
  if (v is Timestamp) {
    final d = v.toDate();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
  final s = v.toString().trim();
  return (s == 'null') ? '' : s;
}

const _skipKeys = {
  'source',
  'status',
  'sacramentType',
  'rawLine',
  'ocrScanId',
  'scanId',
  'originalImagePath',
  'imagePath',
  'image_ref',
  'contractingParties',
  'id',
  'uid',
  'created_by_uid',
};

bool _looksInternal(String k) {
  final l = k.toLowerCase();
  return l.contains('image') ||
      l.contains('url') ||
      l.endsWith('uid') ||
      l.contains('confidence');
}

const _labels = <String, String>{
  'volNo': 'Vol. No.',
  'seriesNo': 'Series',
  'pageNo': 'Page No.',
  'lineNo': 'Line No.',
  'nameOfChild': 'Name of child',
  'placeAndBirthDate': 'Place & date of birth',
  'legitimacy': 'L or ILL',
  'parents': 'Parents',
  'residentsOf': 'Residents of',
  'dateOfBaptism': 'Date of baptism',
  'dateOfConfirmation': 'Date of confirmation',
  'dateOfMarriage': 'Date of marriage',
  'dateOfDeath': 'Date of death',
  'dateOfBurial': 'Date of burial',
  'minister': 'Minister',
  'sponsors': 'Sponsors',
  'witnesses': 'Witnesses',
  'licenseNumber': 'License No.',
  'observations': 'Observations',
  'groom': 'Groom',
  'bride': 'Bride',
  'name': 'Name',
  'legalStatus': 'Legal status',
  'actualAddress': 'Address',
  'datesPlaceOfBirth': 'Date & place of birth',
  'datesPlaceOfBaptism': 'Date & place of baptism',
  'fatherName': "Father's name",
  'motherName': "Mother's name",
  'father': 'Father',
  'mother': 'Mother',
  'causeOfDeath': 'Cause of death',
  'placeOfBurial': 'Place of burial',
  'age': 'Age',
};

/// Reading order: register position first, then the person, then the rest.
int _rank(String k) {
  const order = [
    'volNo', 'seriesNo', 'pageNo', 'lineNo',
    'nameOfChild', 'name', 'groom', 'bride',
    'placeAndBirthDate', 'datesPlaceOfBirth', 'legitimacy',
    'parents', 'father', 'fatherName', 'mother', 'motherName',
    'residentsOf', 'actualAddress', 'legalStatus',
    'dateOfBaptism', 'dateOfConfirmation', 'dateOfMarriage',
    'datesPlaceOfBaptism', 'dateOfDeath', 'causeOfDeath', 'dateOfBurial',
    'placeOfBurial', 'minister', 'sponsors', 'witnesses', 'licenseNumber',
    'observations',
  ];
  final i = order.indexOf(k);
  return i == -1 ? order.length : i;
}

String _humanise(String key) {
  final spaced = key
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .trim();
  if (spaced.isEmpty) return key;
  final lower = spaced.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}

/// Looks up entries in the parish register collections.
class RegisterRecordSearch {
  RegisterRecordSearch({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static String collectionFor(String requestType) {
    switch (requestType.trim().toLowerCase()) {
      case 'marriage':
        return 'marriage_records';
      case 'confirmation':
        return 'confirmation_records';
      case 'death':
      case 'funeral':
        return 'funeral_records';
      case 'baptism':
      default:
        return 'baptism_records';
    }
  }

  static RegisterRecordOption _fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final created = d['created_at'];
    DateTime? date;
    if (created is Timestamp) date = created.toDate();
    return RegisterRecordOption(
      id: doc.id,
      name: (d['text'] ?? d['name'] ?? '').toString().trim(),
      date: date,
      fields: registerRecordFields(d),
    );
  }

  /// The record already linked to a request, if it still exists.
  Future<RegisterRecordOption?> byId(String requestType, String id) async {
    if (id.trim().isEmpty) return null;
    final snap = await _db.collection(collectionFor(requestType)).doc(id).get();
    if (!snap.exists) return null;
    return _fromDoc(snap);
  }

  /// Register entries whose name contains every word of [query]
  /// (case-insensitive), most recent first.
  Future<List<RegisterRecordOption>> search(
    String requestType,
    String query, {
    int limit = 25,
  }) async {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const [];
    final snap = await _db
        .collection(collectionFor(requestType))
        .orderBy('created_at', descending: true)
        .limit(1000)
        .get();
    final out = <RegisterRecordOption>[];
    for (final doc in snap.docs) {
      final option = _fromDoc(doc);
      final name = option.name.toLowerCase();
      if (words.every(name.contains)) out.add(option);
      if (out.length >= limit) break;
    }
    return out;
  }
}
