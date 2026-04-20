import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OcrJobsRepository {
  static const Duration _timeout = Duration(seconds: 15);

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }
    return uid;
  }

  Future<List<Map<String, dynamic>>> listAssignedTo(
    String uid, {
    int limit = 50,
  }) async {
    // Simplified query to avoid composite index requirement
    // Fetch more docs and filter client-side
    final snap = await _db
        .collection('ocr_jobs')
        .orderBy('created_at', descending: true)
        .limit(limit * 3) // Fetch more to account for filtering
        .get()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('OCR jobs list timed out'),
        );

    String toIso(dynamic v) {
      if (v == null) return '';
      if (v is Timestamp) return v.toDate().toIso8601String();
      if (v is DateTime) return v.toIso8601String();
      return v.toString();
    }

    // Filter assigned to uid in memory
    final filtered = snap.docs
        .where((d) {
          final m = d.data();
          return m['assigned_to'] == uid;
        })
        .take(limit);

    return filtered.map((d) {
      final m = d.data();
      return <String, dynamic>{
        'id': d.id,
        'type': m['type'],
        'status': m['status'],
        'title': m['title'],
        'assigned_to': m['assigned_to'],
        'created_at': toIso(m['created_at']),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listUnassigned({int limit = 50}) async {
    // Simplified query to avoid composite index requirement
    final snap = await _db
        .collection('ocr_jobs')
        .orderBy('created_at', descending: true)
        .limit(limit * 3) // Fetch more to account for filtering
        .get()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('OCR jobs list timed out'),
        );

    String toIso(dynamic v) {
      if (v == null) return '';
      if (v is Timestamp) return v.toDate().toIso8601String();
      if (v is DateTime) return v.toIso8601String();
      return v.toString();
    }

    // Filter unassigned (null) in memory
    final filtered = snap.docs
        .where((d) {
          final m = d.data();
          return m['assigned_to'] == null;
        })
        .take(limit);

    return filtered.map((d) {
      final m = d.data();
      return <String, dynamic>{
        'id': d.id,
        'type': m['type'],
        'status': m['status'],
        'title': m['title'],
        'assigned_to': m['assigned_to'],
        'created_at': toIso(m['created_at']),
      };
    }).toList();
  }

  Future<String> createJob({
    required String type,
    String? bookNumber,
    String? pageNumber,
    String? notes,
  }) async {
    final uid = _requireUid();
    final doc = await _db
        .collection('ocr_jobs')
        .add({
          'type': type,
          'title': '$type OCR Job',
          'status': 'processing',
          'assigned_to': uid,
          'created_by': uid,
          'book_number': bookNumber,
          'page_number': pageNumber,
          'notes': notes,
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
          'locked': false,
        })
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Create OCR job timed out'),
        );

    return doc.id;
  }

  Future<String?> claimJob(String jobId) async {
    final uid = _requireUid();

    final ref = _db.collection('ocr_jobs').doc(jobId);
    final claimed = await _db
        .runTransaction((tx) async {
          final snap = await tx.get(ref);
          if (!snap.exists) return false;
          final data = snap.data();
          final assigned = data?['assigned_to'];
          if (assigned != null && assigned.toString().trim().isNotEmpty) {
            return false;
          }
          tx.set(ref, {
            'assigned_to': uid,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return true;
        })
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Claim OCR job timed out'),
        );

    return claimed ? jobId : null;
  }

  Future<String?> claimNextAvailable() async {
    final snap = await _db
        .collection('ocr_jobs')
        .where('assigned_to', isEqualTo: null)
        .orderBy('created_at', descending: true)
        .limit(1)
        .get()
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Claim OCR job timed out'),
        );

    if (snap.docs.isEmpty) return null;

    final id = snap.docs.first.id;
    return claimJob(id);
  }
}
