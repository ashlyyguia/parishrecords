import 'package:flutter/material.dart';
import '../../../services/export_service.dart';
import '../../../services/admin_repository.dart';

class AdminBackupPage extends StatefulWidget {
  const AdminBackupPage({super.key});

  @override
  State<AdminBackupPage> createState() => _AdminBackupPageState();
}

class _AdminBackupPageState extends State<AdminBackupPage> {
  String _dataType = 'All Records';
  String _dateRange = 'All Time';
  final List<_HistoryItem> _history = [];
  bool _busy = false;
  final AdminRepository _adminRepo = AdminRepository();

  int _dateRangeDays() {
    switch (_dateRange) {
      case 'Today':
        return 1;
      case 'Last 7 Days':
        return 7;
      case 'Last 30 Days':
        return 30;
      default:
        return 3650;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRecords() async {
    final records = await _adminRepo.listRecent(
      limit: 1000,
      days: _dateRangeDays(),
    );
    final List<Map<String, dynamic>> items = [];

    for (final r in records) {
      if (_dataType != 'All Records') {
        if (r.type.name.toLowerCase() != _dataType.toLowerCase()) {
          continue;
        }
      }
      items.add({
        'id': r.id,
        'type': r.type.name,
        'name': r.name,
        'date': r.date.toIso8601String(),
        'imagePath': r.imagePath,
        'parish': r.parish,
        'notes': r.notes,
        'certificateStatus': r.certificateStatus.name,
      });
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
      final items = await _fetchRecords();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final base = _dataType.replaceAll(' ', '_').toLowerCase();
      if (csv) {
        final rows = _toCsvRows(items);
        await ExportService.exportCsv('export_${base}_$ts.csv', rows);
      } else {
        await ExportService.exportJson('export_${base}_$ts.json', items);
      }
      setState(
        () => _history.insert(
          0,
          _HistoryItem(
            kind: csv ? 'CSV' : 'JSON',
            count: items.length,
            when: DateTime.now(),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doExportPdf() async {
    setState(() => _busy = true);
    try {
      final items = await _fetchRecords();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final base = _dataType.replaceAll(' ', '_').toLowerCase();
      final subtitle = '$_dataType • $_dateRange';
      await ExportService.exportPdf(
        'report_${base}_$ts.pdf',
        items,
        title: 'Parish Records Report',
        subtitle: subtitle,
      );
      setState(
        () => _history.insert(
          0,
          _HistoryItem(kind: 'PDF', count: items.length, when: DateTime.now()),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.of(context).size.width;
    final bool isPhoneLayout = viewportWidth < 800;

    Widget content = Padding(
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
                  Text(
                    'Data Backup and Export',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
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
                          DropdownMenuItem(
                            value: 'All Records',
                            child: Text('All Records'),
                          ),
                          DropdownMenuItem(
                            value: 'baptism',
                            child: Text('Baptism'),
                          ),
                          DropdownMenuItem(
                            value: 'marriage',
                            child: Text('Marriage'),
                          ),
                          DropdownMenuItem(
                            value: 'funeral',
                            child: Text('Funeral'),
                          ),
                          DropdownMenuItem(
                            value: 'confirmation',
                            child: Text('Confirmation'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _dataType = v ?? 'All Records'),
                      ),
                      const Text('Date Range:'),
                      DropdownButton<String>(
                        value: _dateRange,
                        items: const [
                          DropdownMenuItem(
                            value: 'All Time',
                            child: Text('All Time'),
                          ),
                          DropdownMenuItem(
                            value: 'Today',
                            child: Text('Today'),
                          ),
                          DropdownMenuItem(
                            value: 'Last 7 Days',
                            child: Text('Last 7 Days'),
                          ),
                          DropdownMenuItem(
                            value: 'Last 30 Days',
                            child: Text('Last 30 Days'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _dateRange = v ?? 'All Time'),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _doExport(true),
                        icon: const Icon(Icons.table_chart),
                        label: const Text('Download Excel (CSV)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _doExport(false),
                        icon: const Icon(Icons.data_object),
                        label: const Text('Download Backup (JSON)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _doExportPdf,
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Download Report (PDF)'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Export History',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Divider(),
                  // Use fixed height on narrow screens to avoid Expanded in unconstrained Card
                  if (isNarrow)
                    SizedBox(
                      height: 280,
                      child: _history.isEmpty
                          ? const Center(child: Text('No exports yet'))
                          : ListView.separated(
                              itemCount: _history.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 0),
                              itemBuilder: (_, i) {
                                final h = _history[i];
                                return ListTile(
                                  leading: const Icon(Icons.history),
                                  title: Text(
                                    '${h.kind} export • ${h.count} items',
                                  ),
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
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 0),
                              itemBuilder: (_, i) {
                                final h = _history[i];
                                return ListTile(
                                  leading: const Icon(Icons.history),
                                  title: Text(
                                    '${h.kind} export • ${h.count} items',
                                  ),
                                  subtitle: Text(h.when.toLocal().toString()),
                                );
                              },
                            ),
                    ),
                ],
              ),
            ),
          );

          if (isNarrow) {
            return main;
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: main)],
          );
        },
      ),
    );

    if (isPhoneLayout) {
      return SingleChildScrollView(child: content);
    }

    return content;
  }
}

class _HistoryItem {
  final String kind;
  final int count;
  final DateTime when;
  _HistoryItem({required this.kind, required this.count, required this.when});
}
