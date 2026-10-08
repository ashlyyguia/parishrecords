import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/parish_payment_config.dart';
import '../utils/firestore_date.dart';
import 'notifications_repository.dart';

class DonationsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationsRepository _notifications = NotificationsRepository();

  static const Duration _timeout = Duration(seconds: 20);

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }

    return uid;
  }

  Future<List<Map<String, dynamic>>> listMine({int limit = 100}) async {
    final uid = _requireUid();

    final snap = await _firestore
        .collection('donations')
        .where('donor_id', isEqualTo: uid)
        .limit(limit)
        .get()
        .timeout(
          _timeout,
          onTimeout: () =>
              throw TimeoutException('Donations request timed out'),
        );

    final rows = snap.docs.map((doc) {
      final data = doc.data();
      data['donation_id'] = doc.id;
      final created = parseFirestoreDate(data['created_at']);
      if (created != null) {
        data['created_at'] = created;
      }
      return data;
    }).toList();

    rows.sort((a, b) {
      final da = a['created_at'];
      final db = b['created_at'];
      if (da is DateTime && db is DateTime) return db.compareTo(da);
      return 0;
    });
    return rows;
  }

  Future<List<Map<String, dynamic>>> list({int limit = 200}) async {
    _requireUid();

    final snap = await _firestore
        .collection('donations')
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get()
        .timeout(
          _timeout,

          onTimeout: () =>
              throw TimeoutException('Donations request timed out'),
        );

    return _mapDonationDocs(snap.docs);
  }

  Future<bool> reconcile(String donationId, {bool? reconciled}) async {
    _requireUid();

    final data = <String, dynamic>{'updated_at': FieldValue.serverTimestamp()};

    if (reconciled != null) {
      data['reconciled'] = reconciled;
    }

    await _firestore
        .collection('donations')
        .doc(donationId)
        .update(data)
        .timeout(
          _timeout,

          onTimeout: () =>
              throw TimeoutException('Reconcile request timed out'),
        );

    return reconciled ?? true;
  }

  Future<String> create({
    required double amount,

    String method = 'cash',

    String? campaign,

    String? certificateType,

    String? donorName,

    bool anonymous = false,

    DateTime? createdAt,

    String? source,
  }) async {
    final uid = _requireUid();

    final data = {
      'amount': amount,

      'method': method,

      'campaign': campaign,

      if (certificateType != null && certificateType.isNotEmpty)
        'certificate_type': certificateType,

      'donor_name': donorName,

      'anonymous': anonymous,

      'donor_id': uid,

      'reconciled': false,

      'online': false,

      if (source != null && source.isNotEmpty) 'source': source,

      'created_at': createdAt != null
          ? Timestamp.fromDate(createdAt)
          : FieldValue.serverTimestamp(),
    };

    final docRef = await _firestore
        .collection('donations')
        .add(data)
        .timeout(
          _timeout,

          onTimeout: () => throw TimeoutException('Donation create timed out'),
        );

    await _notifyAfterAdminRecord(
      donationId: docRef.id,
      amount: amount,
      method: method,
      campaign: campaign,
      certificateType: certificateType,
      donorName: donorName,
      anonymous: anonymous,
      source: source,
    );

    return docRef.id;
  }

  /// Admin/staff: manual in-person cash donation (not landing GCash).
  Future<String> createManualCashDonation({
    required double amount,
    String? campaign,
    String? donorName,
    bool anonymous = false,
    DateTime? createdAt,
  }) async {
    return create(
      amount: amount,
      method: 'cash',
      campaign: campaign,
      donorName: donorName,
      anonymous: anonymous,
      createdAt: createdAt,
      source: 'manual_cash',
    );
  }

  /// Online e-wallet donation — stored in `donations` for Admin & Finance.
  Future<String> createOnlineDonation({
    required double amount,
    required String donationType,
    required String paymentMethod,
    required String donorName,
    required String email,
    required String phone,
    String? message,
    bool anonymous = false,
    bool gcashAmountPending = false,
  }) async {
    final uid = _requireUid();
    if (!gcashAmountPending && !(amount > 0)) {
      throw Exception('Invalid donation amount');
    }

    final methodId = paymentMethod.trim().toLowerCase();
    final configured = ParishPaymentMethod.byId(methodId);
    final channelLabel = configured?.label ?? methodId;

    final data = {
      'amount': amount.toDouble(),
      'method': methodId,
      'campaign': donationType,
      'donation_type': donationType,
      'payment_method': methodId,
      'payment_channel': channelLabel,
      'donor_name': donorName.trim(),
      'donor_email': email.trim(),
      'donor_phone': phone.trim(),
      if (message != null && message.trim().isNotEmpty)
        'donor_message': message.trim(),
      'anonymous': anonymous,
      'donor_id': uid,
      'reconciled': false,
      'source': 'online',
      'online': true,
      'amount_pending': gcashAmountPending,
      'status': gcashAmountPending
          ? 'awaiting_gcash_amount'
          : 'pending_verification',
      'qr_transfer_confirmed': true,
      'qr_transfer_confirmed_at': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    final docRef = await _firestore
        .collection('donations')
        .add(data)
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Donation create timed out'),
        );

    await _notifyOnlineDonation(
      donationId: docRef.id,
      donorName: donorName,
      donationType: donationType,
      paymentMethod: methodId,
      amount: amount,
      amountPending: gcashAmountPending,
    );

    return docRef.id;
  }

  /// Landing page GCash donation — works signed-in or as guest (no account).
  Future<String> saveLandingGcashDonation({
    required String donorName,
    required String donationType,
    String? email,
    String? phone,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final name = donorName.trim();
    if (name.isEmpty) {
      throw Exception('Donor name is required');
    }

    final methodId = 'gcash';
    final configured = ParishPaymentMethod.byId(methodId);
    final channelLabel = configured?.label ?? 'GCash';

    final data = <String, dynamic>{
      'amount': 0,
      'method': methodId,
      'campaign': donationType,
      'donation_type': donationType,
      'payment_method': methodId,
      'payment_channel': channelLabel,
      'donor_name': name,
      'donor_email': (email ?? '').trim(),
      'donor_phone': (phone ?? '').trim().isEmpty ? '—' : phone!.trim(),
      'anonymous': false,
      'reconciled': false,
      'source': 'online',
      'online': true,
      'amount_pending': true,
      'status': 'awaiting_gcash_amount',
      'qr_transfer_confirmed': true,
      'qr_transfer_confirmed_at': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    if (user != null) {
      data['donor_id'] = user.uid;
      data['guest_donation'] = false;
    } else {
      data['donor_id'] = 'guest';
      data['guest_donation'] = true;
    }

    final docRef = await _firestore
        .collection('donations')
        .add(data)
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Donation create timed out'),
        );

    await _notifyOnlineDonation(
      donationId: docRef.id,
      donorName: name,
      donationType: donationType,
      paymentMethod: methodId,
      amount: 0,
      amountPending: true,
    );

    return docRef.id;
  }

  Future<void> _notifyAfterAdminRecord({
    required String donationId,
    required double amount,
    required String method,
    String? campaign,
    String? certificateType,
    String? donorName,
    bool anonymous = false,
    String? source,
  }) async {
    final name = anonymous
        ? 'Anonymous'
        : ((donorName ?? '').trim().isNotEmpty
            ? donorName!.trim()
            : 'Donor');
    final campaignNorm = (campaign ?? '').trim().toLowerCase();
    final sourceNorm = (source ?? '').trim().toLowerCase();

    if (campaignNorm == 'certificate') {
      await _notifyFinanceSafe(
        donationId: donationId,
        notify: () => _notifications.notifyFinanceOnCertificateFee(
          donationId: donationId,
          payerName: name,
          amount: amount,
          certificateType: certificateType,
          method: method,
        ),
      );
    } else if (sourceNorm == 'manual_cash') {
      await _notifyFinanceSafe(
        donationId: donationId,
        notify: () => _notifications.notifyFinanceOnCashDonation(
          donationId: donationId,
          donorName: name,
          amount: amount,
          campaign: campaign,
          method: method,
        ),
      );
    }
  }

  Future<void> _notifyFinanceSafe({
    required String donationId,
    required Future<void> Function() notify,
  }) async {
    try {
      final doc = await _firestore.collection('donations').doc(donationId).get();
      if (doc.data()?['finance_notified'] == true) return;

      await notify();

      await _firestore.collection('donations').doc(donationId).set(
        {'finance_notified': true},
        SetOptions(merge: true),
      );
    } catch (e, st) {
      developer.log(
        'Finance notification failed: $e',
        name: 'DonationsRepository',
        stackTrace: st,
      );
    }
  }

  Future<void> _notifyOnlineDonation({
    required String donationId,
    required String donorName,
    required String donationType,
    required String paymentMethod,
    double amount = 0,
    bool amountPending = false,
  }) async {
    await _notifyFinanceSafe(
      donationId: donationId,
      notify: () => _notifications.notifyFinanceOnOnlineDonation(
        donationId: donationId,
        donorName: donorName,
        donationType: donationType,
        paymentMethod: paymentMethod,
        amount: amount,
        amountPending: amountPending,
      ),
    );
  }

  List<Map<String, dynamic>> _mapDonationDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.map((doc) {
      final data = doc.data();
      data['donation_id'] = doc.id;
      final created = parseFirestoreDate(data['created_at']);
      if (created != null) {
        data['created_at'] = created;
      }
      return data;
    }).toList();
  }

  /// Live stream for Admin Donations and Finance ledger.
  Stream<List<Map<String, dynamic>>> watchAll({int limit = 200}) async* {
    _requireUid();

    try {
      await for (final snap in _firestore
          .collection('donations')
          .orderBy('created_at', descending: true)
          .limit(limit)
          .snapshots()) {
        yield _mapDonationDocs(snap.docs);
      }
    } on FirebaseException catch (e) {
      developer.log(
        'donations watchAll: ${e.code} — $e',
        name: 'DonationsRepository',
      );
      yield <Map<String, dynamic>>[];
    }
  }

  Future<void> update(
    String donationId, {
    double? amount,
    String? method,
    String? campaign,
    String? certificateType,
    String? donorName,
    bool? anonymous,
  }) async {
    _requireUid();

    final data = <String, dynamic>{'updated_at': FieldValue.serverTimestamp()};

    if (amount != null) data['amount'] = amount;
    if (method != null) data['method'] = method;
    if (campaign != null) data['campaign'] = campaign;
    if (certificateType != null) data['certificate_type'] = certificateType;
    if (donorName != null) data['donor_name'] = donorName;
    if (anonymous != null) data['anonymous'] = anonymous;

    if (data.length == 1) return; // Only updated_at, nothing to update

    await _firestore
        .collection('donations')
        .doc(donationId)
        .update(data)
        .timeout(
          _timeout,
          onTimeout: () => throw TimeoutException('Update donation timed out'),
        );
  }

  Future<void> delete(String donationId) async {
    _requireUid();

    await _firestore
        .collection('donations')
        .doc(donationId)
        .delete()
        .timeout(
          _timeout,

          onTimeout: () => throw TimeoutException('Delete donation timed out'),
        );
  }

  Stream<List<Map<String, dynamic>>> watch() => watchAll();
}
