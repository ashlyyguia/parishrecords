import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/finance_providers.dart';
import '../../../widgets/app_loading.dart';

class DonationsLedgerPage extends ConsumerWidget {
  const DonationsLedgerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final donationsAsync = ref.watch(donationsListProvider(200));

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
                    Icons.volunteer_activism_outlined,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Donations Ledger',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: () => ref.invalidate(donationsListProvider(200)),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: donationsAsync.when(
                  data: (rows) {
                    if (rows.isEmpty) {
                      return const Center(child: Text('No donations found.'));
                    }

                    return Card(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Donor')),
                            DataColumn(label: Text('Amount')),
                            DataColumn(label: Text('Method')),
                            DataColumn(label: Text('Campaign')),
                            DataColumn(label: Text('Reconciled')),
                            DataColumn(label: Text('Actions')),
                          ],
                          rows: [
                            for (final r in rows)
                              DataRow(
                                cells: [
                                  DataCell(Text((r['date'] ?? '—').toString())),
                                  DataCell(
                                    Text(
                                      (r['anonymous'] == true)
                                          ? 'Anonymous'
                                          : (r['donor_name']
                                                        ?.toString()
                                                        .trim()
                                                        .isNotEmpty ==
                                                    true
                                                ? r['donor_name'].toString()
                                                : '—'),
                                    ),
                                  ),
                                  DataCell(
                                    Text(((r['amount'] ?? 0).toString())),
                                  ),
                                  DataCell(
                                    Text((r['method'] ?? '—').toString()),
                                  ),
                                  DataCell(
                                    Text((r['campaign'] ?? '—').toString()),
                                  ),
                                  DataCell(
                                    Text(
                                      r['reconciled'] == true ? 'Yes' : 'No',
                                    ),
                                  ),
                                  DataCell(_ActionsCell(row: r)),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                  loading: () => const Center(child: AppLoading()),
                  error: (e, _) => Center(child: Text('Failed to load: $e')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionsCell extends ConsumerStatefulWidget {
  final Map<String, dynamic> row;
  const _ActionsCell({required this.row});

  @override
  ConsumerState<_ActionsCell> createState() => _ActionsCellState();
}

class _ActionsCellState extends ConsumerState<_ActionsCell> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final id = (widget.row['id'] ?? '').toString();
    final reconciled = widget.row['reconciled'] == true;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.tonal(
          onPressed: _busy || id.isEmpty
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await ref
                        .read(donationsRepositoryProvider)
                        .reconcile(id, reconciled: !reconciled);
                    ref.invalidate(donationsListProvider(200));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            !reconciled
                                ? 'Marked reconciled'
                                : 'Marked unreconciled',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Reconcile failed: $e')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(reconciled ? 'Unreconcile' : 'Reconcile'),
        ),
      ],
    );
  }
}
