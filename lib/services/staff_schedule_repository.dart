import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StaffScheduleRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _timeout = Duration(seconds: 20);

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }
    return uid;
  }

  Future<List<Map<String, dynamic>>> listTodayEvents({
    String date = 'today',
  }) async {
    _requireUid();

    DateTime targetDate;
    if (date == 'today') {
      targetDate = DateTime.now();
    } else {
      targetDate = DateTime.tryParse(date) ?? DateTime.now();
    }

    final startOfDay = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );
    final endOfDay = startOfDay.add(Duration(days: 1));

    final snap = await _firestore
        .collection('events')
        .where(
          'start_time',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where('start_time', isLessThan: Timestamp.fromDate(endOfDay))
        .get()
        .timeout(_timeout);

    return snap.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listBookings({
    String? eventId,
    int limit = 100,
  }) async {
    _requireUid();

    Query<Map<String, dynamic>> query = _firestore
        .collection('bookings')
        .orderBy('created_at', descending: true)
        .limit(limit);

    if (eventId != null && eventId.isNotEmpty) {
      query = query.where('event_id', isEqualTo: eventId);
    }

    final snap = await query.get().timeout(_timeout);

    return snap.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  Future<void> confirmBooking(String bookingId) async {
    _requireUid();

    await _firestore
        .collection('bookings')
        .doc(bookingId)
        .update({
          'status': 'confirmed',
          'confirmed_at': FieldValue.serverTimestamp(),
        })
        .timeout(_timeout);
  }
}
