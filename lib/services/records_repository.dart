import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/record.dart';

class RecordsRepository {
  static const Duration _timeout = Duration(seconds: 20);

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw Exception('Not authenticated');
    return uid;
  }

  String _collectionForType(RecordType type) {
    switch (type) {
      case RecordType.baptism:
        return 'baptism_records';
      case RecordType.marriage:
        return 'marriage_records';
      case RecordType.confirmation:
        return 'confirmation_records';
      case RecordType.funeral:
        return 'funeral_records';
    }
  }

  ParishRecord _fromFirestore(
    RecordType type,
    String id,
    Map<String, dynamic> r,
  ) {
    final createdAt = r['created_at'] ?? r['createdAt'];
    DateTime date;
    if (createdAt is Timestamp) {
      date = createdAt.toDate();
    } else if (createdAt is String) {
      date = DateTime.tryParse(createdAt) ?? DateTime.now();
    } else if (createdAt is DateTime) {
      date = createdAt;
    } else {
      date = DateTime.now();
    }
    final name =
        (r['text'] as String?) ?? (r['name'] as String?) ?? 'Unnamed Record';
    CertificateStatus certificateStatus = CertificateStatus.pending;
    final rawStatus = r['certificate_status'] ?? r['certificateStatus'];
    if (rawStatus is String) {
      certificateStatus = CertificateStatusExtension.fromString(rawStatus);
    } else if (rawStatus is int &&
        rawStatus < CertificateStatus.values.length) {
      certificateStatus = CertificateStatus.values[rawStatus];
    }
    final notes = (r['notes'] as String?) ?? (r['source'] as String?);

    return ParishRecord(
      id: id,
      type: type,
      name: name,
      date: date,
      imagePath: r['image_ref'] as String?,
      parish: r['parish'] as String?,
      notes: notes,
      certificateStatus: certificateStatus,
    );
  }

  Map<String, dynamic>? _buildBaptismData(String? notesJson) {
    if (notesJson == null || notesJson.isEmpty) return null;
    try {
      final decoded = json.decode(notesJson) as Map<String, dynamic>;
      final registry = (decoded['registry'] as Map<String, dynamic>?) ?? {};
      final child = (decoded['child'] as Map<String, dynamic>?) ?? {};
      final parents = (decoded['parents'] as Map<String, dynamic>?) ?? {};
      final godparents = (decoded['godparents'] as Map<String, dynamic>?) ?? {};
      final baptism = (decoded['baptism'] as Map<String, dynamic>?) ?? {};
      final metadata = (decoded['metadata'] as Map<String, dynamic>?) ?? {};

      return {
        'registryNo': registry['registryNo']?.toString(),
        'bookNo': registry['bookNo']?.toString(),
        'pageNo': registry['pageNo']?.toString(),
        'lineNo': registry['lineNo']?.toString(),
        'childName': child['fullName']?.toString(),
        'childGender': child['gender']?.toString(),
        'dateOfBirth': child['dateOfBirth']?.toString(),
        'placeOfBirth': child['placeOfBirth']?.toString(),
        'fatherName': parents['father']?.toString(),
        'motherName': parents['mother']?.toString(),
        'godfatherName': godparents['godfather1']?.toString(),
        'godmotherName': godparents['godmother1']?.toString(),
        'ministerName': baptism['minister']?.toString(),
        'dateOfBaptism': baptism['date']?.toString(),
        'placeOfBaptism': baptism['place']?.toString(),
        'certificateIssued': metadata['certificateIssued'] == true,
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _buildMarriageData(String? notesJson) {
    if (notesJson == null || notesJson.isEmpty) return null;
    try {
      final decoded = json.decode(notesJson) as Map<String, dynamic>;
      final marriage = (decoded['marriage'] as Map<String, dynamic>?) ?? {};
      final groom = (decoded['groom'] as Map<String, dynamic>?) ?? {};
      final bride = (decoded['bride'] as Map<String, dynamic>?) ?? {};
      final witnesses = (decoded['witnesses'] as Map<String, dynamic>?) ?? {};

      return {
        'registryNo': null,
        'groomName': groom['fullName']?.toString(),
        'brideName': bride['fullName']?.toString(),
        'dateOfMarriage': marriage['date']?.toString(),
        'placeOfMarriage': marriage['place']?.toString(),
        'witness1Name': witnesses['witness1']?.toString(),
        'witness2Name': witnesses['witness2']?.toString(),
        'ministerName': marriage['officiant']?.toString(),
        'certificateIssued': false,
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _buildConfirmationData(String? notesJson) {
    if (notesJson == null || notesJson.isEmpty) return null;
    try {
      final decoded = json.decode(notesJson) as Map<String, dynamic>;
      final confirmand = (decoded['confirmand'] as Map<String, dynamic>?) ?? {};
      final sponsor = (decoded['sponsor'] as Map<String, dynamic>?) ?? {};
      final confirmation =
          (decoded['confirmation'] as Map<String, dynamic>?) ?? {};

      return {
        'registryNo': null,
        'confirmedName': confirmand['fullName']?.toString(),
        'dateOfConfirmation': confirmation['date']?.toString(),
        'placeOfConfirmation': confirmation['place']?.toString(),
        'sponsorName': sponsor['fullName']?.toString(),
        'ministerName': confirmation['officiant']?.toString(),
        'certificateIssued': false,
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _buildDeathData(String? notesJson) {
    if (notesJson == null || notesJson.isEmpty) return null;
    try {
      final decoded = json.decode(notesJson) as Map<String, dynamic>;
      final deceased = (decoded['deceased'] as Map<String, dynamic>?) ?? {};
      final burial = (decoded['burial'] as Map<String, dynamic>?) ?? {};

      return {
        'registryNo': null,
        'deceasedName': deceased['fullName']?.toString(),
        'dateOfDeath': deceased['dateOfDeath']?.toString(),
        'placeOfDeath': deceased['placeOfDeath']?.toString(),
        'causeOfDeath': deceased['causeOfDeath']?.toString(),
        'ageAtDeath': deceased['age']?.toString(),
        'burialDate': burial['date']?.toString(),
        'burialPlace': burial['place']?.toString(),
        'certificateIssued': false,
      };
    } catch (_) {
      return null;
    }
  }

  Future<List<ParishRecord>> list() async {
    final uid = _requireUid();
    if (uid.isEmpty) {
      return const <ParishRecord>[];
    }

    Future<List<ParishRecord>> loadType(RecordType t) async {
      final col = _collectionForType(t);
      final snap = await _db
          .collection(col)
          .orderBy('created_at', descending: true)
          .limit(500)
          .get()
          .timeout(
            _timeout,
            onTimeout: () => throw TimeoutException('Records list timed out'),
          );
      return snap.docs.map((d) => _fromFirestore(t, d.id, d.data())).toList();
    }

    try {
      final all = <ParishRecord>[];
      for (final t in RecordType.values) {
        all.addAll(await loadType(t));
      }
      all.sort((a, b) => b.date.compareTo(a.date));
      return all;
    } catch (e) {
      developer.log('Firestore load failed: $e', name: 'RecordsRepository');
      rethrow;
    }
  }

  Stream<List<ParishRecord>> watch({
    Duration interval = const Duration(seconds: 5),
  }) {
    return Stream.periodic(
      interval,
    ).asyncMap((_) => list()).distinct((a, b) => a.length == b.length);
  }

  Future<void> add(
    RecordType type,
    String name,
    DateTime date, {
    String? imagePath,
    String? parish,
    String? notes,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Record name cannot be empty');
    }

    final payload = <String, dynamic>{
      'type': type.name,
      'text': trimmedName,
      'source': parish ?? 'app',
      'image_ref': imagePath,
    };
    if (notes != null) {
      payload['notes'] = notes;
      Map<String, dynamic>? extra;
      switch (type) {
        case RecordType.baptism:
          extra = _buildBaptismData(notes);
          if (extra != null) payload['baptismData'] = extra;
          break;
        case RecordType.marriage:
          extra = _buildMarriageData(notes);
          if (extra != null) payload['marriageData'] = extra;
          break;
        case RecordType.confirmation:
          extra = _buildConfirmationData(notes);
          if (extra != null) payload['confirmationData'] = extra;
          break;
        case RecordType.funeral:
          extra = _buildDeathData(notes);
          if (extra != null) payload['deathData'] = extra;
          break;
      }
    }

    final uid = _requireUid();
    payload['created_by_uid'] = uid;
    payload['created_at'] = FieldValue.serverTimestamp();
    payload['updated_at'] = FieldValue.serverTimestamp();
    payload['certificate_status'] = CertificateStatus.pending.name;
    payload['date'] = Timestamp.fromDate(date);

    final col = _collectionForType(type);
    await _db
        .collection(col)
        .add(payload)
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Add record timed out'),
        );
  }

  Future<void> update(
    String id, {
    RecordType? type,
    String? name,
    DateTime? date,
    String? imagePath,
    String? parish,
    String? notes,
    CertificateStatus? certificateStatus,
  }) async {
    if (type == null) {
      throw Exception('Record type is required for Firebase-only update');
    }
    final data = <String, dynamic>{};
    data['type'] = type.name;
    if (name != null) data['text'] = name;
    if (imagePath != null) data['image_ref'] = imagePath;
    if (parish != null) data['source'] = parish;
    if (notes != null) data['notes'] = notes;
    if (date != null) data['date'] = Timestamp.fromDate(date);
    if (certificateStatus != null) {
      data['certificate_status'] = certificateStatus.name;
    }
    if (data.isEmpty) return;

    data['updated_at'] = FieldValue.serverTimestamp();
    final col = _collectionForType(type);
    await _db
        .collection(col)
        .doc(id)
        .set(data, SetOptions(merge: true))
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Update record timed out'),
        );
  }

  Future<void> updateCertificateStatus(
    String id,
    CertificateStatus status,
  ) async {
    throw UnimplementedError(
      'Firebase-only: updateCertificateStatus requires record type; '
      'use update(id, type: ..., ...) with certificate_status',
    );
  }

  Future<void> updateCertificateStatusForType(
    String id,
    RecordType type,
    CertificateStatus status,
  ) async {
    final col = _collectionForType(type);
    await _db.collection(col).doc(id).set({
      'certificate_status': status.name,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    throw UnimplementedError(
      'Firebase-only: delete requires record type; use deleteForType',
    );
  }

  Future<void> deleteForType(String id, RecordType type) async {
    final col = _collectionForType(type);
    await _db
        .collection(col)
        .doc(id)
        .delete()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Delete record timed out'),
        );
  }
}
