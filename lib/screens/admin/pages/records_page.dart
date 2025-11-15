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
  Timer? _timer;
  List<ParishRecord> _records = const [];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadFromBackend(),
    );
  }

  Future<void> _openNewRecord() async {
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('New Record'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'baptism'),
            child: const Text('Baptism Record Entry'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'marriage'),
            child: const Text('Marriage Record Entry'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'confirmation'),
            child: const Text('Confirmation Record Entry'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'death'),
            child: const Text('Death / Burial Record Entry'),
          ),
        ],
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
    _timer?.cancel();
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
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Records Management',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 700;
                      final gap = isNarrow ? 8.0 : 12.0;
                      return Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: gap,
                        spacing: gap,
                        children: [
                          SizedBox(
                            width: isNarrow ? constraints.maxWidth : 360,
                            child: TextField(
                              controller: _searchCtrl,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                hintText: 'Search records',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _loadFromBackend,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh'),
                          ),
                          Text(
                            'Records: ${items.length}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          // Filters group scrollable horizontally when space is tight
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: isNarrow
                                  ? constraints.maxWidth
                                  : constraints.maxWidth - 600,
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  DropdownButton<String>(
                                    value: _type,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'all',
                                        child: Text('All types'),
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
                                        setState(() => _type = v ?? 'all'),
                                  ),
                                  SizedBox(width: gap),
                                  DropdownButton<String>(
                                    value: _parish,
                                    items: [
                                      for (final p in parishOptions)
                                        DropdownMenuItem(
                                          value: p,
                                          child: Text(
                                            p == 'all' ? 'All parishes' : p,
                                          ),
                                        ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _parish = v ?? 'all'),
                                  ),
                                  SizedBox(width: gap),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: _from ?? DateTime.now(),
                                        firstDate: DateTime(1900),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        setState(() => _from = picked);
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.calendar_today_outlined,
                                    ),
                                    label: Text(
                                      _from == null
                                          ? 'From'
                                          : df.format(_from!),
                                    ),
                                  ),
                                  SizedBox(width: isNarrow ? 6 : 8),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: _to ?? DateTime.now(),
                                        firstDate: DateTime(1900),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        setState(() => _to = picked);
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.calendar_month_outlined,
                                    ),
                                    label: Text(
                                      _to == null ? 'To' : df.format(_to!),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Clear dates',
                                    onPressed: (_from == null && _to == null)
                                        ? null
                                        : () => setState(() {
                                            _from = null;
                                            _to = null;
                                          }),
                                    icon: const Icon(Icons.clear),
                                  ),
                                  SizedBox(width: gap),
                                  IconButton(
                                    tooltip: _desc
                                        ? 'Sort: Newest first'
                                        : 'Sort: Oldest first',
                                    onPressed: () =>
                                        setState(() => _desc = !_desc),
                                    icon: Icon(
                                      _desc ? Icons.sort : Icons.sort_by_alpha,
                                    ),
                                  ),
                                  SizedBox(width: isNarrow ? 6 : 8),
                                  OutlinedButton.icon(
                                    onPressed: _selected.isEmpty
                                        ? null
                                        : _bulkDelete,
                                    icon: const Icon(
                                      Icons.delete_sweep_outlined,
                                    ),
                                    label: Text('Delete (${_selected.length})'),
                                  ),
                                  SizedBox(width: isNarrow ? 6 : 8),
                                  OutlinedButton.icon(
                                    onPressed: _selected.isEmpty
                                        ? null
                                        : () => _bulkExport(true),
                                    icon: const Icon(Icons.table_chart),
                                    label: const Text('Export CSV'),
                                  ),
                                  SizedBox(width: isNarrow ? 6 : 8),
                                  OutlinedButton.icon(
                                    onPressed: _selected.isEmpty
                                        ? null
                                        : () => _bulkExport(false),
                                    icon: const Icon(Icons.data_object),
                                    label: const Text('Export JSON'),
                                  ),
                                  SizedBox(width: gap),
                                  Checkbox(
                                    value:
                                        _selected.isNotEmpty &&
                                        _selected.length == items.length,
                                    onChanged: (v) {
                                      setState(() {
                                        if (v == true) {
                                          _selected
                                            ..clear()
                                            ..addAll(
                                              items
                                                  .map(
                                                    (e) =>
                                                        e['id']?.toString() ??
                                                        '',
                                                  )
                                                  .where((id) => id.isNotEmpty),
                                            );
                                        } else {
                                          _selected.clear();
                                        }
                                      });
                                    },
                                  ),
                                  const Text('All'),
                                  SizedBox(width: gap),
                                  FilledButton.icon(
                                    onPressed: _openNewRecord,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Record'),
                                  ),
                                  SizedBox(width: isNarrow ? 6 : 8),
                                  OutlinedButton.icon(
                                    onPressed: _importCsvDialog,
                                    icon: const Icon(
                                      Icons.file_upload_outlined,
                                    ),
                                    label: const Text('Import CSV'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Tooltip(
                            message:
                                _selected.length == items.length &&
                                    items.isNotEmpty
                                ? 'Unselect all'
                                : 'Select all',
                            child: IconButton(
                              onPressed: items.isEmpty
                                  ? null
                                  : () => _toggleSelectAll(items),
                              icon: const Icon(Icons.select_all),
                            ),
                          ),
                          Tooltip(
                            message: 'Delete selected',
                            child: IconButton(
                              onPressed: _selected.isEmpty ? null : _bulkDelete,
                              icon: const Icon(Icons.delete_sweep_outlined),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const Divider(height: 0),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (items.isEmpty) {
                        return const Center(child: Text('No records'));
                      }
                      final w = constraints.maxWidth;
                      int cols = 1;
                      if (w >= 1200) {
                        cols = 4;
                      } else if (w >= 900) {
                        cols = 3;
                      } else if (w >= 600) {
                        cols = 2;
                      }
                      return GridView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 4,
                          childAspectRatio: 3.8,
                        ),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final m = items[i];
                          final key = m['id']?.toString() ?? '';
                          final id = key;
                          final selected = _selected.contains(id);
                          final type = (m['type'] ?? '').toString();
                          final parish = (m['parish'] ?? '').toString();
                          final date = (m['date'] ?? '').toString();
                          final parts = <String>[];
                          if (type.isNotEmpty) parts.add(type);
                          if (parish.isNotEmpty) parts.add(parish);
                          if (date.isNotEmpty) parts.add(date);
                          final subtitle = parts.join(' · ');
                          return Card(
                            elevation: 0,
                            child: ListTile(
                              leading: Checkbox(
                                value: selected,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selected.add(id);
                                    } else {
                                      _selected.remove(id);
                                    }
                                  });
                                },
                              ),
                              title: Text(
                                m['name']?.toString() ?? 'Untitled',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    tooltip: 'Edit',
                                    onPressed: () => _upsert(existing: m),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    onPressed: key.isEmpty
                                        ? null
                                        : () async {
                                            final ok = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text(
                                                  'Delete record?',
                                                ),
                                                content: Text(
                                                  'Are you sure you want to delete "$key"?',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          false,
                                                        ),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          true,
                                                        ),
                                                    child: const Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (ok == true) await _delete(id);
                                          },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
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
