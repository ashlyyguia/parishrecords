import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:universal_html/html.dart' as html;

import '../../../widgets/page_header.dart';
import '../../../services/report_pdf_service.dart';
import '../../../services/donations_repository.dart';
import '../../../utils/firestore_date.dart';

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
      final all = await DonationsRepository().list(limit: 5000);
      final end = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
      final inRange = all.where((d) {
        final dt = parseFirestoreDate(d['created_at']);
        return dt != null && !dt.isBefore(_from) && !dt.isAfter(end) && d['amount_pending'] != true;
      }).toList();
      final Uint8List bytes = _template == 'donor_statements'
          ? await ReportPdfService.donorStatements(donations: inRange, from: _from, to: end, generatedBy: ReportPdfService.currentUserLabel())
          : await ReportPdfService.financialOverview(donations: inRange, from: _from, to: end, generatedBy: ReportPdfService.currentUserLabel());
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(
                icon: Icons.summarize_outlined,
                title: 'Financial Reports',
                subtitle: 'Generate P&L statements and donor statements.',
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final stackDates = constraints.maxWidth < 520;
                      return Column(
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
                          if (stackDates) ...[
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _busy ? null : _pickFrom,
                                icon: const Icon(Icons.date_range_outlined),
                                label: Text('From: ${_from.toIso8601String().split('T').first}'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _busy ? null : _pickTo,
                                icon: const Icon(Icons.event_outlined),
                                label: Text('To: ${_to.toIso8601String().split('T').first}'),
                              ),
                            ),
                          ] else
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
                      );
                    },
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
