// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:universal_html/html.dart' as html;

import '../../../utils/firestore_date.dart';
import '../../../utils/record_date_filter.dart';
import '../../../widgets/app_loading.dart';
import '../../../widgets/record_date_range_filters.dart';
import '../../../services/donations_repository.dart';
import '../../../utils/donation_display.dart';
import '../widgets/finance_module_design.dart' hide formatPaymentMethod;

class AdminDonationsPage extends ConsumerStatefulWidget {
  const AdminDonationsPage({super.key});
  @override
  ConsumerState<AdminDonationsPage> createState() => _AdminDonationsPageState();
}

class _AdminDonationsPageState extends ConsumerState<AdminDonationsPage> {
  int _refreshKey = 0;
  bool _donationPdfBusy = false;
  bool _actionBusy = false;
  DateTime? _from;
  DateTime? _to;

  // ── PDF: Donations ──────────────────────────────────────────────────────────
  Future<void> _exportDonationsPdf(List<Map<String, dynamic>> rows) async {
    if (_donationPdfBusy) return;
    setState(() => _donationPdfBusy = true);
    try {
      final pdf = pw.Document();
      double total = 0;
      for (final r in rows) {
        total += (r['amount'] as num?)?.toDouble() ?? 0;
      }
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (ctx) => [
            pw.Center(
              child: pw.Text(
                'Donations Report',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                _from != null || _to != null
                    ? 'Filter: ${_from != null ? DateFormat('MMM d, yyyy').format(_from!) : '…'} – ${_to != null ? DateFormat('MMM d, yyyy').format(_to!) : '…'}'
                    : 'All records',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Generated: ${DateFormat('MMMM d, yyyy h:mm a').format(DateTime.now())} · ${rows.length} record(s)',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headers: ['Date', 'Donor', 'Category', 'Method', 'Amount (₱)'],
              data: rows.map((r) {
                final dt = parseFirestoreDate(r['created_at']);
                final d = dt != null
                    ? DateFormat('MMM d, yyyy').format(dt)
                    : '—';
                final donor = r['anonymous'] == true
                    ? 'Anonymous'
                    : (r['donor_name']?.toString().trim().isNotEmpty == true
                          ? r['donor_name'].toString()
                          : '—');
                return [
                  d,
                  donor,
                  r['campaign'] ?? 'General',
                  (r['method'] ?? 'cash').toString().toUpperCase(),
                  ((r['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 12),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Grand Total: ₱${total.toStringAsFixed(2)}',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
      await _savePdf(
        await pdf.save(),
        'donations_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Donations PDF exported.')),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _donationPdfBusy = false);
    }
  }

  Future<void> _savePdf(List<int> bytes, String name) async {
    if (kIsWeb) {
      final url = 'data:application/pdf;base64,${base64Encode(bytes)}';
      (html.AnchorElement(href: url)..setAttribute('download', name)).click();
    } else {
      await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: name);
    }
  }

  // ── Record Donation ─────────────────────────────────────────────────────────
  Future<void> _recordDonation() async {
    final result = await showFinanceFormSheet<Map<String, dynamic>>(
      context: context,
      style: FinanceModuleStyle.of(FinanceModuleKind.donations),
      title: 'Record cash donation',
      child: const _RecordDonationForm(),
      actions: const [],
    );
    if (result != null) {
      try {
        await DonationsRepository().createManualCashDonation(
          amount: (result['amount'] as num).toDouble(),
          campaign: result['campaign']?.toString(),
          donorName: result['donorName']?.toString(),
          anonymous: result['anonymous'] == true,
          createdAt: result['date'] as DateTime?,
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Donation recorded.')));
          setState(() => _refreshKey++);
        }
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  List<Map<String, dynamic>> _filterDonations(List<Map<String, dynamic>> all) {
    var donations = filterAdminDonations(all);
    if (_from != null || _to != null) {
      donations = donations
          .where(
            (r) => RecordDateFilter.matchesValue(
              r['created_at'],
              from: _from,
              to: _to,
            ),
          )
          .toList();
    }
    return donations;
  }

  Future<void> _generateDonationsReport() async {
    try {
      final all = await DonationsRepository().list(limit: 200);
      final donations = _filterDonations(all);
      if (donations.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No donations to export.')),
          );
        }
        return;
      }
      await _exportDonationsPdf(donations);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report failed: $e')),
        );
      }
    }
  }

  Future<void> _editDonation(Map<String, dynamic> record) async {
    final donationId = record['donation_id']?.toString() ?? '';
    if (donationId.isEmpty) return;

    final amountController = TextEditingController(
      text: (record['amount'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00',
    );
    final donorController = TextEditingController(
      text: record['donor_name']?.toString() ?? '',
    );
    final campaigns = ['Tithes', 'Projects', 'Outreach', 'General'];
    const selectedMethod = 'cash';
    String selectedCampaign = record['campaign']?.toString() ?? 'General';
    bool anonymous = record['anonymous'] == true;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Donation'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount (₱)',
                        prefixIcon: Icon(Icons.payments),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: donorController,
                      decoration: const InputDecoration(
                        labelText: 'Donor Name',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: anonymous,
                      onChanged: (v) =>
                          setDialogState(() => anonymous = v ?? false),
                      title: const Text('Anonymous'),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Payment',
                        prefixIcon: Icon(Icons.payments_outlined),
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        'Cash',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCampaign,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category),
                        border: OutlineInputBorder(),
                      ),
                      items: campaigns
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (v) => setDialogState(
                        () => selectedCampaign = v ?? 'General',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final amount = double.tryParse(
                      amountController.text.trim(),
                    );
                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a valid amount'),
                        ),
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop();
                    if (!mounted) return;
                    setState(() => _actionBusy = true);
                    try {
                      await DonationsRepository().update(
                        donationId,
                        amount: amount,
                        method: selectedMethod,
                        campaign: selectedCampaign,
                        donorName: donorController.text.trim().isNotEmpty
                            ? donorController.text.trim()
                            : null,
                        anonymous: anonymous,
                      );
                      if (!mounted) return;
                      setState(() => _refreshKey++);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Donation updated successfully'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Update failed: $e')),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _actionBusy = false);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteDonation(String id) async {
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Donation'),
        content: const Text('Are you sure? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() => _actionBusy = true);
    try {
      await DonationsRepository().delete(id);
      if (!mounted) return;
      setState(() => _refreshKey++);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Donation deleted.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FinanceModulePage(
      module: FinanceModuleKind.donations,
      body: _DonationsPanel(
        refreshKey: _refreshKey,
        pdfBusy: _donationPdfBusy,
        from: _from,
        to: _to,
        onFromChanged: (d) => setState(() => _from = d),
        onToChanged: (d) => setState(() => _to = d),
        onClearDates: () => setState(() {
          _from = null;
          _to = null;
        }),
        onReportPdf: _generateDonationsReport,
        onRecord: _recordDonation,
        onExportTable: _exportDonationsPdf,
        onEdit: _editDonation,
        onDelete: _deleteDonation,
      ),
    );
  }
}

class _AdminDonationsInfoBanner extends StatelessWidget {
  const _AdminDonationsInfoBanner({required this.style});

  final FinanceModuleStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: style.accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: style.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: style.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Manual cash gifts recorded here. Online GCash donations from the '
              'public Donations page are saved separately — view them under '
              'Finance → Donations.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.45,
                    color: const Color(0xFF475569),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Donations Panel ────────────────────────────────────────────────────────────
class _DonationsPanel extends StatelessWidget {
  final int refreshKey;
  final bool pdfBusy;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTime?> onFromChanged;
  final ValueChanged<DateTime?> onToChanged;
  final VoidCallback onClearDates;
  final VoidCallback onReportPdf;
  final VoidCallback onRecord;
  final Future<void> Function(List<Map<String, dynamic>>) onExportTable;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(String) onDelete;

  const _DonationsPanel({
    required this.refreshKey,
    required this.pdfBusy,
    this.from,
    this.to,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onClearDates,
    required this.onReportPdf,
    required this.onRecord,
    required this.onExportTable,
    required this.onEdit,
    required this.onDelete,
  });

  static const _donationTypes = [
    'Tithes',
    'Projects',
    'Outreach',
    'General',
  ];

  @override
  Widget build(BuildContext context) {
    final style = FinanceModuleStyle.of(FinanceModuleKind.donations);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: DonationsRepository().watchAll(limit: 100),
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: style.accent, size: 40),
                const SizedBox(height: 12),
                Text(
                  'Could not load donations',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  snap.error.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        var donations = filterAdminDonations(snap.data ?? []);

        if (from != null || to != null) {
          donations = donations
              .where(
                (r) => RecordDateFilter.matchesValue(
                  r['created_at'],
                  from: from,
                  to: to,
                ),
              )
              .toList();
        }

        final byCategory = <String, double>{
          for (final t in _donationTypes) t: 0,
        };
        var grandTotal = 0.0;
        for (final d in donations) {
          final amt = (d['amount'] as num?)?.toDouble() ?? 0;
          final cat = (d['campaign'] as String?)?.trim();
          final key = (cat == null || cat.isEmpty) ? 'General' : cat;
          byCategory[key] = (byCategory[key] ?? 0) + amt;
          grandTotal += amt;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DonationsTopToolbar(
              style: style,
              from: from,
              to: to,
              pdfBusy: pdfBusy,
              onFromChanged: onFromChanged,
              onToChanged: onToChanged,
              onClearDates: onClearDates,
              onReportPdf: onReportPdf,
              onRecord: onRecord,
            ),
            if (snap.hasData) ...[
              const SizedBox(height: 16),
              _DonationsAnalyticsGrid(
                style: style,
                total: grandTotal,
                recordCount: donations.length,
                byCategory: byCategory,
              ),
            ],
            const SizedBox(height: 20),
            _AdminDonationsInfoBanner(style: style),
            const SizedBox(height: 12),
            FinanceSectionTitle(
              title: 'Cash donation records',
              style: style,
              trailing: snap.hasData && donations.isNotEmpty
                  ? TextButton.icon(
                      onPressed: pdfBusy ? null : () => onExportTable(donations),
                      icon: pdfBusy
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: style.accent,
                              ),
                            )
                          : Icon(Icons.download_rounded, color: style.accent),
                      label: Text('Export', style: TextStyle(color: style.accent)),
                    )
                  : null,
            ),
            if (snap.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: AppLoading()),
              )
            else if (donations.isEmpty)
              FinanceEmptyState(style: style)
            else
              _DonationsDataTable(
                donations: donations,
                style: style,
                onEdit: onEdit,
                onDelete: onDelete,
              ),
          ],
        );
      },
    );
  }
}

/// Top bar: date filters + Report PDF + Record (above analytics).
class _DonationsTopToolbar extends StatelessWidget {
  const _DonationsTopToolbar({
    required this.style,
    required this.from,
    required this.to,
    required this.pdfBusy,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onClearDates,
    required this.onReportPdf,
    required this.onRecord,
  });

  final FinanceModuleStyle style;
  final DateTime? from;
  final DateTime? to;
  final bool pdfBusy;
  final ValueChanged<DateTime?> onFromChanged;
  final ValueChanged<DateTime?> onToChanged;
  final VoidCallback onClearDates;
  final VoidCallback onReportPdf;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 720;
          final filters = RecordDateRangeFilters(
            from: from,
            to: to,
            fromLabel: 'From',
            toLabel: 'To',
            onFromChanged: onFromChanged,
            onToChanged: onToChanged,
            onClear: onClearDates,
          );
          final actions = Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: pdfBusy ? null : onReportPdf,
                icon: pdfBusy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: style.accent,
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Report PDF'),
              ),
              FilledButton.icon(
                onPressed: onRecord,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Record'),
                style: FilledButton.styleFrom(
                  backgroundColor: style.accent,
                  foregroundColor: style.onAccent,
                ),
              ),
            ],
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                filters,
                const SizedBox(height: 12),
                actions,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: filters),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }
}

/// Analytics cards: total + each donation type.
class _DonationsAnalyticsGrid extends StatelessWidget {
  const _DonationsAnalyticsGrid({
    required this.style,
    required this.total,
    required this.recordCount,
    required this.byCategory,
  });

  final FinanceModuleStyle style;
  final double total;
  final int recordCount;
  final Map<String, double> byCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final typeEntries = <MapEntry<String, double>>[];
    for (final t in _DonationsPanel._donationTypes) {
      typeEntries.add(MapEntry(t, byCategory[t] ?? 0));
    }
    for (final e in byCategory.entries) {
      if (!_DonationsPanel._donationTypes.contains(e.key)) {
        typeEntries.add(e);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                style.accent.withValues(alpha: 0.12),
                style.accentSoft,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: style.accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: style.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: style.accent,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total collected',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₱${total.toStringAsFixed(2)}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: style.accent,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$recordCount record${recordCount == 1 ? '' : 's'} in view',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final cols = w > 900 ? 4 : (w > 520 ? 2 : 1);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: cols == 1 ? 2.8 : 1.55,
              ),
              itemCount: typeEntries.length,
              itemBuilder: (context, i) {
                final e = typeEntries[i];
                final color = donationCategoryColor(e.key);
                final icon = donationCategoryIcon(e.key);
                return _DonationTypeCard(
                  label: e.key,
                  amount: e.value,
                  color: color,
                  icon: icon,
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _DonationTypeCard extends StatelessWidget {
  const _DonationTypeCard({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '₱${amount.toStringAsFixed(2)}',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Donations table ───────────────────────────────────────────────────────────
class _DonationsDataTable extends StatelessWidget {
  const _DonationsDataTable({
    required this.donations,
    required this.style,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> donations;
  final FinanceModuleStyle style;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(String) onDelete;

  static String _donorName(Map<String, dynamic> d) {
    if (d['anonymous'] == true) return 'Anonymous';
    final name = d['donor_name']?.toString().trim() ?? '';
    return name.isNotEmpty ? name : '—';
  }

  static String _donationType(Map<String, dynamic> d) => donationTypeLabel(d);

  static double _amount(Map<String, dynamic> d) =>
      (d['amount'] as num?)?.toDouble() ?? 0;

  static String _methodLabel(Map<String, dynamic> d) =>
      formatPaymentMethod(donationPaymentMethodId(d));

  static String _dateLabel(Map<String, dynamic> d) {
    final dt = parseFirestoreDate(d['created_at']);
    return dt != null ? DateFormat('MMM d, yyyy').format(dt) : '—';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        return Container(
          margin: const EdgeInsets.only(top: 8),
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: tableWidth),
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                    style.accent.withValues(alpha: 0.14),
                  ),
                  headingTextStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: style.accent,
                  ),
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 72,
                  columnSpacing: 28,
                  horizontalMargin: 20,
                  columns: const [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Type of Donation')),
                    DataColumn(
                      label: Text('Payment'),
                      numeric: true,
                    ),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: donations.map((d) {
                    final id = (d['donation_id'] ?? d['id'] ?? '').toString();
                    final type = _donationType(d);
                    final typeColor = donationCategoryColor(type);
                    final amt = _amount(d);
                    return DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 110,
                            child: Text(
                              _dateLabel(d),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 180,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _donorName(d),
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (isOnlineDonation(d)) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: Colors.blue.shade200,
                                          ),
                                        ),
                                        child: Text(
                                          'Online',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: Colors.blue.shade700,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (donorEmail(d) != null ||
                                    donorPhone(d) != null)
                                  Text(
                                    [
                                      if (donorEmail(d) != null) donorEmail(d),
                                      if (donorPhone(d) != null) donorPhone(d),
                                    ].join(' · '),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurface.withValues(alpha: 0.55),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          FinanceCategoryBadge(
                            label: type,
                            color: typeColor,
                          ),
                        ),
                        DataCell(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                donationAmountLabel(d),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cs.primary,
                                ),
                              ),
                              Text(
                                _methodLabel(d),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.edit_outlined,
                                  size: 20,
                                  color: style.accent,
                                ),
                                tooltip: 'Edit',
                                onPressed: () => onEdit(d),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                  color: cs.error,
                                ),
                                tooltip: 'Delete',
                                onPressed:
                                    id.isEmpty ? null : () => onDelete(id),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Record Donation Form ─────────────────────────────────────────────────────
class _RecordDonationForm extends StatefulWidget {
  const _RecordDonationForm();
  @override
  State<_RecordDonationForm> createState() => _RecordDonationFormState();
}

class _RecordDonationFormState extends State<_RecordDonationForm> {
  final _formKey = GlobalKey<FormState>();
  final _donorCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  static const _defaultCategories = [
    'Tithes',
    'Projects',
    'Outreach',
    'General',
  ];
  String _category = 'General';
  DateTime _selectedDate = DateTime.now();
  bool _anonymous = false;

  @override
  void dispose() {
    _donorCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final name = _donorCtrl.text.trim();
    Navigator.pop(context, {
      'donorName': name.isEmpty ? null : name,
      'amount': double.tryParse(_amountCtrl.text) ?? 0,
      'campaign': _category,
      'method': 'cash',
      'anonymous': _anonymous || name.isEmpty,
      'date': _selectedDate,
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = FinanceModuleStyle.of(FinanceModuleKind.donations).accent;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date',
                prefixIcon: Icon(Icons.calendar_today_rounded),
                border: OutlineInputBorder(),
              ),
              child: Text(DateFormat('MMMM d, yyyy').format(_selectedDate)),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _donorCtrl,
            decoration: const InputDecoration(
              labelText: 'Donor name',
              prefixIcon: Icon(Icons.person_outline_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _amountCtrl,
            decoration: const InputDecoration(
              labelText: 'Amount *',
              prefixText: '₱ ',
              prefixIcon: Icon(Icons.payments_rounded),
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Payment',
              prefixIcon: const Icon(Icons.payments_outlined),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: accent.withValues(alpha: 0.06),
            ),
            child: Text(
              'Cash (in-person)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(
              labelText: 'Category',
              prefixIcon: Icon(Icons.category_outlined),
              border: OutlineInputBorder(),
            ),
            items: _defaultCategories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _category = v ?? 'General'),
          ),
          CheckboxListTile(
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v ?? false),
            title: const Text('Keep donor anonymous'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Save donation'),
            ),
          ),
        ],
      ),
    );
  }
}

