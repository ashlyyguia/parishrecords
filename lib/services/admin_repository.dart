import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/record.dart';

class AdminRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<ParishRecord>> listRecent({int limit = 50, int days = 7}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final List<ParishRecord> records = [];

    final collections = [
      'baptism_records',
      'marriage_records',
      'confirmation_records',
      'funeral_records',
    ];

    for (final collection in collections) {
      try {
        final snap = await _firestore
            .collection(collection)
            .where('created_at', isGreaterThan: Timestamp.fromDate(since))
            .orderBy('created_at', descending: true)
            .limit(limit)
            .get();

        for (final doc in snap.docs) {
          final type = _collectionToType(collection);
          final record = _fromFirestoreWithType(doc, type);
          records.add(record);
        }
      } catch (e) {
        developer.log('Error loading $collection: $e', name: 'AdminRepository');
      }
    }

    records.sort((a, b) => b.date.compareTo(a.date));
    return records.take(limit).toList();
  }

  RecordType _collectionToType(String collection) {
    switch (collection) {
      case 'baptism_records':
        return RecordType.baptism;
      case 'marriage_records':
        return RecordType.marriage;
      case 'confirmation_records':
        return RecordType.confirmation;
      case 'funeral_records':
        return RecordType.funeral;
      default:
        return RecordType.baptism;
    }
  }

  ParishRecord _fromFirestoreWithType(DocumentSnapshot doc, RecordType type) {
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

    final name = (data['text'] as String?) ?? 'Unnamed Record';

    return ParishRecord(
      id: doc.id,
      type: type,
      name: name,
      date: date,
      imagePath: data['image_ref'] as String?,
      parish: null,
      notes: data['source'] as String?,
    );
  }

  Future<List<ParishRecord>> listByUser(String userId, {int limit = 50}) async {
    final List<ParishRecord> records = [];
    final collections = [
      'baptism_records',
      'marriage_records',
      'confirmation_records',
      'funeral_records',
    ];

    for (final collection in collections) {
      try {
        final snap = await _firestore
            .collection(collection)
            .where('created_by_uid', isEqualTo: userId)
            .orderBy('created_at', descending: true)
            .limit(limit)
            .get();

        final type = _collectionToType(collection);
        for (final doc in snap.docs) {
          records.add(_fromFirestoreWithType(doc, type));
        }
      } catch (e) {
        developer.log(
          'Error loading $collection for user: $e',
          name: 'AdminRepository',
        );
      }
    }

    return records..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> update(
    String id, {
    String? name,
    String? parish,
    String? imagePath,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['text'] = name;
    if (imagePath != null) data['image_ref'] = imagePath;
    if (parish != null) data['source'] = parish;
    if (data.isEmpty) return;

    data['updated_at'] = FieldValue.serverTimestamp();

    // Try all collections to find the record
    final collections = [
      'baptism_records',
      'marriage_records',
      'confirmation_records',
      'funeral_records',
    ];
    for (final collection in collections) {
      try {
        await _firestore.collection(collection).doc(id).update(data);
        return;
      } catch (e) {
        // Continue to next collection
      }
    }
    throw Exception('Record not found in any collection');
  }

  Future<void> delete(String id) async {
    final collections = [
      'baptism_records',
      'marriage_records',
      'confirmation_records',
      'funeral_records',
    ];
    for (final collection in collections) {
      try {
        await _firestore.collection(collection).doc(id).delete();
        return;
      } catch (e) {
        // Continue to next collection
      }
    }
    throw Exception('Record not found in any collection');
  }

  Future<Map<String, dynamic>> getSettings() async {
    try {
      final doc = await _firestore.collection('settings').doc('app').get();
      if (doc.exists) {
        return doc.data() ?? {};
      }
    } catch (e) {
      developer.log('Get settings failed: $e', name: 'AdminRepository');
    }

    return {
      'language': 'en',
      'timezone': 'UTC',
      'notify': true,
      'auto_backup': false,
    };
  }

  Future<void> saveSettings({
    required String language,
    required String timezone,
    required bool notify,
    required bool autoBackup,
  }) async {
    await _firestore.collection('settings').doc('app').set({
      'language': language,
      'timezone': timezone,
      'notify': notify,
      'auto_backup': autoBackup,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<Map<String, dynamic>>> getLogs({
    int limit = 100,
    int days = 7,
  }) async {
    try {
      final since = DateTime.now().subtract(Duration(days: days));
      final snap = await _firestore
          .collection('audit_logs')
          .where('timestamp', isGreaterThan: Timestamp.fromDate(since))
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return snap.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'user_id': data['user_id'] ?? '',
          'action': data['action'] ?? '',
          'details': data['details'] ?? data['new_values'] ?? '',
          'resource_id': data['resource_id'],
          'timestamp': data['timestamp'] is Timestamp
              ? (data['timestamp'] as Timestamp).toDate().toIso8601String()
              : (data['timestamp'] ?? ''),
        };
      }).toList();
    } catch (e) {
      developer.log('Get logs failed: $e', name: 'AdminRepository');
      return [];
    }
  }

  Future<void> deleteLog(String id) async {
    await _firestore.collection('audit_logs').doc(id).delete();
  }

  Future<List<Map<String, dynamic>>> getUsers(
    String? role, {
    int limit = 100,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .limit(limit);

    if (role != null && role.isNotEmpty) {
      query = query.where('role', isEqualTo: role);
    }

    final snap = await query.get();
    return snap.docs.map((doc) {
      final data = doc.data();
      data['uid'] = doc.id;
      return data;
    }).toList();
  }

  Future<void> setUserRole(String uid, String role) async {
    await _firestore.collection('users').doc(uid).update({
      'role': role,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setUserStatus(String uid, bool disabled) async {
    await _firestore.collection('users').doc(uid).update({
      'disabled': disabled,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> getDailyCounts({int days = 14}) async {
    // Generate daily counts from Firestore
    final List<Map<String, dynamic>> result = [];
    final now = DateTime.now();

    for (int i = 0; i < days; i++) {
      final date = now.subtract(Duration(days: i));
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(Duration(days: 1));

      int count = 0;
      final collections = [
        'baptism_records',
        'marriage_records',
        'confirmation_records',
        'funeral_records',
      ];

      for (final collection in collections) {
        try {
          final snap = await _firestore
              .collection(collection)
              .where(
                'created_at',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
              )
              .where('created_at', isLessThan: Timestamp.fromDate(endOfDay))
              .count()
              .get();
          count += snap.count ?? 0;
        } catch (e) {
          // Ignore errors
        }
      }

      result.add({
        'date': startOfDay.toIso8601String().split('T')[0],
        'count': count,
      });
    }

    return result.reversed.toList();
  }

  Future<List<Map<String, dynamic>>> getRecordHistory(String recordId) async {
    try {
      final snap = await _firestore
          .collection('audit_logs')
          .where('resource_id', isEqualTo: recordId)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      return snap.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'user_id': data['user_id'] ?? '',
          'action': data['action'] ?? '',
          'details': data['details'] ?? '',
          'timestamp': data['timestamp'] is Timestamp
              ? (data['timestamp'] as Timestamp).toDate().toIso8601String()
              : (data['timestamp'] ?? ''),
        };
      }).toList();
    } catch (e) {
      developer.log('Get record history failed: $e', name: 'AdminRepository');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAnalytics({int days = 7}) async {
    // Get analytics data from Firestore
    final List<Map<String, dynamic>> result = [];
    final collections = [
      'baptism_records',
      'marriage_records',
      'confirmation_records',
      'funeral_records',
    ];

    for (final collection in collections) {
      try {
        final snap = await _firestore.collection(collection).count().get();
        result.add({
          'type': collection.replaceAll('_records', ''),
          'count': snap.count ?? 0,
        });
      } catch (e) {
        result.add({'type': collection.replaceAll('_records', ''), 'count': 0});
      }
    }

    return result;
  }

  Future<Map<String, dynamic>> getSummary({int days = 7}) async {
    try {
      final usersSnapshot = await _firestore.collection('users').get();
      final usersByRole = <String, int>{};

      for (final doc in usersSnapshot.docs) {
        final role = doc.data()['role'] as String? ?? 'volunteer';
        usersByRole[role] = (usersByRole[role] ?? 0) + 1;
      }

      // Get recent records count
      final since = DateTime.now().subtract(Duration(days: days));
      int recentRecords = 0;
      final collections = [
        'baptism_records',
        'marriage_records',
        'confirmation_records',
        'funeral_records',
      ];

      for (final collection in collections) {
        try {
          final snap = await _firestore
              .collection(collection)
              .where('created_at', isGreaterThan: Timestamp.fromDate(since))
              .count()
              .get();
          recentRecords += snap.count ?? 0;
        } catch (e) {
          // Ignore errors
        }
      }

      return {
        'total_records_last_days': recentRecords,
        'users_by_role': usersByRole.isNotEmpty
            ? usersByRole
            : {'admin': 1, 'staff': 2, 'volunteer': 1},
        'total_users': usersSnapshot.docs.isNotEmpty
            ? usersSnapshot.docs.length
            : 4,
        'generated_at': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      developer.log('Error generating summary: $e', name: 'AdminRepository');
      return {
        'total_records_last_days': 0,
        'users_by_role': {'admin': 0, 'staff': 0, 'volunteer': 0},
        'total_users': 0,
        'error': e.toString(),
      };
    }
  }

  Future<bool> usersHealth() async {
    try {
      await _firestore.collection('users').limit(1).get();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<int> usersSync() async {
    // No sync needed with direct Firestore
    final snap = await _firestore.collection('users').count().get();
    return snap.count ?? 0;
  }
}
