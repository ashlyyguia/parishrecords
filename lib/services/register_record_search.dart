import 'package:cloud_firestore/cloud_firestore.dart';

/// A parish register entry offered when verifying a certificate request.
class RegisterRecordOption {
  const RegisterRecordOption({
    required this.id,
    required this.name,
    this.date,
    this.details = '',
  });

  final String id;
  final String name;
  final DateTime? date;

  /// Extra text to help tell entries apart (e.g. parents, Vol./Page).
  final String details;
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
    final parish = (d['source'] ?? '').toString().trim();
    return RegisterRecordOption(
      id: doc.id,
      name: (d['text'] ?? d['name'] ?? '').toString().trim(),
      date: date,
      details: parish == 'Parish Register' ? '' : parish,
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
