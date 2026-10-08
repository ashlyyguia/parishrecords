import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/report_pdf_service.dart';

/// Builds the three Reports Library PDFs from sample data.
/// The files are written to build/report_previews/ for visual review.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final funds = ['Tithes / General Fund', 'Church Maintenance', 'Mass Intention', 'Youth Ministry', 'Building Fund', 'Scholarship Program'];
  final methods = ['cash', 'gcash', 'maya', 'gotyme'];
  final names = ['Liza Montero Villanueva', 'Antonio Lagura Ompad', 'Gloria Pacana Ompad', 'Leonardo Sy Cabahug', 'Carlo Reyes Sarmiento', 'Rhea Ladera Tagalog'];
  final donations = <Map<String, dynamic>>[
    for (var i = 0; i < 70; i++)
      {
        'created_at': now.subtract(Duration(days: i % 29, hours: i)),
        'amount': [100, 250, 500, 1000, 1500, 3000][i % 6],
        'method': methods[i % 4],
        'payment_method': methods[i % 4],
        'campaign': i % 9 == 0 ? 'certificate' : funds[i % funds.length],
        'donation_type': funds[i % funds.length],
        if (i % 9 == 0) 'certificate_type': ['Baptism', 'Confirmation', 'Marriage', 'Death'][i % 4],
        'donor_name': names[i % names.length],
        'anonymous': i % 13 == 0,
        'reconciled': i % 5 != 0,
        'source': methods[i % 4] == 'cash' ? 'manual_cash' : 'online',
        'online': methods[i % 4] != 'cash',
      },
  ];
  final users = [
    {'displayName': 'Administrator', 'email': 'admin@example.com', 'role': 'admin', 'verificationCodeVerified': true, 'createdAt': now.subtract(const Duration(days: 120)), 'lastLogin': now},
    {'displayName': 'Staff', 'email': 'staff@example.com', 'role': 'staff', 'verificationCodeVerified': true, 'createdAt': now.subtract(const Duration(days: 90)), 'lastLogin': now.subtract(const Duration(days: 2))},
    {'displayName': 'Finance', 'email': 'finance@example.com', 'role': 'finance', 'verificationCodeVerified': true, 'createdAt': now.subtract(const Duration(days: 90)), 'lastLogin': now.subtract(const Duration(days: 40))},
    {'displayName': 'Parishioner', 'email': 'user@example.com', 'role': 'parishioner', 'verificationCodeVerified': false, 'createdAt': now.subtract(const Duration(days: 30))},
  ];

  final out = Directory('build/report_previews')..createSync(recursive: true);

  test('financial overview PDF builds', () async {
    final bytes = await ReportPdfService.financialOverview(
      donations: donations,
      from: now.subtract(const Duration(days: 30)),
      to: now,
      generatedBy: 'Administrator',
    );
    expect(bytes.length, greaterThan(1000));
    File('${out.path}/financial_overview.pdf').writeAsBytesSync(bytes);
  });

  test('donations PDF builds across several pages', () async {
    final bytes = await ReportPdfService.donations(
      donations: donations.where((d) => d['campaign'] != 'certificate').toList(),
      periodLabel: 'All donations',
      generatedBy: 'Administrator',
    );
    expect(bytes.length, greaterThan(1000));
    File('${out.path}/donations.pdf').writeAsBytesSync(bytes);
  });

  test('user activity PDF builds', () async {
    final bytes = await ReportPdfService.userActivity(users: users, generatedBy: 'Administrator');
    expect(bytes.length, greaterThan(1000));
    File('${out.path}/user_activity.pdf').writeAsBytesSync(bytes);
  });

  test('CSV rows have readable headers', () {
    expect(ReportPdfService.donationsCsv(donations).first.first, 'Date');
    expect(ReportPdfService.usersCsv(users).first, contains('Role'));
  });
}
