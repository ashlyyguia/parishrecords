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
    try {
      await _adminRepo.delete(key);
      if (!mounted) return;
      setState(() {
        _records = _records.where((r) => r.id != key).toList();
      });
      await _loadFromBackend();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Record deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
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
            subtitle:
                'Manage, search, and export ${items.length} parish records securely.',
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
                label: 'OCR Scan',
                icon: Icons.document_scanner,
                onPressed: () => context.go('/admin/ocr/upload'),
                isPrimary: true,
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
                              DropdownMenuItem(
                                value: 'all',
                                child: Text('All Types'),
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
                          _buildDropdownFilter(
                            value: _parish,
                            items: [
                              for (final p in parishOptions)
                                DropdownMenuItem(
                                  value: p,
                                  child: Text(p == 'all' ? 'All Parishes' : p),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _parish = v ?? 'all'),
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
                            icon: Icon(
                              _desc ? Icons.arrow_downward : Icons.arrow_upward,
                            ),
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
                    const Divider(height: 1),
                    // DATA TABLE
                    Expanded(
                      child: items.isEmpty
                          ? AdminDesignSystem.emptyState(
                              context,
                              message:
                                  'No records found matching your filters.',
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
    ColorScheme colorScheme,
  ) {
    final df = DateFormat.yMMMd();

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width - 48,
          ),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            dataRowMinHeight: 64,
            dataRowMaxHeight: 64,
            showCheckboxColumn: false,
            columns: const [
              DataColumn(
                label: Text(
                  'Record Date',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Full Name',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Sacrament Type',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Parish Location',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataColumn(
                label: Text(
                  'Actions',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.visibility_outlined, size: 20),
                          tooltip: 'View Details',
                          color: colorScheme.secondary,
                          onPressed: () {
                            if (id.isNotEmpty) {
                              context.push('/admin/records/$id');
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'Edit',
                          color: colorScheme.primary,
                          onPressed: () {
                            final record = m['record'];
                            if (record is ParishRecord) {
                              _editRecord(record);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.card_membership, size: 20),
                          tooltip: 'Certificate',
                          color: Colors.orange,
                          onPressed: () {
                            if (id.isNotEmpty) {
                              context.push(
                                '/admin/records/$id/certificate',
                                extra: _strToType(type),
                              );
                            }
                          },
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
                                content: Text(
                                  'Are you sure you want to delete "${m['name']}"?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: colorScheme.error,
                                    ),
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
