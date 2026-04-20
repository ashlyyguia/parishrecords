import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';

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

      final report = resp['report'] is Map ? (resp['report'] as Map) : const {};
      final url = (report['download_url'] ?? '').toString();
      final name = (report['name'] ?? 'report.json').toString();

      if (url.isEmpty) {
        throw Exception('Missing download_url');
      }

      if (kIsWeb && url.startsWith('data:')) {
        (html.AnchorElement(href: url)..setAttribute('download', name)).click();
      } else {
        final uri = Uri.parse(url);
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok) {
          throw Exception('Unable to open download link');
        }
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
