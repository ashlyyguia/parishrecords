import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import '../../../models/record.dart';
import '../../../services/records_repository.dart';
import '../../../services/admin_repository.dart';
import '../../../utils/record_date_filter.dart';
import '../../../widgets/record_date_range_filters.dart';
import '../../../utils/manual_register_notes.dart';
import '../../../widgets/manual_register_launcher.dart';
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
            'record': r,
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
    if (_from != null || _to != null) {
      it = it.where((m) {
        final d = DateTime.tryParse((m['date'] ?? '').toString());
        if (d == null) return false;
        return RecordDateFilter.matches(d, from: _from, to: _to);
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

  Future<void> _editRecord(ParishRecord record) async {
    final data = ManualRegisterNotes.tryDecode(record.notes);
    if (record.type == RecordType.baptism &&
        data != null &&
        ManualRegisterNotes.usesFlatRegisterLayout(data)) {
      await context.push('/admin/records/manual-baptism', extra: record);
    } else if (record.type == RecordType.marriage &&
        data != null &&
        ManualRegisterNotes.usesFlatMarriageRegisterLayout(data)) {
      await context.push('/admin/records/manual-marriage', extra: record);
    } else {
      switch (record.type) {
        case RecordType.baptism:
          await context.push('/admin/records/new/baptism', extra: record);
          break;
        case RecordType.marriage:
          await context.push('/admin/records/new/marriage', extra: record);
          break;
        case RecordType.confirmation:
          await context.push('/admin/records/new/confirmation', extra: record);
          break;
        case RecordType.funeral:
          await context.push('/admin/records/new/death', extra: record);
          break;
      }
    }
    if (mounted) await _loadFromBackend();
  }

  Future<void> _openNewRecord() async {
    await _openManualRegister();
  }

  Future<void> _openManualRegister() async {
    await ManualRegisterLauncher.open(
      context,
      recordsBasePath: '/admin/records',
    );
    if (mounted) await _loadFromBackend();
  }

  Future<void> _viewRecord(ParishRecord record) async {
    await context.push('/admin/records/${record.id}', extra: record);
    if (mounted) await _loadFromBackend();
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
                  'Paste CSV with headers: id(optional), name, type, date(YYYY-MM-DD). '
                  'Type must be baptism or marriage only.',
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
        if (type != 'baptism' && type != 'marriage') {
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
      if (mounted) await _loadFromBackend();
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

  Future<void> _deleteRecord(ParishRecord record) async {
    try {
      await _repo.deleteForType(record.id, record.type);
      if (!mounted) return;
      setState(() {
        _records = _records.where((r) => r.id != record.id).toList();
      });
      await _loadFromBackend();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Record deleted.')));
    } catch (e) {
      try {
        await _adminRepo.delete(record.id);
        if (!mounted) return;
        setState(() {
          _records = _records.where((r) => r.id != record.id).toList();
        });
        await _loadFromBackend();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Record deleted.')));
      } catch (e2) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e2')));
      }
    }
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
    final parishSet = <String>{};
    for (final m in items) {
      final p = (m['parish'] ?? '').toString();
      if (p.isNotEmpty) parishSet.add(p);
    }
    final parishOptions = ['all', ...parishSet.toList()..sort()];
    final colorScheme = Theme.of(context).colorScheme;

    final isCompact = MediaQuery.sizeOf(context).width < 600;
    final pagePadding = isCompact ? 12.0 : 24.0;

    final Widget headerSection = Padding(
      padding: EdgeInsets.fromLTRB(pagePadding, pagePadding, pagePadding, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminDesignSystem.pageHeader(
            context,
            title: 'Records Management',
            subtitle:
                'Manage baptism and marriage register records (${items.length} total).',
            icon: Icons.folder_shared_outlined,
            actions: [],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pagePadding),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _openManualRegister,
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('Manual Register'),
                ),
                OutlinedButton.icon(
                  onPressed: _importCsvDialog,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Import CSV'),
                ),
                FilledButton.icon(
                  onPressed: () => context.push('/admin/ocr/upload'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.cyan.shade700,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Add Record (OCR)'),
                ),
                FilledButton.icon(
                  onPressed: () => context.push('/admin/certificate-scan'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text('Scan Certificate'),
                ),
                OutlinedButton.icon(
                  onPressed: _openNewRecord,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Record'),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final Widget filtersSection = Padding(
      padding: EdgeInsets.all(isCompact ? 12 : 20),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: isCompact ? double.infinity : 320,
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
          RecordDateRangeFilters(
            from: _from,
            to: _to,
            fromLabel: 'From Date',
            toLabel: 'To Date',
            onFromChanged: (d) => setState(() => _from = d),
            onToChanged: (d) => setState(() => _to = d),
            onClear: () => setState(() {
              _from = null;
              _to = null;
            }),
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
    );

    final Widget emptyState = AdminDesignSystem.emptyState(
      context,
      message: _records.isEmpty
          ? 'No records yet. Add baptism or marriage register entries.'
          : 'No records found matching your filters.',
      icon: _records.isEmpty ? Icons.folder_open_outlined : Icons.search_off,
      actionLabel: _records.isEmpty ? 'Add Record' : 'Clear Search',
      onAction: _records.isEmpty
          ? _openNewRecord
          : () {
              _searchCtrl.clear();
              setState(() {
                _type = 'all';
                _parish = 'all';
                _from = null;
                _to = null;
              });
            },
    );

    // Compact (mobile) screens scroll the whole page so tall filter bars can't
    // squeeze the table's viewport to zero. Wide screens keep the pinned
    // header with an independently scrolling table.
    if (isCompact) {
      return Container(
        decoration: AdminDesignSystem.pageBackground(context),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: pagePadding),
          child: Column(
            children: [
              headerSection,
              Padding(
                padding: EdgeInsets.all(pagePadding),
                child: Container(
                  decoration: AdminDesignSystem.cardDecoration(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      filtersSection,
                      const Divider(height: 1),
                      if (items.isEmpty)
                        SizedBox(height: 320, child: emptyState)
                      else
                        _buildTable(items, colorScheme, shrinkWrap: true),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: AdminDesignSystem.pageBackground(context),
      child: Column(
        children: [
          headerSection,
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(pagePadding),
              child: Container(
                decoration: AdminDesignSystem.cardDecoration(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    filtersSection,
                    const Divider(height: 1),
                    Expanded(
                      child: items.isEmpty
                          ? emptyState
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
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
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

  Widget _buildTable(
    List<Map<String, dynamic>> items,
    ColorScheme colorScheme, {
    bool shrinkWrap = false,
  }) {
    final df = DateFormat.yMMMd();
    final theme = Theme.of(context);
    final primary = colorScheme.primary;

    return ListView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.sizeOf(context).width - 40,
                ),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    primary.withValues(alpha: 0.1),
                  ),
                  headingTextStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: primary,
                  ),
                  dataRowMinHeight: 48,
                  columnSpacing: 24,
                  horizontalMargin: 16,
                  columns: const [
                    DataColumn(label: Text('Record Date')),
                    DataColumn(label: Text('Full Name')),
                    DataColumn(label: Text('Sacrament Type')),
                    DataColumn(label: Text('Parish Location')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: items.map((m) {
                    final id = m['id']?.toString() ?? '';
                    final dateStr = m['date']?.toString() ?? '';
                    final date = DateTime.tryParse(dateStr) ?? DateTime.now();
                    final type = m['type']?.toString() ?? '';

                    Color badgeColor;
                    switch (type) {
                      case 'baptism':
                        badgeColor = Colors.blue;
                        break;
                      case 'marriage':
                        badgeColor = Colors.pink;
                        break;
                      case 'funeral':
                        badgeColor = Colors.grey;
                        break;
                      default:
                        badgeColor = Colors.orange;
                        break;
                    }

                    return DataRow(
                      cells: [
                        DataCell(Text(df.format(date))),
                        DataCell(
                          Text(
                            m['name']?.toString() ?? 'Untitled',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        DataCell(
                          AdminDesignSystem.statusBadge(
                            context,
                            type.toUpperCase(),
                            badgeColor,
                          ),
                        ),
                        DataCell(Text(m['parish']?.toString() ?? '-')),
                        DataCell(
                          PopupMenuButton<String>(
                            onSelected: (action) async {
                              final record = m['record'];
                              if (action == 'view' && record is ParishRecord) {
                                _viewRecord(record);
                              } else if (action == 'edit' &&
                                  record is ParishRecord) {
                                _editRecord(record);
                              } else if (action == 'certificate' &&
                                  id.isNotEmpty) {
                                context.push(
                                  '/admin/records/$id/certificate',
                                  extra: _strToType(type),
                                );
                              } else if (action == 'delete') {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete record?'),
                                    content: Text(
                                      'Are you sure you want to delete "${m['name']}"?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: colorScheme.error,
                                        ),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  final record = m['record'];
                                  if (record is ParishRecord) {
                                    await _deleteRecord(record);
                                  }
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'view',
                                child: Row(
                                  children: [
                                    Icon(Icons.visibility_outlined, size: 18),
                                    SizedBox(width: 8),
                                    Text('View Details'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 18),
                                    SizedBox(width: 8),
                                    Text('Edit'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'certificate',
                                child: Row(
                                  children: [
                                    Icon(Icons.card_membership, size: 18),
                                    SizedBox(width: 8),
                                    Text('Certificate'),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
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
          ),
        ),
      ],
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
