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
      final filtered = _filterRows(rows);
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
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headers: ['Date', 'Payer', 'Method', 'Amount (₱)'],
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
                final payer = r['anonymous'] == true
                    ? 'Anonymous'
                    : (r['donor_name']?.toString().trim().isNotEmpty == true
                          ? r['donor_name'].toString()
                          : '—');
                return [
                  dateStr,
                  payer,
                  formatPaymentMethod(
                    (r['method'] ?? 'cash').toString(),
                  ),
                  ((r['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
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
      exportButton: exportBtn,
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
