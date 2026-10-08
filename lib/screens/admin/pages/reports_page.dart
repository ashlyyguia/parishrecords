import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../services/donations_repository.dart';
import '../../../services/export_service.dart';
import '../../../services/report_pdf_service.dart';
import '../../../utils/donation_display.dart';
import '../../../utils/firestore_date.dart';
import '../../../widgets/page_header.dart';

/// Period options for the Financial Overview report.
enum _FinancePeriod { last30, last90, thisYear }

extension on _FinancePeriod {
  String get label => switch (this) {
        _FinancePeriod.last30 => 'Last 30 days',
        _FinancePeriod.last90 => 'Last 90 days',
        _FinancePeriod.thisYear => 'This year',
      };

  DateTime from(DateTime now) => switch (this) {
        _FinancePeriod.last30 => now.subtract(const Duration(days: 30)),
        _FinancePeriod.last90 => now.subtract(const Duration(days: 90)),
        _FinancePeriod.thisYear => DateTime(now.year, 1, 1),
      };
}

class AdminReportsPage extends ConsumerStatefulWidget {
  const AdminReportsPage({super.key});

  @override
  ConsumerState<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends ConsumerState<AdminReportsPage> {
  static const _donationsLimit = 1000;
  _FinancePeriod _period = _FinancePeriod.last30;
  String? _busy; // which export is running

  String get _generatedBy {
    final u = FirebaseAuth.instance.currentUser;
    final name = u?.displayName?.trim() ?? '';
    return name.isNotEmpty ? name : (u?.email ?? '');
  }

  String _stamp() => DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

  Future<void> _run(String key, Future<bool> Function() job) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      final exported = await job();
      if (exported && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report exported.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  bool _empty(String what) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No $what to export.')));
    }
    return false;
  }

  // ---------------------------------------------------------------- financial
  Future<void> _exportFinancial(String format) => _run('fin-$format', () async {
        final now = DateTime.now();
        final from = _period.from(now);
        final all = await DonationsRepository().list(limit: 5000);
        final inPeriod = all.where((d) {
          final dt = parseFirestoreDate(d['created_at']);
          return dt != null && !dt.isBefore(from) && !dt.isAfter(now) && d['amount_pending'] != true;
        }).toList();
        final name = 'financial_overview_${_stamp()}';
        if (format == 'pdf') {
          final bytes = await ReportPdfService.financialOverview(
            donations: inPeriod,
            from: from,
            to: now,
            generatedBy: _generatedBy,
          );
          await ExportService.savePdfBytes(bytes, '$name.pdf');
        } else {
          await ExportService.exportCsv('$name.csv', ReportPdfService.financialCsv(inPeriod, from, now));
        }
        return true;
      });

  // ---------------------------------------------------------------- donations
  Future<void> _exportDonations(String format) => _run('don-$format', () async {
        final all = await DonationsRepository().list(limit: _donationsLimit);
        final donations = filterAdminDonations(all);
        if (donations.isEmpty) return _empty('donations');
        final dates = donations.map((d) => parseFirestoreDate(d['created_at'])).whereType<DateTime>().toList()..sort();
        final df = DateFormat('MMM d, yyyy');
        final period = all.length >= _donationsLimit
            ? 'Latest ${donations.length} donations (${df.format(dates.first)} – ${df.format(dates.last)})'
            : 'All donations, ${df.format(dates.first)} – ${df.format(dates.last)}';
        final name = 'donations_report_${_stamp()}';
        if (format == 'pdf') {
          final bytes = await ReportPdfService.donations(
            donations: donations,
            periodLabel: period,
            generatedBy: _generatedBy,
          );
          await ExportService.savePdfBytes(bytes, '$name.pdf');
        } else {
          await ExportService.exportCsv('$name.csv', ReportPdfService.donationsCsv(donations));
        }
        return true;
      });

  // ---------------------------------------------------------------- users
  Future<void> _exportUsers(String format) => _run('usr-$format', () async {
        final snap = await FirebaseFirestore.instance.collection('users').get();
        final users = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        if (users.isEmpty) return _empty('users');
        final name = 'user_activity_${_stamp()}';
        if (format == 'pdf') {
          final bytes = await ReportPdfService.userActivity(users: users, generatedBy: _generatedBy);
          await ExportService.savePdfBytes(bytes, '$name.pdf');
        } else {
          await ExportService.exportCsv('$name.csv', ReportPdfService.usersCsv(users));
        }
        return true;
      });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(
                icon: Icons.summarize_outlined,
                title: 'Reports Library',
                subtitle: 'Generate and export reports (PDF/CSV).',
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    _ReportCard(
                      title: 'Financial Overview',
                      subtitle: 'Totals by payment method, fund, and week, with reconciliation status (portrait).',
                      icon: Icons.account_balance_wallet_outlined,
                      busy: _busy?.startsWith('fin') == true,
                      onExportPdf: () => _exportFinancial('pdf'),
                      onExportCsv: () => _exportFinancial('csv'),
                      extra: DropdownButton<_FinancePeriod>(
                        value: _period,
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final p in _FinancePeriod.values)
                            DropdownMenuItem(value: p, child: Text(p.label)),
                        ],
                        onChanged: (p) => setState(() => _period = p ?? _period),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ReportCard(
                      title: 'Donations Report',
                      subtitle: 'Every donation with donor, fund, method, and status (landscape).',
                      icon: Icons.volunteer_activism_outlined,
                      busy: _busy?.startsWith('don') == true,
                      onExportPdf: () => _exportDonations('pdf'),
                      onExportCsv: () => _exportDonations('csv'),
                    ),
                    const SizedBox(height: 12),
                    _ReportCard(
                      title: 'User Activity Summary',
                      subtitle: 'System accounts by role, with registration and last sign-in dates.',
                      icon: Icons.people_alt_outlined,
                      busy: _busy?.startsWith('usr') == true,
                      onExportPdf: () => _exportUsers('pdf'),
                      onExportCsv: () => _exportUsers('csv'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool busy;
  final VoidCallback onExportPdf;
  final VoidCallback onExportCsv;
  final Widget? extra;

  const _ReportCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onExportPdf,
    required this.onExportCsv,
    this.busy = false,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                if (extra != null) ...[const SizedBox(width: 12), extra!],
              ],
            ),
            const SizedBox(height: 16),
            if (busy)
              const LinearProgressIndicator()
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onExportPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onExportCsv,
                      icon: const Icon(Icons.table_chart),
                      label: const Text('CSV'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
