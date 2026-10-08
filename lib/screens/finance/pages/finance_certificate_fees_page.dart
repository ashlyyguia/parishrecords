import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:universal_html/html.dart' as html;

import '../../../providers/finance_providers.dart';
import '../../../utils/donation_display.dart';
import '../../../utils/record_date_filter.dart';
import '../../../widgets/app_loading.dart';
import '../../admin/widgets/finance_module_design.dart'
    hide formatPaymentMethod;
import '../widgets/finance_records_layout.dart';
import '../../../services/donations_repository.dart';
import '../../admin/pages/admin_certificate_fees_page.dart'
    show RecordCertificateFeeForm;
import '../../../services/report_pdf_service.dart';

class FinanceCertificateFeesPage extends ConsumerStatefulWidget {
  const FinanceCertificateFeesPage({super.key});

  @override
  ConsumerState<FinanceCertificateFeesPage> createState() =>
      _FinanceCertificateFeesPageState();
}

class _FinanceCertificateFeesPageState
    extends ConsumerState<FinanceCertificateFeesPage> {
  bool _exportBusy = false;
  DateTime? _from;
  DateTime? _to;

  static final _style =
      FinanceModuleStyle.of(FinanceModuleKind.certificateFees);

  List<Map<String, dynamic>> _certificateRows(List<Map<String, dynamic>> rows) {
    return rows.where((r) {
      final campaign =
          (r['campaign'] ?? '').toString().trim().toLowerCase();
      return campaign == 'certificate';
    }).toList();
  }

  List<Map<String, dynamic>> _filterRows(List<Map<String, dynamic>> rows) {
    var list = _certificateRows(rows);
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

  Future<void> _exportPdf(List<Map<String, dynamic>> rows) async {
    if (_exportBusy) return;
    setState(() => _exportBusy = true);
    try {
      final filtered = _filterRows(rows);
      final grandTotal = filtered.fold<double>(0, (t, r) => t + ((r['amount'] as num?)?.toDouble() ?? 0));
      final bytesNew = await ReportPdfService.tableReport(
        title: 'Certificate Payments Report',
        period: [
          ReportPdfService.periodLabel(_from, _to),
        ].join(' · '),
        headers: const ['Date', 'Payer', 'Certificate', 'Method', 'Amount'],
        rows: [
          for (final r in filtered)
            [
              ReportPdfService.shortDate(r['created_at']),
              ReportPdfService.donorName(r),
              (r['certificate_type'] ?? '—').toString(),
              formatPaymentMethod((r['method'] ?? 'cash').toString()),
              r['amount_pending'] == true ? 'Pending' : ReportPdfService.peso((r['amount'] as num?) ?? 0),
            ],
        ],
        right: const {4},
        tiles: [
          ['Total collected', ReportPdfService.peso(grandTotal), '${filtered.length} records'],
        ],
        totalLine: 'Grand total: ${ReportPdfService.peso(grandTotal)}',
        landscape: false,
        signatures: const [['Prepared by:', 'Finance Officer'], ['Verified by:', 'Parish Administrator']],
        generatedBy: ReportPdfService.currentUserLabel(),
      );

      final bytes = bytesNew;
      final name =
          'certificate_payments_${DateTime.now().millisecondsSinceEpoch}.pdf';

      if (kIsWeb) {
        final base64Str = base64Encode(bytes);
        final url = 'data:application/pdf;base64,$base64Str';
        (html.AnchorElement(href: url)..setAttribute('download', name)).click();
      } else {
        await Printing.sharePdf(bytes: bytes, filename: name);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Certificate Payments PDF exported.')),
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

  // ── Record a certificate fee (same form as Admin → Certificate Fees) ──
  Future<void> _recordCertificateFee() async {
    final result = await showFinanceFormSheet<Map<String, dynamic>>(
      context: context,
      style: _style,
      title: 'Record certificate fee',
      child: const RecordCertificateFeeForm(),
      actions: const [],
    );
    if (result == null) return;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Certificate fee recorded.')),
      );
      ref.invalidate(donationsListProvider(200));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Widget _headerActions(Widget? exportBtn) => Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          FilledButton.icon(
            key: const ValueKey('add-certificate-fee'),
            style: FilledButton.styleFrom(backgroundColor: _style.accent),
            onPressed: _recordCertificateFee,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Certificate Fee'),
          ),
          ?exportBtn,
        ],
      );

  Widget _buildShell({
    required Widget body,
    List<Widget> summaryChips = const [],
    int? recordCount,
    Widget? exportBtn,
  }) {
    return FinanceRecordsLayout(
      style: _style,
      title: 'Certificate Records',
      subtitle: 'Certificate payment records from donations.',
      from: _from,
      to: _to,
      onFromChanged: (d) => setState(() => _from = d),
      onToChanged: (d) => setState(() => _to = d),
      onClearDates: () => setState(() {
        _from = null;
        _to = null;
      }),
      onRefresh: () => ref.invalidate(donationsListProvider(200)),
      exportButton: _headerActions(exportBtn),
      summaryChips: summaryChips,
      recordCount: recordCount,
      body: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    final donationsAsync = ref.watch(donationsListProvider(200));

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
        final filtered = _filterRows(rows);

        if (filtered.isEmpty) {
          return _buildShell(
            exportBtn: exportBtn,
            body: FinanceEmptyState(style: _style),
          );
        }

        double total = 0;
        for (final r in filtered) {
          total += (r['amount'] as num?)?.toDouble() ?? 0;
        }

        return _buildShell(
          exportBtn: exportBtn,
          summaryChips: [
            FinanceSummaryChip(
              label: 'Total',
              value: '₱${total.toStringAsFixed(2)}',
              color: _style.accent,
            ),
          ],
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
                      constraints:
                          BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          _style.accentSoft,
                        ),
                        columns: const [
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Payer')),
                          DataColumn(label: Text('Method')),
                          DataColumn(
                            label: Text('Amount (₱)'),
                            numeric: true,
                          ),
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
                                dateStr =
                                    DateFormat('MMM d, yyyy').format(dt);
                              }
                            } catch (_) {}
                          }
                          final payer = r['anonymous'] == true
                              ? 'Anonymous'
                              : (r['donor_name']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ==
                                        true
                                    ? r['donor_name'].toString()
                                    : '—');
                          final amount = (r['amount'] as num?)
                                  ?.toDouble()
                                  .toStringAsFixed(2) ??
                              '0.00';
                          return DataRow(
                            cells: [
                              DataCell(Text(dateStr)),
                              DataCell(
                                Text(
                                  payer,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  formatPaymentMethod(
                                    (r['method'] ?? 'cash').toString(),
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  amount,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _style.accent,
                                  ),
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
        body: Center(child: Text('Failed to load records: $e')),
      ),
    );
  }
}
