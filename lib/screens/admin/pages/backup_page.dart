import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../../services/local_storage.dart';
import '../../../services/export_service.dart';

class AdminBackupPage extends StatefulWidget {
  const AdminBackupPage({super.key});

  @override
  State<AdminBackupPage> createState() => _AdminBackupPageState();
}

class _AdminBackupPageState extends State<AdminBackupPage> {
  String _dataType = 'All Records';
  final List<_HistoryItem> _history = [];
  bool _busy = false;

  List<Map<String, dynamic>> _collectRecords() {
    final box = Hive.box(LocalStorageService.recordsBox);
    final values = box.values.toList();
    final List<Map<String, dynamic>> items = [];
    for (final v in values) {
      if (v is Map) {
        final m = Map<String, dynamic>.from(v);
        if (_dataType != 'All Records') {
          if ((m['type'] ?? '').toString().toLowerCase() != _dataType.toLowerCase()) continue;
        }
        items.add(m);
      }
    }
    return items;
  }

  List<List<dynamic>> _toCsvRows(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return [];
    final headers = <String>{};
    for (final m in items) {
      headers.addAll(m.keys.map((e) => e.toString()));
    }
    final cols = headers.toList();
    final rows = <List<dynamic>>[];
    rows.add(cols);
    for (final m in items) {
      rows.add(cols.map((k) => m[k]).toList());
    }
    return rows;
  }

  Future<void> _doExport(bool csv) async {
    setState(() => _busy = true);
    try {
      final items = _collectRecords();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final base = _dataType.replaceAll(' ', '_').toLowerCase();
      if (csv) {
        final rows = _toCsvRows(items);
        await ExportService.exportCsv('export_${base}_$ts.csv', rows);
      } else {
        await ExportService.exportJson('export_${base}_$ts.json', items);
      }
      setState(() => _history.insert(0, _HistoryItem(kind: csv ? 'CSV' : 'JSON', count: items.length, when: DateTime.now())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 800;
          final gap = isNarrow ? 12.0 : 16.0;

          Widget main = Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Data Backup and Export', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      const Text('Data Type:'),
                      DropdownButton<String>(
                        value: _dataType,
                        items: const [
                          DropdownMenuItem(value: 'All Records', child: Text('All Records')),
                          DropdownMenuItem(value: 'baptism', child: Text('Baptism')),
                          DropdownMenuItem(value: 'marriage', child: Text('Marriage')),
                          DropdownMenuItem(value: 'funeral', child: Text('Funeral')),
                          DropdownMenuItem(value: 'confirmation', child: Text('Confirmation')),
                        ],
                        onChanged: (v) => setState(() => _dataType = v ?? 'All Records'),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _doExport(true),
                        icon: const Icon(Icons.table_chart),
                        label: const Text('Export CSV'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _doExport(false),
                        icon: const Icon(Icons.data_object),
                        label: const Text('Export JSON'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Export History', style: Theme.of(context).textTheme.titleMedium),
                  const Divider(),
                  // Use fixed height on narrow screens to avoid Expanded in unconstrained Card
                  if (isNarrow)
                    SizedBox(
                      height: 280,
                      child: _history.isEmpty
                          ? const Center(child: Text('No exports yet'))
                          : ListView.separated(
                              itemCount: _history.length,
                              separatorBuilder: (_, __) => const Divider(height: 0),
                              itemBuilder: (_, i) {
                                final h = _history[i];
                                return ListTile(
                                  leading: const Icon(Icons.history),
                                  title: Text('${h.kind} export • ${h.count} items'),
                                  subtitle: Text(h.when.toLocal().toString()),
                                );
                              },
                            ),
                    )
                  else
                    Expanded(
                      child: _history.isEmpty
                          ? const Center(child: Text('No exports yet'))
                          : ListView.separated(
                              itemCount: _history.length,
                              separatorBuilder: (_, __) => const Divider(height: 0),
                              itemBuilder: (_, i) {
                                final h = _history[i];
                                return ListTile(
                                  leading: const Icon(Icons.history),
                                  title: Text('${h.kind} export • ${h.count} items'),
                                  subtitle: Text(h.when.toLocal().toString()),
                                );
                              },
                            ),
                    ),
                ],
              ),
            ),
          );

          Widget side = Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cloud Backup Settings', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: false,
                    onChanged: (_) {},
                    title: const Text('Automatic Backups'),
                    subtitle: const Text('This is a local-only app demo. Cloud controls are placeholders.'),
                  ),
                ],
              ),
            ),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                main,
                SizedBox(height: gap),
                side,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: main),
              SizedBox(width: gap),
              SizedBox(width: 360, child: side),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryItem {
  final String kind;
  final int count;
  final DateTime when;
  _HistoryItem({required this.kind, required this.count, required this.when});
}
