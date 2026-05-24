import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/record.dart';
import '../models/register_ocr_entry.dart';
import 'audit_service.dart';

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
        try {
          final snapshot = await _collectionForType(type).get();
          final records = snapshot.docs
              .map((doc) => _fromFirestore(doc, type))
              .toList();
          allRecords.addAll(records);
          developer.log(
            'Loaded ${records.length} ${type.name} records',
            name: 'RecordsRepository',
          );
        } catch (e) {
          developer.log(
            'Failed to load ${type.name} records: $e',
            name: 'RecordsRepository',
          );
          // Continue loading other types even if one fails
        }
      }

      allRecords.sort((a, b) => b.date.compareTo(a.date));
      developer.log(
        'Total records loaded: ${allRecords.length}',
        name: 'RecordsRepository',
      );
      return allRecords;
    } catch (e) {
      developer.log('Firestore load failed: $e', name: 'RecordsRepository');
      // Rethrow so caller can handle the error properly
      throw Exception('Failed to load records: $e');
    }
  }

  /// Load a single record by document id across all sacrament collections.
  Future<ParishRecord?> getById(String id) async {
    if (id.trim().isEmpty) return null;

    for (final type in RecordType.values) {
      try {
        final doc = await _collectionForType(type).doc(id).get();
        if (doc.exists) {
          return _fromFirestore(doc, type);
        }
      } catch (e) {
        developer.log(
          'getById failed for ${type.name}/$id: $e',
          name: 'RecordsRepository',
        );
      }
    }
    return null;
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
      for (final s in subs) {
        await s.cancel();
      }
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
      'record_status': 'official',
      'certificate_status': CertificateStatus.pending.name,
      'created_by_uid': user.uid,
      'created_at': Timestamp.fromDate(date),
    };

    final docRef = await _collectionForType(type).add(data);
    developer.log(
      'Record saved to Firestore successfully',
      name: 'RecordsRepository',
    );

    // Log audit entry
    try {
      await AuditService.log(
        action: 'record_create',
        userId: user.uid,
        details:
            'Created ${type.name} record "$trimmedName" (ID: ${docRef.id})',
      );
    } catch (_) {}
  }

  /// Creates multiple official records in Firestore (chunked batches, max 400 per commit).
  Future<int> addBatch(List<RegisterRecordDraft> drafts) async {
    if (drafts.isEmpty) return 0;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');

    const chunkSize = 400;
    var saved = 0;

    for (var offset = 0; offset < drafts.length; offset += chunkSize) {
      final end = (offset + chunkSize < drafts.length)
          ? offset + chunkSize
          : drafts.length;
      final chunk = drafts.sublist(offset, end);
      final batch = _firestore.batch();

      for (final draft in chunk) {
        final trimmedName = draft.name.trim();
        if (trimmedName.isEmpty) continue;

        final ref = _collectionForType(draft.type).doc();
        batch.set(ref, {
          'text': trimmedName,
          'type': _typeString(draft.type),
          'source': draft.parish ?? 'register_ocr',
          'image_ref': draft.imagePath,
          'notes': draft.notes,
          'record_status': draft.recordStatus,
          'certificate_status': CertificateStatus.pending.name,
          'created_by_uid': user.uid,
          'created_at': Timestamp.fromDate(draft.date),
        });
      }

      await batch.commit();
      saved += chunk.length;
    }

    developer.log(
      'Bulk saved $saved records',
      name: 'RecordsRepository',
    );

    try {
      await AuditService.log(
        action: 'record_bulk_create',
        userId: user.uid,
        details: 'Bulk created $saved register OCR records',
      );
    } catch (_) {}

    return saved;
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
    final user = FirebaseAuth.instance.currentUser;
    final data = <String, dynamic>{};
    if (name != null) data['text'] = name;
    if (imagePath != null) data['image_ref'] = imagePath;
    if (parish != null) data['source'] = parish;
    if (notes != null) data['notes'] = notes;
    if (date != null) data['created_at'] = Timestamp.fromDate(date);
    if (data.isEmpty) return;

    data['updated_at'] = Timestamp.now();
    final typeName = type?.name ?? 'unknown';
    final recordName = name ?? 'Record';

    // If type is provided, prefer updating the target collection.
    // If the doc doesn't exist there (e.g. type changed), find it in the other
    // collections and migrate while keeping the same doc id.
    if (type != null) {
      final targetRef = _collectionForType(type).doc(id);
      try {
        await targetRef.update({...data, 'type': _typeString(type)});
        // Log audit entry
        if (user != null) {
          try {
            await AuditService.log(
              action: 'record_update',
              userId: user.uid,
              details: 'Updated $typeName record "$recordName" (ID: $id)',
            );
          } catch (_) {}
        }
        return;
      } on FirebaseException catch (e) {
        // If not found in target, attempt to locate and migrate.
        if (e.code != 'not-found') rethrow;
      }

      final collections = <RecordType, String>{
        RecordType.baptism: 'baptism_records',
        RecordType.marriage: 'marriage_records',
        RecordType.confirmation: 'confirmation_records',
        RecordType.funeral: 'funeral_records',
      };

      DocumentSnapshot<Map<String, dynamic>>? existingDoc;
      RecordType? existingType;

      for (final entry in collections.entries) {
        final docRef = _firestore
            .collection(entry.value)
            .doc(id)
            .withConverter<Map<String, dynamic>>(
              fromFirestore: (s, _) => s.data() ?? {},
              toFirestore: (m, _) => m,
            );
        final snap = await docRef.get();
        if (snap.exists) {
          existingDoc = snap;
          existingType = entry.key;
          break;
        }
      }

      if (existingDoc == null || existingType == null) {
        throw Exception('Record not found for update');
      }

      final existingData = existingDoc.data() ?? <String, dynamic>{};
      final merged = <String, dynamic>{
        ...existingData,
        ...data,
        'type': _typeString(type),
      };

      // If type changed, migrate documents across collections.
      final sourceCollection = _collectionForType(existingType);
      final targetCollection = _collectionForType(type);

      if (sourceCollection.path == targetCollection.path) {
        await targetCollection.doc(id).set(merged, SetOptions(merge: true));
        // Log audit entry
        if (user != null) {
          try {
            await AuditService.log(
              action: 'record_update',
              userId: user.uid,
              details: 'Updated $typeName record "$recordName" (ID: $id)',
            );
          } catch (_) {}
        }
        return;
      }

      await _firestore.runTransaction((txn) async {
        txn.set(targetCollection.doc(id), merged, SetOptions(merge: true));
        txn.delete(sourceCollection.doc(id));
      });
      // Log audit entry
      if (user != null) {
        try {
          await AuditService.log(
            action: 'record_update',
            userId: user.uid,
            details:
                'Migrated record "$recordName" from ${existingType.name} to ${type.name} (ID: $id)',
          );
        } catch (_) {}
      }
      return;
    }

    // No type provided: try all collections and update whichever contains the doc.
    final collections = [
      'baptism_records',
      'marriage_records',
      'confirmation_records',
      'funeral_records',
    ];
    for (final col in collections) {
      try {
        await _firestore.collection(col).doc(id).update(data);
        // Log audit entry
        if (user != null) {
          try {
            await AuditService.log(
              action: 'record_update',
              userId: user.uid,
              details: 'Updated $typeName record "$recordName" (ID: $id)',
            );
          } catch (_) {}
        }
        return;
      } catch (_) {
        // Continue to next collection
      }
    }
    throw Exception('Record not found for update');
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
    final user = FirebaseAuth.instance.currentUser;
    final typeName = type?.name ?? 'unknown';

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

    // Log audit entry
    if (user != null) {
      try {
        await AuditService.log(
          action: 'record_delete',
          userId: user.uid,
          details: 'Deleted $typeName record (ID: $id)',
        );
      } catch (_) {}
    }
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
