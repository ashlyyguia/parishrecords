import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/record.dart';

class RecordsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection references based on record type
  CollectionReference _collectionForType(RecordType type) {
    switch (type) {
      case RecordType.marriage:
        return _firestore.collection('marriage_records');
      case RecordType.funeral:
        return _firestore.collection('funeral_records');
      case RecordType.confirmation:
        return _firestore.collection('confirmation_records');
      case RecordType.baptism:
        return _firestore.collection('baptism_records');
    }
  }

  String _typeString(RecordType type) {
    return type.name;
  }

  ParishRecord _fromFirestore(DocumentSnapshot doc, RecordType type) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final createdAt = data['created_at'] ?? data['createdAt'];
    DateTime date;
    if (createdAt is Timestamp) {
      date = createdAt.toDate();
    } else if (createdAt is String) {
      date = DateTime.tryParse(createdAt) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }

    final name =
        (data['text'] as String?) ??
        (data['name'] as String?) ??
        'Unnamed Record';

    CertificateStatus certificateStatus = CertificateStatus.pending;
    final rawStatus = data['certificate_status'] ?? data['certificateStatus'];
    if (rawStatus is String) {
      certificateStatus = CertificateStatusExtension.fromString(rawStatus);
    } else if (rawStatus is int &&
        rawStatus < CertificateStatus.values.length) {
      certificateStatus = CertificateStatus.values[rawStatus];
    }

    return ParishRecord(
      id: doc.id,
      type: type,
      name: name,
      date: date,
      imagePath: data['image_ref'] as String? ?? data['imagePath'] as String?,
      parish: data['parish'] as String? ?? data['source'] as String?,
      notes: data['notes'] as String?,
      certificateStatus: certificateStatus,
    );
  }

  Future<List<ParishRecord>> list() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final List<ParishRecord> allRecords = [];

      // Query all record types
      final types = [
        RecordType.baptism,
        RecordType.marriage,
        RecordType.confirmation,
        RecordType.funeral,
      ];

      for (final type in types) {
        final snapshot = await _collectionForType(type).get();
        final records = snapshot.docs
            .map((doc) => _fromFirestore(doc, type))
            .toList();
        allRecords.addAll(records);
      }

      return allRecords..sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      developer.log('Firestore load failed: $e', name: 'RecordsRepository');
      return [];
    }
  }

  Stream<List<ParishRecord>> watch() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    // Combine streams from all record collections
    final baptismStream = _firestore.collection('baptism_records').snapshots();
    final marriageStream = _firestore
        .collection('marriage_records')
        .snapshots();
    final confirmationStream = _firestore
        .collection('confirmation_records')
        .snapshots();
    final funeralStream = _firestore.collection('funeral_records').snapshots();

    return _combineStreams(
      baptismStream,
      marriageStream,
      confirmationStream,
      funeralStream,
    );
  }

  Stream<List<ParishRecord>> _combineStreams(
    Stream<QuerySnapshot> s1,
    Stream<QuerySnapshot> s2,
    Stream<QuerySnapshot> s3,
    Stream<QuerySnapshot> s4,
  ) {
    final controller = StreamController<List<ParishRecord>>();
    QuerySnapshot? r1, r2, r3, r4;

    void emit() {
      if (r1 == null || r2 == null || r3 == null || r4 == null) return;
      final records = <ParishRecord>[
        ...r1!.docs.map((d) => _fromFirestore(d, RecordType.baptism)),
        ...r2!.docs.map((d) => _fromFirestore(d, RecordType.marriage)),
        ...r3!.docs.map((d) => _fromFirestore(d, RecordType.confirmation)),
        ...r4!.docs.map((d) => _fromFirestore(d, RecordType.funeral)),
      ]..sort((a, b) => b.date.compareTo(a.date));
      controller.add(records);
    }

    final subs = <StreamSubscription<QuerySnapshot>>[];
    subs.add(
      s1.listen((e) {
        r1 = e;
        emit();
      }),
    );
    subs.add(
      s2.listen((e) {
        r2 = e;
        emit();
      }),
    );
    subs.add(
      s3.listen((e) {
        r3 = e;
        emit();
      }),
    );
    subs.add(
      s4.listen((e) {
        r4 = e;
        emit();
      }),
    );

    controller.onCancel = () async {
      for (final s in subs) await s.cancel();
    };

    return controller.stream;
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

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final data = {
      'text': trimmedName,
      'type': _typeString(type),
      'source': parish ?? 'app',
      'image_ref': imagePath,
      'notes': notes,
      'certificate_status': CertificateStatus.pending.name,
      'created_by_uid': user.uid,
      'created_at': Timestamp.fromDate(date),
    };

    await _collectionForType(type).add(data);
    developer.log(
      'Record saved to Firestore successfully',
      name: 'RecordsRepository',
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
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['text'] = name;
    if (imagePath != null) data['image_ref'] = imagePath;
    if (parish != null) data['source'] = parish;
    if (notes != null) data['notes'] = notes;
    if (data.isEmpty) return;

    data['updated_at'] = Timestamp.now();

    // Need type to know which collection
    if (type != null) {
      await _collectionForType(type).doc(id).update(data);
    } else {
      // Try all collections
      final collections = [
        'baptism_records',
        'marriage_records',
        'confirmation_records',
        'funeral_records',
      ];
      for (final col in collections) {
        try {
          await _firestore.collection(col).doc(id).update(data);
          break;
        } catch (e) {
          // Continue to next collection
        }
      }
    }

    developer.log(
      'Record updated in Firestore successfully',
      name: 'RecordsRepository',
    );
  }

  Future<void> updateCertificateStatus(
    String id,
    CertificateStatus status, {
    RecordType? type,
  }) async {
    final data = {
      'certificate_status': status.name,
      'updated_at': Timestamp.now(),
    };

    if (type != null) {
      await _collectionForType(type).doc(id).update(data);
    } else {
      // Try all collections
      final collections = [
        'baptism_records',
        'marriage_records',
        'confirmation_records',
        'funeral_records',
      ];
      for (final col in collections) {
        try {
          await _firestore.collection(col).doc(id).update(data);
          break;
        } catch (e) {
          // Continue to next collection
        }
      }
    }

    developer.log(
      'Certificate status updated in Firestore',
      name: 'RecordsRepository',
    );
  }

  Future<void> deleteForType(String id, RecordType type) async {
    await delete(id, type: type);
  }

  Future<void> updateCertificateStatusForType(
    String id,
    RecordType type,
    CertificateStatus status,
  ) async {
    await updateCertificateStatus(id, status, type: type);
  }

  Future<void> delete(String id, {RecordType? type}) async {
    if (type != null) {
      await _collectionForType(type).doc(id).delete();
    } else {
      // Try all collections
      final collections = [
        'baptism_records',
        'marriage_records',
        'confirmation_records',
        'funeral_records',
      ];
      for (final col in collections) {
        try {
          await _firestore.collection(col).doc(id).delete();
          break;
        } catch (e) {
          // Continue to next collection
        }
      }
    }

    developer.log(
      'Record deleted from Firestore successfully',
      name: 'RecordsRepository',
    );
  }

  Future<void> submitCorrectionRequest(String recordId, String message) async {
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      throw Exception('Correction message cannot be empty');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final data = {
      'record_id': recordId,
      'message': trimmedMessage,
      'created_by_uid': user.uid,
      'created_at': Timestamp.now(),
      'status': 'pending',
    };

    await _firestore.collection('correction_tickets').add(data);
    developer.log(
      'Correction request submitted successfully',
      name: 'RecordsRepository',
    );
  }
}
