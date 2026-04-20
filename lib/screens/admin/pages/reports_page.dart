import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../providers/finance_providers.dart';
import '../../../services/export_service.dart';

class AdminReportsPage extends ConsumerWidget {
  const AdminReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.summarize_outlined,
                    size: 32,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Reports Library',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Generate and export reports (PDF/CSV).',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    _ReportCard(
                      title: 'Financial Overview',
                      subtitle: 'Last 30 days of financial data',
                      icon: Icons.account_balance_wallet_outlined,
                      onExportPdf: () =>
                          _exportFinancialReport(context, ref, 'pdf', 30),
                      onExportCsv: () =>
                          _exportFinancialReport(context, ref, 'csv', 30),
                    ),
                    const SizedBox(height: 12),
                    _ReportCard(
                      title: 'Donations Report',
                      subtitle: 'Recent donations list',
                      icon: Icons.volunteer_activism_outlined,
                      onExportPdf: () =>
                          _exportDonationsReport(context, ref, 'pdf', 100),
                      onExportCsv: () =>
                          _exportDonationsReport(context, ref, 'csv', 100),
                    ),
                    const SizedBox(height: 12),
                    _ReportCard(
                      title: 'User Activity Summary',
                      subtitle: 'System users and roles',
                      icon: Icons.people_alt_outlined,
                      onExportPdf: () => _showComingSoon(context),
                      onExportCsv: () => _showComingSoon(context),
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

  Future<void> _exportFinancialReport(
    BuildContext context,
    WidgetRef ref,
    String format,
    int days,
  ) async {
    try {
      final data = await ref.read(financeOverviewProvider(days).future);

      if (data.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No financial data available')),
          );
        }
        return;
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'financial_report_$timestamp';

      if (format == 'pdf') {
        await ExportService.exportPdf(
          '$filename.pdf',
          [data],
          title: 'Financial Overview Report',
          subtitle:
              'Generated on ${DateFormat('MMM d, yyyy').format(DateTime.now())}',
        );
      } else {
        final rows = <List<dynamic>>[];
        rows.add(['Metric', 'Value']);
        data.forEach((key, value) {
          rows.add([key, value.toString()]);
        });
        await ExportService.exportCsv('$filename.csv', rows);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${format.toUpperCase()} report exported successfully',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _exportDonationsReport(
    BuildContext context,
    WidgetRef ref,
    String format,
    int limit,
  ) async {
    try {
      final data = await ref.read(donationsListProvider(limit).future);

      if (data.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No donations data available')),
          );
        }
        return;
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'donations_report_$timestamp';

      if (format == 'pdf') {
        await ExportService.exportPdf(
          '$filename.pdf',
          data,
          title: 'Donations Report',
          subtitle:
              'Generated on ${DateFormat('MMM d, yyyy').format(DateTime.now())}',
        );
      } else {
        if (data.isNotEmpty) {
          final headers = data.first.keys.toList();
          final rows = <List<dynamic>>[];
          rows.add(headers);
          for (final item in data) {
            rows.add(headers.map((h) => item[h]?.toString() ?? '').toList());
          }
          await ExportService.exportCsv('$filename.csv', rows);
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${format.toUpperCase()} report exported successfully',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('This report is coming soon')));
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onExportPdf;
  final VoidCallback onExportCsv;

  const _ReportCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onExportPdf,
    required this.onExportCsv,
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
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
