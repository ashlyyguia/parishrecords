import 'package:flutter/material.dart';

/// Parish e-wallet accounts for online donations.
/// Replace account numbers and add QR image files under assets/images/payments/
/// (e.g. assets/images/gcashqr.png) when you have official static QR codes from the bank.
class ParishPaymentMethod {
  const ParishPaymentMethod({
    required this.id,
    required this.label,
    required this.accountName,
    required this.accountNumber,
    required this.qrPayload,
    required this.brandColor,
    this.qrAssetPath,
    this.instructions,
  });

  final String id;
  final String label;
  final String accountName;
  final String accountNumber;
  /// Data encoded in the QR (mobile number or merchant QR string).
  final String qrPayload;
  final Color brandColor;
  final String? qrAssetPath;
  final String? instructions;

  static ParishPaymentMethod? byId(String id) {
    for (final m in ParishPaymentConfig.methods) {
      if (m.id == id) return m;
    }
    return null;
  }
}

class ParishPaymentConfig {
  ParishPaymentConfig._();

  static const parishDisplayName = 'Holy Rosary Parish – Oroquieta City';

  /// Landing page donation categories (public donate flow).
  static const landingDonationTypes = [
    'Tithes',
    'Projects',
    'Outreach',
    'General',
  ];

  /// Full list for signed-in app donate flow.
  static const donationTypes = [
    'Tithes / General Fund',
    'Church Maintenance',
    'Parish Relief Fund',
    'Youth Ministry',
    'Community Outreach',
    'Scholarship Program',
    'Mass Intention',
    'Building Fund',
  ];

  /// Update these with your parish's real e-wallet details.
  static const methods = [
    ParishPaymentMethod(
      id: 'gcash',
      label: 'GCash',
      accountName: parishDisplayName,
      accountNumber: '0912 345 6789',
      qrPayload: '09123456789',
      brandColor: Color(0xFF007DF9),
      qrAssetPath: 'assets/images/gcashqr.png',
      instructions: 'Scan with GCash app → Send Money',
    ),
    ParishPaymentMethod(
      id: 'maya',
      label: 'Maya',
      accountName: parishDisplayName,
      accountNumber: '0912 345 6789',
      qrPayload: '09123456789',
      brandColor: Color(0xFF00B14F),
      qrAssetPath: 'assets/images/payments/maya_qr.png',
      instructions: 'Scan with Maya app → Send Money',
    ),
    ParishPaymentMethod(
      id: 'gotyme',
      label: 'GoTyme',
      accountName: parishDisplayName,
      accountNumber: '0912 345 6789',
      qrPayload: '09123456789',
      brandColor: Color(0xFFE85D04),
      qrAssetPath: 'assets/images/payments/gotyme_qr.png',
      instructions: 'Scan with GoTyme app → Send / Transfer',
    ),
  ];
}
