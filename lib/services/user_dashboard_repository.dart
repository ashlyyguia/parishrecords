import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class UserDashboardRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _timeout = Duration(seconds: 10);

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw Exception('Not authenticated');
    return uid;
  }

  DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  int _countSacramentsFromMember(Map<String, dynamic> m, Set<String> seen) {
    var added = 0;
    const fields = [
      'baptismRecordId',
      'confirmationRecordId',
      'marriageRecordId',
      'deathRecordId',
    ];
    for (final field in fields) {
      final id = m[field]?.toString();
      if (id == null || id.isEmpty) continue;
      final key = '$field:$id';
      if (seen.add(key)) added++;
    }
    final cached = m['linkedSacraments'];
    if (cached is List) {
      for (final raw in cached) {
        if (raw is! Map) continue;
        final type = (raw['type'] ?? '').toString();
        final id = (raw['recordId'] ?? '').toString();
        if (id.isEmpty) continue;
        final key = '$type:$id';
        if (seen.add(key)) added++;
      }
    }
    return added;
  }

  Future<QuerySnapshot<Map<String, dynamic>>?> _fetchHouseholdMembers(
    String householdId,
  ) async {
    try {
      return await _firestore
          .collection('household_members')
          .where('householdId', isEqualTo: householdId)
          .where('isActive', isEqualTo: true)
          .get()
          .timeout(_timeout);
    } catch (_) {
      return null;
    }
  }

  Future<({List<Map<String, dynamic>> members, int sacramentsCount})>
  _loadHouseholdSummary(String uid, String? linkedHouseholdId) async {
    final householdIds = <String>{};
    if (linkedHouseholdId != null && linkedHouseholdId.isNotEmpty) {
      householdIds.add(linkedHouseholdId);
    }

    try {
      final householdsSnap = await _firestore
          .collection('households')
          .where('created_by', isEqualTo: uid)
          .where('isArchived', isEqualTo: false)
          .get()
          .timeout(_timeout);
      for (final doc in householdsSnap.docs) {
        householdIds.add(doc.id);
      }
    } catch (_) {
      return (members: <Map<String, dynamic>>[], sacramentsCount: 0);
    }

    if (householdIds.isEmpty) {
      return (members: <Map<String, dynamic>>[], sacramentsCount: 0);
    }

    final memberSnaps = await Future.wait(
      householdIds.map(_fetchHouseholdMembers),
    );

    final members = <Map<String, dynamic>>[];
    final sacramentKeys = <String>{};

    for (final snap in memberSnaps) {
      if (snap == null) continue;
      for (final memberDoc in snap.docs) {
        final m = memberDoc.data();
        m['id'] = memberDoc.id;
        members.add(m);
        _countSacramentsFromMember(m, sacramentKeys);
      }
    }

    return (members: members, sacramentsCount: sacramentKeys.length);
  }

  Map<String, dynamic> _normalizeRequest(String docId, Map<String, dynamic> data) {
    final dt = _parseTimestamp(
      data['requested_at'] ?? data['created_at'] ?? data['createdAt'],
    );
    final status = (data['status'] ?? 'pending').toString().trim().toLowerCase();
    if (status.isEmpty || status == 'submitted') {
      data['status'] = 'pending';
    } else {
      data['status'] = status;
    }
    final certFor = (data['certificate_for_name'] ?? data['requester_name'] ?? '')
        .toString();
    data['request_id'] = docId;
    data['id'] = docId;
    data['requester_name'] = certFor;
    data['certificate_for_name'] = certFor;
    data['requested_at'] = dt?.toIso8601String() ?? '';
    data['requested_at_display'] =
        dt != null ? DateFormat('MMM d, yyyy • h:mm a').format(dt) : '';
    return data;
  }

  Future<List<Map<String, dynamic>>> _loadRecentRequests(String uid) async {
    try {
      final requestsSnap = await _firestore
          .collection('requests')
          .where('created_by_uid', isEqualTo: uid)
          .limit(20)
          .get()
          .timeout(_timeout);

      final requestsList = requestsSnap.docs
          .map((doc) => _normalizeRequest(doc.id, doc.data()))
          .toList();

      requestsList.sort((a, b) {
        final aTime = _parseTimestamp(a['created_at'] ?? a['requested_at']);
        final bTime = _parseTimestamp(b['created_at'] ?? b['requested_at']);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      return requestsList.take(5).toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> getMyDashboard() async {
    final uid = _requireUid();

    final userDoc = await _firestore
        .collection('users')
        .doc(uid)
        .get()
        .timeout(_timeout);
    final userData = userDoc.data() ?? {};
    final linkedHouseholdId = userData['linkedHouseholdId']?.toString();

    final householdFuture = _loadHouseholdSummary(uid, linkedHouseholdId);
    final requestsFuture = _loadRecentRequests(uid);

    final results = await Future.wait([householdFuture, requestsFuture]);

    final household = results[0] as ({List<Map<String, dynamic>> members, int sacramentsCount});
    final recentRequests =
        results[1] as List<Map<String, dynamic>>;

    return {
      'user': userData,
      'requests': recentRequests,
      'recent_requests': recentRequests,
      'members': household.members,
      'sacraments_count': household.sacramentsCount,
      'generated_at': DateTime.now().toIso8601String(),
    };
  }
}
