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
import '../../../services/certificate_fee_repository.dart';
import '../../../services/donations_repository.dart';
import '../widgets/finance_module_design.dart';

class AdminCertificateFeesPage extends ConsumerStatefulWidget {
  const AdminCertificateFeesPage({super.key});
  @override
  ConsumerState<AdminCertificateFeesPage> createState() =>
      _AdminCertificateFeesPageState();
}

class _AdminCertificateFeesPageState
    extends ConsumerState<AdminCertificateFeesPage> {
  int _refreshKey = 0;
  bool _feePdfBusy = false;
  bool _actionBusy = false;
  DateTime? _from;
  DateTime? _to;

  Future<void> _exportFeesPdf(List<Map<String, dynamic>> rows) async {
    if (_feePdfBusy) return;
    setState(() => _feePdfBusy = true);
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
                'Certificate Payments Report',
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
              headers: ['Date', 'Payer', 'Certificate', 'Method', 'Amount (₱)'],
              data: rows.map((r) {
                final dt = parseFirestoreDate(r['created_at']);
                final d = dt != null
                    ? DateFormat('MMM d, yyyy').format(dt)
                    : '—';
                final payer = r['anonymous'] == true
                    ? 'Anonymous'
                    : (r['donor_name']?.toString().trim().isNotEmpty == true
                          ? r['donor_name'].toString()
                          : '—');
                return [
                  d,
                  payer,
                  _CertificateFeesDataTable.certificateLabel(r),
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
        'certificate_payments_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Certificate payments PDF exported.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _feePdfBusy = false);
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

  Future<void> _recordCertificateFee() async {
    final result = await showFinanceFormSheet<Map<String, dynamic>>(
      context: context,
      style: FinanceModuleStyle.of(FinanceModuleKind.certificateFees),
      title: 'Record certificate fee',
      child: const _RecordCertificateFeeForm(),
      actions: const [],
    );
    if (result != null) {
      try {
        await DonationsRepository().create(
          amount: (result['amount'] as num).toDouble(),
          method: result['method']?.toString() ?? 'cash',
          campaign: 'certificate',
          certificateType: result['certificateType']?.toString(),
          donorName: result['payerName']?.toString(),
          anonymous: result['anonymous'] == true,
          createdAt: result['date'] as DateTime?,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Certificate fee recorded.')),
          );
          setState(() => _refreshKey++);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  List<Map<String, dynamic>> _filterCertificateRows(
    List<Map<String, dynamic>> all,
  ) {
    var rows = all.where((d) {
      final raw = (d['campaign'] ?? '').toString().trim().toLowerCase();
      return raw == 'certificate';
    }).toList();
    if (_from != null || _to != null) {
      rows = rows
          .where(
            (r) => RecordDateFilter.matchesValue(
              r['created_at'],
              from: _from,
              to: _to,
            ),
          )
          .toList();
    }
    return rows;
  }

  Future<void> _generateCertificateReport() async {
    try {
      final all = await DonationsRepository().list(limit: 200);
      final rows = _filterCertificateRows(all);
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No certificate fees to export.')),
          );
        }
        return;
      }
      await _exportFeesPdf(rows);
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
    final methods = ['cash', 'gcash', 'bank_transfer', 'check', 'card'];
    String selectedMethod = record['method']?.toString() ?? 'cash';
    const selectedCampaign = 'certificate';
    String selectedType = _CertificateFeesPanel.certificateTypeKey(record);
    bool anonymous = record['anonymous'] == true;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Certificate Fee'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _CertificateFeesPanel._certificateTypes
                              .contains(selectedType)
                          ? selectedType
                          : _CertificateFeesPanel._certificateTypes.first,
                      decoration: const InputDecoration(
                        labelText: 'Certificate type',
                        prefixIcon: Icon(Icons.verified_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: _CertificateFeesPanel._certificateTypes
                          .map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Text(
                                CertificateFeeRepository.getDisplayName(t),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setDialogState(
                        () => selectedType = v ?? selectedType,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                        labelText: 'Payer Name',
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
                    DropdownButtonFormField<String>(
                      value: selectedMethod,
                      decoration: const InputDecoration(
                        labelText: 'Method',
                        prefixIcon: Icon(Icons.payment),
                        border: OutlineInputBorder(),
                      ),
                      items: methods
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(formatPaymentMethod(m)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedMethod = v ?? 'cash'),
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
                        certificateType: selectedType,
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
                            content: Text('Certificate fee updated.'),
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
        title: const Text('Delete Certificate Fee'),
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
      ).showSnackBar(const SnackBar(content: Text('Certificate fee deleted.')));
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
      module: FinanceModuleKind.certificateFees,
      body: _CertificateFeesPanel(
        refreshKey: _refreshKey,
        pdfBusy: _feePdfBusy,
        from: _from,
        to: _to,
        onFromChanged: (d) => setState(() => _from = d),
        onToChanged: (d) => setState(() => _to = d),
        onClearDates: () => setState(() {
          _from = null;
          _to = null;
        }),
        onReportPdf: _generateCertificateReport,
        onRecord: _recordCertificateFee,
        onExportTable: _exportFeesPdf,
        onEdit: _editDonation,
        onDelete: _deleteDonation,
      ),
    );
  }
}

class _CertificateFeesPanel extends StatelessWidget {
  const _CertificateFeesPanel({
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

  static const _certificateTypes = [
    'Baptism',
    'Marriage',
    'Confirmation',
    'Death',
  ];

  static String certificateTypeKey(Map<String, dynamic> d) {
    final t = (d['certificate_type'] as String?)?.trim();
    if (t != null && t.isNotEmpty) {
      if (t == 'Parish Certification') return 'Baptism';
      return t;
    }
    return 'Baptism';
  }

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

  @override
  Widget build(BuildContext context) {
    final style = FinanceModuleStyle.of(FinanceModuleKind.certificateFees);

    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(refreshKey),
      future: DonationsRepository().list(limit: 100),
      builder: (context, snap) {
        var rows = (snap.data ?? []).where((d) {
          final raw = (d['campaign'] ?? '').toString().trim().toLowerCase();
          return raw == 'certificate';
        }).toList();

        if (from != null || to != null) {
          rows = rows
              .where(
                (r) => RecordDateFilter.matchesValue(
                  r['created_at'],
                  from: from,
                  to: to,
                ),
              )
              .toList();
        }

        final byType = <String, double>{
          for (final t in _certificateTypes) t: 0,
        };
        var grandTotal = 0.0;
        for (final r in rows) {
          final amt = (r['amount'] as num?)?.toDouble() ?? 0;
          final key = certificateTypeKey(r);
          byType[key] = (byType[key] ?? 0) + amt;
          grandTotal += amt;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CertificateFeesTopToolbar(
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
              _CertificateFeesAnalyticsGrid(
                style: style,
                total: grandTotal,
                recordCount: rows.length,
                byType: byType,
              ),
            ],
            const SizedBox(height: 20),
            FinanceSectionTitle(
              title: 'Certificate fee records',
              style: style,
              trailing: snap.hasData && rows.isNotEmpty
                  ? TextButton.icon(
                      onPressed: pdfBusy ? null : () => onExportTable(rows),
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
            else if (rows.isEmpty)
              FinanceEmptyState(style: style)
            else
              _CertificateFeesDataTable(
                rows: rows,
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

class _CertificateFeesTopToolbar extends StatelessWidget {
  const _CertificateFeesTopToolbar({
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
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Record fee'),
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

class _CertificateFeesAnalyticsGrid extends StatelessWidget {
  const _CertificateFeesAnalyticsGrid({
    required this.style,
    required this.total,
    required this.recordCount,
    required this.byType,
  });

  final FinanceModuleStyle style;
  final double total;
  final int recordCount;
  final Map<String, double> byType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final typeEntries = <MapEntry<String, double>>[];
    for (final t in _CertificateFeesPanel._certificateTypes) {
      typeEntries.add(MapEntry(t, byType[t] ?? 0));
    }
    for (final e in byType.entries) {
      if (e.key == 'Parish Certification') continue;
      if (!_CertificateFeesPanel._certificateTypes.contains(e.key)) {
        typeEntries.add(e);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                style.accent.withValues(alpha: 0.12),
                style.accentSoft,
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: style.accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: style.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.verified_outlined,
                  color: style.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total collected',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '₱${total.toStringAsFixed(2)}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: style.accent,
                      ),
                    ),
                    Text(
                      '$recordCount record${recordCount == 1 ? '' : 's'} in view',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.55),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final cols = w > 720 ? 4 : (w > 400 ? 2 : 1);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: cols == 1 ? 3.4 : 2.35,
              ),
              itemCount: typeEntries.length,
              itemBuilder: (context, i) {
                final e = typeEntries[i];
                return _CertificateTypeCard(
                  label: CertificateFeeRepository.getDisplayName(e.key),
                  amount: e.value,
                  color: CertificateFeeRepository.getColor(e.key),
                  icon: CertificateFeeRepository.getIcon(e.key),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _CertificateTypeCard extends StatelessWidget {
  const _CertificateTypeCard({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                  ),
                ),
                Text(
                  '₱${amount.toStringAsFixed(2)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CertificateFeesDataTable extends StatelessWidget {
  const _CertificateFeesDataTable({
    required this.rows,
    required this.style,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> rows;
  final FinanceModuleStyle style;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(String) onDelete;

  static String certificateLabel(Map<String, dynamic> d) {
    final key = _CertificateFeesPanel.certificateTypeKey(d);
    return CertificateFeeRepository.getDisplayName(key);
  }

  static String _payerName(Map<String, dynamic> d) {
    if (d['anonymous'] == true) return 'Anonymous';
    final name = d['donor_name']?.toString().trim() ?? '';
    return name.isNotEmpty ? name : '—';
  }

  static double _amount(Map<String, dynamic> d) =>
      (d['amount'] as num?)?.toDouble() ?? 0;

  static String _methodLabel(Map<String, dynamic> d) =>
      formatPaymentMethod((d['method'] ?? 'cash').toString());

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
                    DataColumn(label: Text('Certificate')),
                    DataColumn(
                      label: Text('Payment'),
                      numeric: true,
                    ),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: rows.map((d) {
                    final id = (d['donation_id'] ?? d['id'] ?? '').toString();
                    final typeKey = _CertificateFeesPanel.certificateTypeKey(d);
                    final typeColor = CertificateFeeRepository.getColor(typeKey);
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
                            width: 160,
                            child: Text(
                              _payerName(d),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          FinanceCategoryBadge(
                            label: certificateLabel(d),
                            color: typeColor,
                          ),
                        ),
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₱${amt.toStringAsFixed(2)}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: style.accent,
                                ),
                              ),
                              Text(
                                _methodLabel(d),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.55),
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
                                tooltip: 'Edit',
                                icon: Icon(Icons.edit_outlined, color: style.accent),
                                onPressed: () => onEdit(d),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: Colors.red.shade400,
                                ),
                                onPressed: () => onDelete(id),
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

class _RecordCertificateFeeForm extends StatefulWidget {
  const _RecordCertificateFeeForm();
  @override
  State<_RecordCertificateFeeForm> createState() =>
      _RecordCertificateFeeFormState();
}

class _RecordCertificateFeeFormState extends State<_RecordCertificateFeeForm> {
  final _formKey = GlobalKey<FormState>();
  final _payerCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  static const _methods = ['cash', 'gcash', 'bank_transfer', 'check', 'card'];
  String _method = 'cash';
  String _certificateType = _CertificateFeesPanel._certificateTypes.first;
  DateTime _selectedDate = DateTime.now();
  bool _anonymous = false;

  @override
  void dispose() {
    _payerCtrl.dispose();
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
    final name = _payerCtrl.text.trim();
    Navigator.pop(context, {
      'payerName': name.isEmpty ? null : name,
      'amount': double.tryParse(_amountCtrl.text) ?? 0,
      'method': _method,
      'certificateType': _certificateType,
      'anonymous': _anonymous || name.isEmpty,
      'date': _selectedDate,
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        FinanceModuleStyle.of(FinanceModuleKind.certificateFees).accent;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _certificateType,
            decoration: const InputDecoration(
              labelText: 'Certificate type *',
              prefixIcon: Icon(Icons.verified_outlined),
              border: OutlineInputBorder(),
            ),
            items: _CertificateFeesPanel._certificateTypes
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(CertificateFeeRepository.getDisplayName(t)),
                  ),
                )
                .toList(),
            onChanged: (v) =>
                setState(() => _certificateType = v ?? _certificateType),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Payment date',
                prefixIcon: Icon(Icons.calendar_today_rounded),
                border: OutlineInputBorder(),
              ),
              child: Text(DateFormat('MMMM d, yyyy').format(_selectedDate)),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _payerCtrl,
            decoration: const InputDecoration(
              labelText: 'Payer name',
              prefixIcon: Icon(Icons.person_outline_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _amountCtrl,
            decoration: const InputDecoration(
              labelText: 'Fee amount *',
              prefixText: '₱ ',
              prefixIcon: Icon(Icons.payments_rounded),
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _method,
            decoration: const InputDecoration(
              labelText: 'Payment method',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              border: OutlineInputBorder(),
            ),
            items: _methods
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(formatPaymentMethod(m)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _method = v ?? 'cash'),
          ),
          CheckboxListTile(
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v ?? false),
            title: const Text('Anonymous payer'),
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
              child: const Text('Save certificate fee'),
            ),
          ),
        ],
      ),
    );
  }
}
