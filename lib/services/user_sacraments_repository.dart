import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class UserSacramentsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _timeout = Duration(seconds: 20);
  static final _dateFormat = DateFormat.yMMMMd();

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw Exception('Not authenticated');
    return uid;
  }

  String _collectionForType(String type) {
    switch (type.toLowerCase()) {
      case 'baptism':
        return 'baptism_records';
      case 'marriage':
        return 'marriage_records';
      case 'confirmation':
        return 'confirmation_records';
      case 'death':
      case 'funeral':
      case 'burial':
        return 'funeral_records';
      default:
        return 'records';
    }
  }

  String _typeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'baptism':
        return 'Baptism';
      case 'marriage':
        return 'Marriage';
      case 'confirmation':
        return 'Confirmation';
      case 'death':
      case 'funeral':
      case 'burial':
        return 'Death / Funeral';
      default:
        return type.isEmpty ? 'Sacrament' : type;
    }
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  String? _certificateUrl(Map<String, dynamic> data) {
    final ref = (data['certificate_url'] ??
            data['certificateUrl'] ??
            data['image_ref'] ??
            data['imagePath'])
        ?.toString()
        .trim();
    if (ref == null || ref.isEmpty) return null;
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return ref;
    }
    return null;
  }

  String _titleFromRecordData(Map<String, dynamic> data, String fallback) {
    final text = (data['text'] ?? data['name'] ?? '').toString().trim();
    if (text.isNotEmpty) return text;

    final notes = data['notes'];
    Map<String, dynamic>? decoded;
    if (notes is String && notes.trim().startsWith('{')) {
      try {
        final d = json.decode(notes);
        if (d is Map<String, dynamic>) decoded = d;
      } catch (_) {}
    } else if (notes is Map<String, dynamic>) {
      decoded = notes;
    }

    if (decoded != null) {
      for (final key in ['child', 'confirmand', 'groom', 'bride', 'deceased', 'person']) {
        final nested = decoded[key];
        if (nested is Map<String, dynamic>) {
          final name = (nested['fullName'] ?? nested['name'] ?? '').toString().trim();
          if (name.isNotEmpty) return name;
        }
      }
      final full = decoded['fullName']?.toString().trim();
      if (full != null && full.isNotEmpty) return full;
    }

    return fallback;
  }

  Future<Map<String, dynamic>?> _fetchRecordDoc(String type, String id) async {
    final collection = _collectionForType(type);
    try {
      final doc = await _firestore
          .collection(collection)
          .doc(id)
          .get()
          .timeout(_timeout);
      if (doc.exists) {
        return {'id': doc.id, 'type': type, ...doc.data()!};
      }
    } catch (_) {}

    try {
      final doc = await _firestore
          .collection('records')
          .doc(id)
          .get()
          .timeout(_timeout);
      if (doc.exists) {
        final data = doc.data()!;
        final legacyType = (data['type'] ?? type).toString();
        return {'id': doc.id, 'type': legacyType, ...data};
      }
    } catch (_) {}

    return null;
  }

  Future<Map<String, dynamic>> _hydrateEntry({
    required String type,
    required String id,
    required String memberName,
    String? cachedTitle,
    dynamic cachedDate,
  }) async {
    final record = await _fetchRecordDoc(type, id);
    final resolvedType =
        (record?['type'] ?? type).toString().toLowerCase();
    final label = _typeLabel(resolvedType);

    if (record == null) {
      final dt = _parseDate(cachedDate);
      return {
        'id': id,
        'record_id': id,
        'type': resolvedType,
        'sacrament_type': resolvedType,
        'title': cachedTitle?.isNotEmpty == true ? cachedTitle! : memberName,
        'date': dt != null ? _dateFormat.format(dt) : '',
        'date_raw': cachedDate,
        'member_name': memberName,
        'certificate_url': '',
        'certificate_status': '',
        'parish': '',
        'sacrament_label': label,
      };
    }

    final dt = _parseDate(record['created_at'] ?? record['createdAt']) ??
        _parseDate(cachedDate);
    final title = _titleFromRecordData(
      record,
      cachedTitle?.isNotEmpty == true ? cachedTitle! : memberName,
    );
    final certUrl = _certificateUrl(record) ?? '';
    final status = (record['certificate_status'] ??
            record['certificateStatus'] ??
            '')
        .toString();

    return {
      'id': id,
      'record_id': id,
      'type': resolvedType,
      'sacrament_type': resolvedType,
      'title': title,
      'date': dt != null ? _dateFormat.format(dt) : '',
      'date_raw': dt?.toIso8601String(),
      'member_name': memberName,
      'certificate_url': certUrl,
      'certificate_status': status,
      'parish': (record['parish'] ?? record['source'] ?? '').toString(),
      'sacrament_label': label,
      'record_status': (record['record_status'] ?? '').toString(),
    };
  }

  /// Sacraments linked to the user's household members, plus records they created.
  Future<List<Map<String, dynamic>>> listMine({int limit = 30}) async {
    final uid = _requireUid();
    final stubs = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addStub({
      required String type,
      required String id,
      required String memberName,
      String? cachedTitle,
      dynamic cachedDate,
    }) {
      if (id.isEmpty || type.isEmpty) return;
      final key = '${type.toLowerCase()}:$id';
      if (seen.contains(key)) return;
      seen.add(key);
      stubs.add({
        'type': type.toLowerCase(),
        'id': id,
        'member_name': memberName,
        'cached_title': cachedTitle,
        'cached_date': cachedDate,
      });
    }

    try {
      final userSnap = await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(_timeout);
      final linkedHouseholdId =
          userSnap.data()?['linkedHouseholdId']?.toString();

      final householdIds = <String>{};
      if (linkedHouseholdId != null && linkedHouseholdId.isNotEmpty) {
        householdIds.add(linkedHouseholdId);
      }

      final ownedSnap = await _firestore
          .collection('households')
          .where('created_by', isEqualTo: uid)
          .where('isArchived', isEqualTo: false)
          .get()
          .timeout(_timeout);
      for (final doc in ownedSnap.docs) {
        householdIds.add(doc.id);
      }

      for (final householdId in householdIds) {
        final membersSnap = await _firestore
            .collection('household_members')
            .where('householdId', isEqualTo: householdId)
            .where('isActive', isEqualTo: true)
            .get()
            .timeout(_timeout);

        for (final memberDoc in membersSnap.docs) {
          final m = memberDoc.data();
          final memberName =
              (m['fullName'] ?? m['firstName'] ?? 'Member').toString();

          final cached = m['linkedSacraments'];
          if (cached is List) {
            for (final raw in cached) {
              if (raw is! Map) continue;
              addStub(
                type: raw['type']?.toString() ?? '',
                id: raw['recordId']?.toString() ?? '',
                memberName: raw['memberName']?.toString() ?? memberName,
                cachedTitle: raw['title']?.toString(),
                cachedDate: raw['date'],
              );
            }
          }

          const fields = {
            'baptismRecordId': 'baptism',
            'confirmationRecordId': 'confirmation',
            'marriageRecordId': 'marriage',
            'deathRecordId': 'death',
          };
          for (final entry in fields.entries) {
            final recordId = m[entry.key]?.toString();
            if (recordId == null || recordId.isEmpty) continue;
            addStub(
              type: entry.value,
              id: recordId,
              memberName: memberName,
            );
          }
        }
      }
    } catch (_) {}

    final collections = [
      ('baptism_records', 'baptism'),
      ('marriage_records', 'marriage'),
      ('confirmation_records', 'confirmation'),
      ('funeral_records', 'death'),
    ];

    for (final (collection, type) in collections) {
      try {
        final snap = await _firestore
            .collection(collection)
            .where('created_by_uid', isEqualTo: uid)
            .orderBy('created_at', descending: true)
            .limit(limit)
            .get()
            .timeout(_timeout);

        for (final doc in snap.docs) {
          addStub(
            type: type,
            id: doc.id,
            memberName: 'You',
            cachedTitle: (doc.data()['text'] ?? doc.data()['name'])?.toString(),
            cachedDate: doc.data()['created_at'],
          );
        }
      } catch (_) {}
    }

    final hydrated = <Map<String, dynamic>>[];
    for (final stub in stubs) {
      if (hydrated.length >= limit) break;
      final row = await _hydrateEntry(
        type: stub['type'] as String,
        id: stub['id'] as String,
        memberName: stub['member_name'] as String,
        cachedTitle: stub['cached_title'] as String?,
        cachedDate: stub['cached_date'],
      );
      hydrated.add(row);
    }

    hydrated.sort((a, b) {
      final aDate = a['date_raw']?.toString() ?? a['date']?.toString() ?? '';
      final bDate = b['date_raw']?.toString() ?? b['date']?.toString() ?? '';
      return bDate.compareTo(aDate);
    });

    return hydrated;
  }

  Future<void> requestCorrection(
    String recordId, {
    required String message,
  }) async {
    final uid = _requireUid();

    await _firestore
        .collection('correction_tickets')
        .add({
          'record_id': recordId,
          'message': message,
          'created_by_uid': uid,
          'created_at': FieldValue.serverTimestamp(),
          'status': 'pending',
        })
        .timeout(_timeout);
  }
}
