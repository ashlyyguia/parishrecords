import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Repository for managing certificate fees configuration
class CertificateFeeRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Duration _timeout = Duration(seconds: 20);
  static const String _settingsDoc = 'certificate_fees';
  static const Set<String> _metaKeys = {'updated_at', 'reset_at'};

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }
    return uid;
  }

  Future<bool> _isAdmin() async {
    final uid = _requireUid();
    try {
      final snap = await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(_timeout);
      final role = (snap.data()?['role'] ?? '').toString().trim().toLowerCase();
      return role == 'admin';
    } catch (e) {
      return false;
    }
  }

  /// Get all certificate fees
  /// Returns a map of certificate type to fee amount
  Future<Map<String, double>> getFees() async {
    try {
      final doc = await _firestore
          .collection('settings')
          .doc(_settingsDoc)
          .get()
          .timeout(_timeout);

      if (!doc.exists) {
        return {};
      }

      final data = doc.data() ?? {};
      final fees = <String, double>{};

      for (final entry in data.entries) {
        if (_metaKeys.contains(entry.key)) continue;
        if (entry.value is num) {
          fees[entry.key] = (entry.value as num).toDouble();
        }
      }
      return fees;
    } catch (e) {
      return {};
    }
  }

  /// Update fee for a specific certificate type
  Future<void> updateFee(String certificateType, double fee) async {
    if (!await _isAdmin()) {
      throw Exception('Admin access required');
    }

    await _firestore
        .collection('settings')
        .doc(_settingsDoc)
        .set({
          certificateType: fee,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .timeout(_timeout);
  }

  /// Update multiple fees at once
  Future<void> updateFees(Map<String, double> fees) async {
    if (!await _isAdmin()) {
      throw Exception('Admin access required');
    }

    final data = <String, dynamic>{'updated_at': FieldValue.serverTimestamp()};
    data.addAll(fees);

    await _firestore
        .collection('settings')
        .doc(_settingsDoc)
        .set(data, SetOptions(merge: true))
        .timeout(_timeout);
  }

  /// Reset all fees to defaults
  Future<void> resetToDefaults() async {
    if (!await _isAdmin()) {
      throw Exception('Admin access required');
    }

    final data = <String, dynamic>{
      ..._defaultFees(),
      'updated_at': FieldValue.serverTimestamp(),
      'reset_at': FieldValue.serverTimestamp(),
    };

    await _firestore
        .collection('settings')
        .doc(_settingsDoc)
        .set(data)
        .timeout(_timeout);
  }

  /// Stream of fee updates
  Stream<Map<String, double>> watchFees() {
    return _firestore.collection('settings').doc(_settingsDoc).snapshots().map((
      doc,
    ) {
      if (!doc.exists) {
        return <String, double>{};
      }

      final data = doc.data() ?? {};
      final fees = <String, double>{};

      for (final entry in data.entries) {
        if (_metaKeys.contains(entry.key)) continue;
        if (entry.value is num) {
          fees[entry.key] = (entry.value as num).toDouble();
        }
      }
      return fees;
    });
  }

  /// Get default certificate fees
  Map<String, double> _defaultFees() {
    return {
      'Baptism': 100.0,
      'Marriage': 500.0,
      'Confirmation': 150.0,
      'Death': 200.0,
      'Parish Certification': 50.0,
    };
  }

  /// Get display name for certificate type
  static String getDisplayName(String type) {
    final names = {
      'Baptism': 'Baptism Certificate',
      'Marriage': 'Marriage Certificate',
      'Confirmation': 'Confirmation Certificate',
      'Death': 'Death/FUNeral Certificate',
      'Parish Certification': 'Parish Certification',
    };
    return names[type] ?? type;
  }

  /// Get icon for certificate type
  static IconData getIcon(String type) {
    switch (type) {
      case 'Baptism':
        return Icons.water_drop;
      case 'Marriage':
        return Icons.favorite;
      case 'Confirmation':
        return Icons.church;
      case 'Death':
        return Icons.sentiment_very_dissatisfied;
      case 'Parish Certification':
        return Icons.description;
      default:
        return Icons.article;
    }
  }

  /// Get color for certificate type
  static Color getColor(String type) {
    switch (type) {
      case 'Baptism':
        return Colors.blue;
      case 'Marriage':
        return Colors.pink;
      case 'Confirmation':
        return Colors.purple;
      case 'Death':
        return Colors.grey;
      case 'Parish Certification':
        return Colors.teal;
      default:
        return Colors.blueGrey;
    }
  }
}
