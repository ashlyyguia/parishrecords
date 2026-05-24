import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:universal_html/html.dart' as html;

import '../../../providers/finance_providers.dart';
import '../../../utils/donation_display.dart';
import '../../../utils/record_date_filter.dart';
import '../../../widgets/app_loading.dart';
import '../../admin/widgets/finance_module_design.dart'
    hide formatPaymentMethod;
import '../widgets/finance_records_layout.dart';

class DonationsLedgerPage extends ConsumerStatefulWidget {
  const DonationsLedgerPage({super.key});

  @override
  ConsumerState<DonationsLedgerPage> createState() =>
      _DonationsLedgerPageState();
}

class _DonationsLedgerPageState extends ConsumerState<DonationsLedgerPage> {
  bool _exportBusy = false;
  bool _actionBusy = false;
  String _filterCampaign = 'All';
  DateTime? _from;
  DateTime? _to;

  static const _campaigns = [
    'All',
    'Tithes',
    'Projects',
    'Outreach',
    'General',
  ];

  static const _methods = ['cash', 'gcash', 'bank_transfer', 'check', 'card'];

  static final _style = FinanceModuleStyle.of(FinanceModuleKind.donations);

  List<Map<String, dynamic>> _filterDonations(List<Map<String, dynamic>> rows) {
    var list = rows.where((r) {
      final campaign = (r['campaign'] ?? '').toString().trim().toLowerCase();
      return campaign != 'certificate';
    }).toList();

    if (_filterCampaign != 'All') {
      list = list
          .where(
            (r) => (r['campaign'] ?? 'General').toString() == _filterCampaign,
          )
          .toList();
    }

    if (_from != null || _to != null) {
      list = list
          .where(
            (r) => RecordDateFilter.matchesValue(
              r['created_at'],
              from: _from,
              to: _to,
            ),
          )
          .toList();
    }
    return list;
  }

  String? _dateRangeLabel() {
    if (_from == null && _to == null) return null;
    final df = DateFormat.yMMMd();
    if (_from != null && _to != null) {
      return 'Period: ${df.format(_from!)} – ${df.format(_to!)}';
    }
    if (_from != null) return 'From: ${df.format(_from!)}';
    return 'To: ${df.format(_to!)}';
  }

  Future<void> _exportPdf(List<Map<String, dynamic>> rows) async {
    if (_exportBusy) return;
    setState(() => _exportBusy = true);
    try {
      final filtered = _filterDonations(rows);
      final pdf = pw.Document();

      double grandTotal = 0;
      for (final r in filtered) {
        grandTotal += (r['amount'] as num?)?.toDouble() ?? 0;
      }

      final rangeLabel = _dateRangeLabel();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (ctx) => [
            pw.Center(
              child: pw.Text(
                'Parish Donations Report',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Generated: ${DateFormat('MMMM d, yyyy').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
            if (rangeLabel != null)
              pw.Center(
                child: pw.Text(
                  rangeLabel,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
            if (_filterCampaign != 'All')
              pw.Center(
                child: pw.Text(
                  'Category: $_filterCampaign',
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
              data: filtered.map((r) {
                final ts = r['created_at'];
                String dateStr = '—';
                if (ts != null) {
                  try {
                    final dt = ts is DateTime
                        ? ts
                        : DateTime.tryParse(ts.toString());
                    if (dt != null) {
                      dateStr = DateFormat('MM/dd/yyyy').format(dt);
                    }
                  } catch (_) {}
                }
                final donor = r['anonymous'] == true
                    ? 'Anonymous'
                    : (r['donor_name']?.toString().trim().isNotEmpty == true
                          ? r['donor_name'].toString()
                          : '—');
                return [
                  dateStr,
                  donor,
                  r['campaign']?.toString() ?? 'General',
                  formatPaymentMethod(donationPaymentMethodId(r)),
                  donationAmountLabel(r),
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 12),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Grand Total: ₱${grandTotal.toStringAsFixed(2)}',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      final name =
          'donations_report_${DateTime.now().millisecondsSinceEpoch}.pdf';

      if (kIsWeb) {
        final base64Str = base64Encode(bytes);
        final url = 'data:application/pdf;base64,$base64Str';
        (html.AnchorElement(href: url)..setAttribute('download', name)).click();
      } else {
        await Printing.sharePdf(bytes: bytes, filename: name);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Donations PDF exported.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exportBusy = false);
    }
  }

  Widget _buildShell({
    required Widget body,
    List<Widget> summaryChips = const [],
    int? recordCount,
    Widget? exportBtn,
  }) {
    return FinanceRecordsLayout(
      style: _style,
      title: 'Donations Records',
      subtitle:
          'All parish donations — cash, online GCash, and other payment types.',
      from: _from,
      to: _to,
      onFromChanged: (d) => setState(() => _from = d),
      onToChanged: (d) => setState(() => _to = d),
      onClearDates: () => setState(() {
        _from = null;
        _to = null;
      }),
      onRefresh: () => ref.invalidate(donationsStreamProvider(200)),
      exportButton: exportBtn,
      summaryChips: summaryChips,
      recordCount: recordCount,
      extraFilters: DropdownButtonFormField<String>(
        value: _filterCampaign,
        decoration: InputDecoration(
          labelText: 'Category',
          prefixIcon: Icon(Icons.category_outlined, color: _style.accent),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: _campaigns
            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
            .toList(),
        onChanged: (v) => setState(() => _filterCampaign = v ?? 'All'),
      ),
      body: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final donationsAsync = ref.watch(donationsStreamProvider(200));

    Widget? exportBtn;
    exportBtn = donationsAsync.whenOrNull(
      data: (rows) => FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: _style.accent),
        onPressed: _exportBusy ? null : () => _exportPdf(rows),
        icon: _exportBusy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.picture_as_pdf, size: 18),
        label: const Text('Export PDF'),
      ),
    );

    return donationsAsync.when(
      data: (rows) {
        final filtered = _filterDonations(rows);

        if (filtered.isEmpty) {
          return _buildShell(
            exportBtn: exportBtn,
            body: FinanceEmptyState(style: _style),
          );
        }

        double total = 0;
        final byType = <String, double>{};
        for (final r in filtered) {
          final amt = (r['amount'] as num?)?.toDouble() ?? 0;
          total += amt;
          final cat = r['campaign']?.toString() ?? 'General';
          byType[cat] = (byType[cat] ?? 0) + amt;
        }

        final summaryChips = [
          FinanceSummaryChip(
            label: 'Total',
            value: '₱${total.toStringAsFixed(2)}',
            color: _style.accent,
          ),
          ...byType.entries.map(
            (e) => FinanceSummaryChip(
              label: e.key,
              value: '₱${e.value.toStringAsFixed(2)}',
              color: colorScheme.secondary,
            ),
          ),
        ];

        return _buildShell(
          exportBtn: exportBtn,
          summaryChips: summaryChips,
          recordCount: filtered.length,
          body: FinanceRecordsTableCard(
            style: _style,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          _style.accentSoft,
                        ),
                        columns: const [
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Type of Donation')),
                          DataColumn(label: Text('Payment')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: filtered.map((r) {
                          final ts = r['created_at'];
                          String dateStr = '—';
                          if (ts != null) {
                            try {
                              final dt = ts is DateTime
                                  ? ts
                                  : DateTime.tryParse(ts.toString());
                              if (dt != null) {
                                dateStr = DateFormat('MMM d, yyyy').format(dt);
                              }
                            } catch (_) {}
                          }
                          final name = r['anonymous'] == true
                              ? 'Anonymous'
                              : (r['donor_name']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ==
                                        true
                                    ? r['donor_name'].toString()
                                    : '—');
                          final type = donationTypeLabel(r);
                          final method = formatPaymentMethod(
                            donationPaymentMethodId(r),
                          );
                          final onlineTag =
                              isOnlineDonation(r) ? ' · Online' : '';
                          final amountLabel = donationAmountLabel(r);
                          final payment = '$amountLabel · $method$onlineTag';
                          final donationId =
                              r['donation_id']?.toString() ?? '';
                          return DataRow(
                            cells: [
                              DataCell(Text(dateStr)),
                              DataCell(
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              DataCell(Text(type)),
                              DataCell(
                                Text(
                                  payment,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _style.accent,
                                  ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 20,
                                      ),
                                      tooltip: 'Edit',
                                      onPressed: _actionBusy
                                          ? null
                                          : () => _showEditDialog(r),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                      ),
                                      tooltip: 'Delete',
                                      color: colorScheme.error,
                                      onPressed: _actionBusy
                                          ? null
                                          : () =>
                                              _confirmDelete(donationId),
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
                );
              },
            ),
          ),
        );
      },
      loading: () => _buildShell(
        exportBtn: exportBtn,
        body: const Center(child: AppLoading()),
      ),
      error: (e, _) => _buildShell(
        exportBtn: exportBtn,
        body: Center(child: Text('Failed to load: $e')),
      ),
    );
  }

  Future<void> _showEditDialog(Map<String, dynamic> record) async {
    final donationId = record['donation_id']?.toString() ?? '';
    if (donationId.isEmpty) return;

    final amountController = TextEditingController(
      text: (record['amount'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00',
    );
    final donorController = TextEditingController(
      text: record['donor_name']?.toString() ?? '',
    );
    String selectedMethod = record['method']?.toString() ?? 'cash';
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
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: donorController,
                      decoration: const InputDecoration(
                        labelText: 'Donor Name',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: anonymous,
                      onChanged: (v) =>
                          setDialogState(() => anonymous = v ?? false),
                      title: const Text('Anonymous'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedMethod,
                      decoration: const InputDecoration(
                        labelText: 'Method',
                        prefixIcon: Icon(Icons.payment),
                      ),
                      items: _methods
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(m.toUpperCase()),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedMethod = v ?? 'cash'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCampaign,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category),
                      ),
                      items: _campaigns
                          .where((c) => c != 'All')
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
                    setState(() => _actionBusy = true);

                    try {
                      await ref.read(donationsRepositoryProvider).update(
                            donationId,
                            amount: amount,
                            method: selectedMethod,
                            campaign: selectedCampaign,
                            donorName: donorController.text.trim().isNotEmpty
                                ? donorController.text.trim()
                                : null,
                            anonymous: anonymous,
                          );

                      ref.invalidate(donationsStreamProvider(200));

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

  Future<void> _confirmDelete(String donationId) async {
    if (donationId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Donation?'),
        content: const Text('This action cannot be undone. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionBusy = true);
    try {
      await ref.read(donationsRepositoryProvider).delete(donationId);
      ref.invalidate(donationsStreamProvider(200));

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Donation deleted')));
      }
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
}
