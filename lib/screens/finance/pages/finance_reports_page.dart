import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:universal_html/html.dart' as html;

import '../../../providers/finance_providers.dart';

class FinanceReportsPage extends ConsumerStatefulWidget {
  const FinanceReportsPage({super.key});

  @override
  ConsumerState<FinanceReportsPage> createState() => _FinanceReportsPageState();
}

class _FinanceReportsPageState extends ConsumerState<FinanceReportsPage> {
  bool _busy = false;
  String _template = 'pnl';
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _from = d);
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _to = d);
  }

  Future<void> _run() async {
    if (_busy) return;

    setState(() => _busy = true);
    try {
      final resp = await ref.read(financialReportsRepositoryProvider).generate(
            template: _template,
            from: _from,
            to: _to,
          );

      final pdf = pw.Document();

      final byMethod = resp['by_method'] as Map<String, dynamic>? ?? {};
      final byCampaign = resp['by_campaign'] as Map<String, dynamic>? ?? {};

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text('Financial Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: context,
              data: <List<String>>[
                ['Template', resp['template'].toString().toUpperCase()],
                ['From', resp['from'].toString().split('T').first],
                ['To', resp['to'].toString().split('T').first],
                ['Generated At', resp['generated_at'].toString().split('T').first],
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Header(level: 1, text: 'OVERVIEW'),
            pw.TableHelper.fromTextArray(
              context: context,
              data: <List<String>>[
                ['Total Amount', 'PHP ${resp['total_amount']}'],
                ['Total Donations', '${resp['donation_count']}'],
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Header(level: 1, text: 'BY PAYMENT METHOD'),
            pw.TableHelper.fromTextArray(
              context: context,
              headers: const ['Method', 'Amount'],
              data: byMethod.entries.map((e) => [e.key.toUpperCase(), 'PHP ${e.value}']).toList(),
            ),
            pw.SizedBox(height: 20),
            pw.Header(level: 1, text: 'BY CAMPAIGN / CATEGORY'),
            pw.TableHelper.fromTextArray(
              context: context,
              headers: const ['Category', 'Amount'],
              data: byCampaign.entries.map((e) => [e.key, 'PHP ${e.value}']).toList(),
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      final base64Str = base64Encode(bytes);
      final url = 'data:application/pdf;base64,$base64Str';
      final name = 'financial_report_${_template}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      if (kIsWeb) {
        (html.AnchorElement(href: url)..setAttribute('download', name)).click();
      } else {
        await Printing.sharePdf(bytes: bytes, filename: name);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report generated. Download started.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  Icon(Icons.summarize_outlined, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Financial Reports',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _template,
                        decoration: const InputDecoration(labelText: 'Template'),
                        items: const [
                          DropdownMenuItem(value: 'pnl', child: Text('P&L')),
                          DropdownMenuItem(value: 'donor_statements', child: Text('Donor Statements')),
                        ],
                        onChanged: (v) => setState(() => _template = v ?? 'pnl'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _pickFrom,
                              icon: const Icon(Icons.date_range_outlined),
                              label: Text('From: ${_from.toIso8601String().split('T').first}'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _pickTo,
                              icon: const Icon(Icons.event_outlined),
                              label: Text('To: ${_to.toIso8601String().split('T').first}'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _run,
                          child: _busy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Run & Download'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Generated report will download as a file.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
