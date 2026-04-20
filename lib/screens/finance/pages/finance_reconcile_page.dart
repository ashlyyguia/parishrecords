import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/finance_providers.dart';

class FinanceReconcilePage extends ConsumerStatefulWidget {
  const FinanceReconcilePage({super.key});

  @override
  ConsumerState<FinanceReconcilePage> createState() =>
      _FinanceReconcilePageState();
}

class _FinanceReconcilePageState extends ConsumerState<FinanceReconcilePage> {
  bool _busy = false;
  List<Map<String, dynamic>> _bankRows = const [];
  List<Map<String, dynamic>> _suggestedMatches = const [];

  Future<void> _pickCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final f = result.files.first;
    final bytes = f.bytes;
    if (bytes == null) return;

    final csvText = utf8.decode(bytes);
    final rows = const CsvToListConverter(eol: '\n').convert(csvText);
    if (rows.isEmpty) return;

    // Expect header: date,amount,description,reference
    final out = <Map<String, dynamic>>[];
    for (int i = 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.isEmpty) continue;
      out.add({
        'date': r.isNotEmpty ? r[0]?.toString() : null,
        'amount': r.length > 1 ? r[1] : null,
        'description': r.length > 2 ? r[2]?.toString() : null,
        'reference': r.length > 3 ? r[3]?.toString() : null,
      });
    }

    setState(() {
      _bankRows = out;
      _suggestedMatches = const [];
    });
  }

  Future<void> _uploadAndSuggest() async {
    if (_bankRows.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref.read(financeRepositoryProvider).bankImport(rows: _bankRows);

      // Suggest matches: match unreconciled donations by amount.
      final donations = await ref
          .read(donationsRepositoryProvider)
          .list(limit: 500);
      final unreconciled = donations
          .where((d) => d['reconciled'] != true)
          .toList();

      final matches = <Map<String, dynamic>>[];
      for (final bank in _bankRows.take(200)) {
        final bankAmount = bank['amount'];
        final bankAmt = bankAmount is num
            ? bankAmount.toDouble()
            : double.tryParse(bankAmount?.toString() ?? '') ?? 0;

        Map<String, dynamic>? best;
        for (final d in unreconciled) {
          final amt = d['amount'] is num
              ? (d['amount'] as num).toDouble()
              : double.tryParse(d['amount']?.toString() ?? '') ?? 0;
          if ((amt - bankAmt).abs() < 0.01) {
            best = d;
            break;
          }
        }

        if (best != null) {
          matches.add({'donation_id': best['id'], 'bank_row': bank});
        }
      }

      setState(() => _suggestedMatches = matches);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${_bankRows.length} bank rows. Suggested ${matches.length} matches.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmMatches() async {
    if (_suggestedMatches.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(financeRepositoryProvider)
          .reconcile(matches: _suggestedMatches);
      ref.invalidate(donationsListProvider(200));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reconciliation applied.')),
        );
      }
      setState(() {
        _bankRows = const [];
        _suggestedMatches = const [];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Reconcile failed: $e')));
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
                  Icon(Icons.rule_folder_outlined, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Reconciliation Workspace',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _pickCsv,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Upload Bank CSV'),
                  ),
                  FilledButton.tonal(
                    onPressed: _busy || _bankRows.isEmpty
                        ? null
                        : _uploadAndSuggest,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Import + Suggest Matches'),
                  ),
                  FilledButton(
                    onPressed: _busy || _suggestedMatches.isEmpty
                        ? null
                        : _confirmMatches,
                    child: const Text('Confirm Matches'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _suggestedMatches.isEmpty
                        ? Text(
                            _bankRows.isEmpty
                                ? 'Upload a CSV file (date,amount,description,reference) to start.'
                                : 'Imported ${_bankRows.length} bank rows. Click "Import + Suggest Matches" to compute suggestions.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _suggestedMatches.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final m = _suggestedMatches[i];
                              final donationId = (m['donation_id'] ?? '')
                                  .toString();
                              final bank = m['bank_row'] is Map
                                  ? (m['bank_row'] as Map)
                                  : const {};
                              return ListTile(
                                title: Text('Donation: $donationId'),
                                subtitle: Text(
                                  '${bank['date'] ?? '—'} • ${bank['description'] ?? '—'}',
                                ),
                                trailing: Text('${bank['amount'] ?? '0'}'),
                              );
                            },
                          ),
                  ),
                ),
              ),
              if (kIsWeb) ...[
                const SizedBox(height: 8),
                Text(
                  'Tip: CSV must include a header row: date,amount,description,reference',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
