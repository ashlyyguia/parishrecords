import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import '../../../models/record.dart';
import '../../../services/records_repository.dart';
import '../../../services/admin_repository.dart';
import '../../../services/export_service.dart';
import '../admin_design_system.dart';

class AdminRecordsPage extends StatefulWidget {
  const AdminRecordsPage({super.key});

  @override
  State<AdminRecordsPage> createState() => _AdminRecordsPageState();
}

class _AdminRecordsPageState extends State<AdminRecordsPage> {
  final _searchCtrl = TextEditingController();
  String _type = 'all';
  bool _desc = true;
  final _uuid = const Uuid();
  final Set<String> _selected = <String>{};
  String _parish = 'all';
  DateTime? _from;
  DateTime? _to;
  final _repo = RecordsRepository();
  final _adminRepo = AdminRepository();
  StreamSubscription<List<ParishRecord>>? _sub;
  List<ParishRecord> _records = const [];

  @override
  void initState() {
    super.initState();
    _loadFromBackend();
  }

  Future<void> _openNewRecord() async {
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Record'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.water_drop_outlined, color: Colors.blue),
              title: const Text('Baptism Record'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () => Navigator.pop(ctx, 'baptism'),
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border, color: Colors.pink),
              title: const Text('Marriage Record'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () => Navigator.pop(ctx, 'marriage'),
            ),
            ListTile(
              leading: const Icon(Icons.local_fire_department_outlined, color: Colors.orange),
              title: const Text('Confirmation Record'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () => Navigator.pop(ctx, 'confirmation'),
            ),
            ListTile(
              leading: const Icon(Icons.church_outlined, color: Colors.grey),
              title: const Text('Funeral Record'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onTap: () => Navigator.pop(ctx, 'death'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || type == null) return;
    switch (type) {
      case 'baptism':
        context.go('/admin/records/new/baptism');
        break;
      case 'marriage':
        context.go('/admin/records/new/marriage');
        break;
      case 'confirmation':
        context.go('/admin/records/new/confirmation');
        break;
      case 'death':
        context.go('/admin/records/new/death');
        break;
    }
  }

  Future<void> _loadFromBackend() async {
    try {
      // Use the regular records repository that includes local storage
      final list = await _repo.list();
      if (mounted) setState(() => _records = list);
      developer.log(
        'Admin loaded ${list.length} records',
        name: 'AdminRecordsPage',
      );
    } catch (e) {
      if (!mounted) return;
      developer.log('Admin records load failed: $e', name: 'AdminRecordsPage');
      // Try fallback with admin repo
      try {
        final list = await _adminRepo.listRecent(limit: 100, days: 365);
        if (mounted) setState(() => _records = list);
        developer.log(
          'Admin loaded ${list.length} records from admin repo',
          name: 'AdminRecordsPage',
        );
      } catch (e2) {
        developer.log(
          'Admin fallback also failed: $e2',
          name: 'AdminRecordsPage',
        );
      }
    }
  }

  void _toggleSelectAll(List<Map<String, dynamic>> items) {
    setState(() {
      if (_selected.length == items.length && items.isNotEmpty) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(
            items
                .map((e) => e['id']?.toString() ?? '')
                .where((id) => id.isNotEmpty),
          );
      }
    });
  }

  List<Map<String, dynamic>> _load() {
    // Transform Firestore records to the map structure the UI expects
    final items = _records
        .map(
          (r) => {
            'id': r.id,
            'name': r.name,
            'type': r.type.name,
            'typeIndex': r.type.index,
            'date': r.date.toIso8601String(),
            'parish': r.parish,
            'notes': r.notes,
          },
        )
        .toList();
    // filter
    final q = _searchCtrl.text.trim().toLowerCase();
    Iterable<Map<String, dynamic>> it = items;
    if (_type != 'all') {
      it = it.where((m) => (m['type'] ?? '').toString() == _type);
    }
    if (_parish != 'all') {
      it = it.where((m) => (m['parish'] ?? '').toString() == _parish);
    }
    if (q.isNotEmpty) {
      it = it.where(
        (m) => m.values.any(
          (val) => val?.toString().toLowerCase().contains(q) ?? false,
        ),
      );
    }
    // date range inclusive
    if (_from != null || _to != null) {
      it = it.where((m) {
        final s = (m['date'] ?? '').toString();
        final d = DateTime.tryParse(s);
        if (d == null) return false;
        if (_from != null &&
            d.isBefore(DateTime(_from!.year, _from!.month, _from!.day))) {
          return false;
        }
        if (_to != null &&
            d.isAfter(DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59))) {
          return false;
        }
        return true;
      });
    }
    final list = it.toList();
    // sort by date desc/asc
    list.sort((a, b) {
      final ad = ((a['date'] ?? '')).toString();
      final bd = ((b['date'] ?? '')).toString();
      final cmp = ad.compareTo(bd);
      return _desc ? -cmp : cmp;
    });
    return list;
  }

  Future<void> _bulkDelete() async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected?'),
        content: Text('This will delete ${_selected.length} record(s).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final id in _selected) {
      await _adminRepo.delete(id);
    }
    setState(() => _selected.clear());
  }

  Future<void> _bulkExport(bool csv) async {
    if (_selected.isEmpty) return;
    final items = <Map<String, dynamic>>[];
    final current = _load();
    for (final id in _selected) {
      final m = current.firstWhere(
        (e) => (e['id']?.toString() ?? '') == id,
        orElse: () => {},
      );
      if (m.isNotEmpty) items.add(m);
    }
    if (items.isEmpty) return;
    final base =
        'selected_${DateTime.now().toIso8601String().replaceAll(':', '-')}'
            .replaceAll(' ', '_');
    if (csv) {
      // Build headers dynamically
      final headers = <String>{};
      for (final m in items) {
        headers.addAll(m.keys.map((e) => e.toString()));
      }
      final cols = headers.toList();
      final rows = <List<dynamic>>[cols];
      for (final m in items) {
        rows.add(cols.map((k) => m[k]).toList());
      }
      await ExportService.exportCsv('records_$base.csv', rows);
    } else {
      await ExportService.exportJson('records_$base.json', items);
    }
  }

  Future<void> _upsert({Map<String, dynamic>? existing}) async {
    final firstCtrl = TextEditingController(
      text: existing?['firstName']?.toString() ?? '',
    );
    final lastCtrl = TextEditingController(
      text: existing?['lastName']?.toString() ?? '',
    );
    final parishCtrl = TextEditingController(
      text: existing?['parish']?.toString() ?? '',
    );
    final notesCtrl = TextEditingController(
      text: existing?['notes']?.toString() ?? '',
    );
    final nameFallback = existing?['name']?.toString() ?? '';
    String type = existing?['type']?.toString() ?? 'baptism';
    DateTime date = () {
      final raw = existing?['date']?.toString();
      if (raw == null || raw.isEmpty) return DateTime.now();
      return DateTime.tryParse(raw) ?? DateTime.now();
    }();

    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(existing == null ? 'Add Record' : 'Edit Record'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: firstCtrl,
                          decoration: InputDecoration(
                            labelText: 'First name',
                            errorText: error,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: lastCtrl,
                          decoration: InputDecoration(
                            labelText: 'Last name',
                            errorText: error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
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
                    onChanged: (v) => setStateDialog(() => type = v ?? type),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Date: ${date.toLocal().toString().split(' ').first}',
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: date,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setStateDialog(() => date = picked);
                          }
                        },
                        child: const Text('Pick date'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: parishCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Parish (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final f = firstCtrl.text.trim();
                  final l = lastCtrl.text.trim();
                  if (f.isEmpty && l.isEmpty && nameFallback.isEmpty) {
                    setStateDialog(() => error = 'Enter first or last name');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true) {
      final id = existing?['id']?.toString() ?? _uuid.v4();
      final f = firstCtrl.text.trim();
      final l = lastCtrl.text.trim();
      final fullName = (f.isEmpty && l.isEmpty)
          ? nameFallback
          : [f, l].where((x) => x.isNotEmpty).join(' ');
      if (existing == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add via admin not supported yet')),
          );
        }
      } else {
        await _adminRepo.update(
          id,
          name: fullName,
          parish: parishCtrl.text.trim().isEmpty
              ? null
              : parishCtrl.text.trim(),
        );
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _importCsvDialog() async {
    final ctrl = TextEditingController();
    int imported = 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Import CSV'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Paste CSV with headers: id(optional), name, type, date(YYYY-MM-DD)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'id,name,type,date',
                ),
                minLines: 8,
                maxLines: 12,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final rows = const CsvToListConverter(
        eol: '\n',
      ).convert(ctrl.text.trim());
      if (rows.isEmpty) return;
      final headers = rows.first.map((e) => e.toString().trim()).toList();
      final idxName = headers.indexOf('name');
      final idxType = headers.indexOf('type');
      final idxDate = headers.indexOf('date');
      for (int i = 1; i < rows.length; i++) {
        final r = rows[i];
        if (r.isEmpty) continue;
        final name = idxName >= 0 && idxName < r.length
            ? r[idxName].toString().trim()
            : '';
        final type = idxType >= 0 && idxType < r.length
            ? r[idxType].toString().trim().toLowerCase()
            : '';
        final dateStr = idxDate >= 0 && idxDate < r.length
            ? r[idxDate].toString().trim()
            : '';
        if (name.isEmpty) continue;
        if (!(type == 'baptism' ||
            type == 'marriage' ||
            type == 'funeral' ||
            type == 'confirmation')) {
          continue;
        }
        DateTime? d = DateTime.tryParse(dateStr);
        d ??= DateTime.now();
        await _repo.add(
          _strToType(type),
          name,
          DateTime(d.year, d.month, d.day),
        );
        imported++;
      }
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Imported $imported records.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _delete(String key) async {
    await _adminRepo.delete(key);
    setState(() {});
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _load();
    final df = DateFormat.yMMMd();
    final parishSet = <String>{};
    for (final m in items) {
      final p = (m['parish'] ?? '').toString();
      if (p.isNotEmpty) parishSet.add(p);
    }
    final parishOptions = ['all', ...parishSet.toList()..sort()];
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: AdminDesignSystem.pageBackground(context),
      child: Column(
        children: [
          AdminDesignSystem.pageHeader(
            context,
            title: 'Records Management',
            subtitle: 'Manage, search, and export ${items.length} parish records securely.',
            icon: Icons.folder_shared_outlined,
            actions: [
              AdminDesignSystem.actionButton(
                context,
                label: 'Import CSV',
                icon: Icons.file_upload_outlined,
                onPressed: _importCsvDialog,
                isPrimary: false,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              AdminDesignSystem.actionButton(
                context,
                label: 'Add Record',
                icon: Icons.add,
                onPressed: _openNewRecord,
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                decoration: AdminDesignSystem.cardDecoration(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // FILTERS BAR
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 320,
                            child: AdminDesignSystem.searchBar(
                              context,
                              controller: _searchCtrl,
                              hint: 'Search records by name...',
                              onChanged: (_) => setState(() {}),
                              onClear: () {},
                            ),
                          ),
                          _buildDropdownFilter(
                            value: _type,
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All Types')),
                              DropdownMenuItem(value: 'baptism', child: Text('Baptism')),
                              DropdownMenuItem(value: 'marriage', child: Text('Marriage')),
                              DropdownMenuItem(value: 'funeral', child: Text('Funeral')),
                              DropdownMenuItem(value: 'confirmation', child: Text('Confirmation')),
                            ],
                            onChanged: (v) => setState(() => _type = v ?? 'all'),
                          ),
                          _buildDropdownFilter(
                            value: _parish,
                            items: [
                              for (final p in parishOptions)
                                DropdownMenuItem(
                                  value: p,
                                  child: Text(p == 'all' ? 'All Parishes' : p),
                                ),
                            ],
                            onChanged: (v) => setState(() => _parish = v ?? 'all'),
                          ),
                          _buildDateFilter(
                            label: _from == null ? 'From Date' : df.format(_from!),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _from ?? DateTime.now(),
                                firstDate: DateTime(1900),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) setState(() => _from = picked);
                            },
                          ),
                          _buildDateFilter(
                            label: _to == null ? 'To Date' : df.format(_to!),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _to ?? DateTime.now(),
                                firstDate: DateTime(1900),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) setState(() => _to = picked);
                            },
                          ),
                          if (_from != null || _to != null)
                            IconButton(
                              onPressed: () => setState(() { _from = null; _to = null; }),
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear Dates',
                            ),
                          IconButton(
                            onPressed: () => setState(() => _desc = !_desc),
                            icon: Icon(_desc ? Icons.arrow_downward : Icons.arrow_upward),
                            tooltip: 'Toggle Sort',
                          ),
                          IconButton(
                            onPressed: _loadFromBackend,
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Refresh',
                          ),
                        ],
                      ),
                    ),
                    if (_selected.isNotEmpty)
                      Container(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        child: Row(
                          children: [
                            Text(
                              '${_selected.length} items selected',
                              style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _bulkExport(true),
                              icon: const Icon(Icons.table_chart_outlined, size: 18),
                              label: const Text('Export CSV'),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: _bulkDelete,
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Delete Selected'),
                              style: FilledButton.styleFrom(
                                backgroundColor: colorScheme.error,
                                foregroundColor: colorScheme.onError,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 1),
                    // DATA TABLE
                    Expanded(
                      child: items.isEmpty
                          ? AdminDesignSystem.emptyState(
                              context,
                              message: 'No records found matching your filters.',
                              icon: Icons.search_off,
                              actionLabel: 'Clear Search',
                              onAction: () {
                                _searchCtrl.clear();
                                setState(() {
                                  _type = 'all';
                                  _parish = 'all';
                                  _from = null;
                                  _to = null;
                                });
                              },
                            )
                          : _buildTable(items, colorScheme),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownFilter({
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          items: items,
          onChanged: onChanged,
          borderRadius: BorderRadius.circular(12),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _buildDateFilter({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> items, ColorScheme colorScheme) {
    final df = DateFormat.yMMMd();

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 48),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
            dataRowMinHeight: 64,
            dataRowMaxHeight: 64,
            showCheckboxColumn: true,
            onSelectAll: (val) => _toggleSelectAll(items),
            columns: const [
              DataColumn(label: Text('Record Date', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Full Name', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Sacrament Type', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Parish Location', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: items.map((m) {
              final id = m['id']?.toString() ?? '';
              final dateStr = m['date']?.toString() ?? '';
              final date = DateTime.tryParse(dateStr) ?? DateTime.now();
              final type = m['type']?.toString() ?? '';
              
              Color badgeColor;
              switch (type) {
                case 'baptism': badgeColor = Colors.blue; break;
                case 'marriage': badgeColor = Colors.pink; break;
                case 'funeral': badgeColor = Colors.grey; break;
                default: badgeColor = Colors.orange; break;
              }

              return DataRow(
                selected: _selected.contains(id),
                onSelectChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selected.add(id);
                    } else {
                      _selected.remove(id);
                    }
                  });
                },
                cells: [
                  DataCell(Text(df.format(date))),
                  DataCell(
                    Text(
                      m['name']?.toString() ?? 'Untitled',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(AdminDesignSystem.statusBadge(context, type.toUpperCase(), badgeColor)),
                  DataCell(Text(m['parish']?.toString() ?? '-')),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'Edit',
                          color: colorScheme.primary,
                          onPressed: () => _upsert(existing: m),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          tooltip: 'Delete',
                          color: colorScheme.error,
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete record?'),
                                content: Text('Are you sure you want to delete "${m['name']}"?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) await _delete(id);
                          },
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
  }

  RecordType _strToType(String s) {
    switch (s.toLowerCase()) {
      case 'baptism':
        return RecordType.baptism;
      case 'marriage':
        return RecordType.marriage;
      case 'funeral':
        return RecordType.funeral;
      case 'confirmation':
        return RecordType.confirmation;
      default:
        return RecordType.baptism;
    }
  }
}
