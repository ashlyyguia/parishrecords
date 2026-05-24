import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../models/record.dart';
import '../../../providers/records_provider.dart';
import '../../../utils/manual_register_notes.dart';
import '../../../utils/record_date_filter.dart';
import '../../../widgets/manual_register_launcher.dart';
import '../../../widgets/record_date_range_filters.dart';
import '../../admin/admin_design_system.dart';

bool _isTemporaryManualRecord(ParishRecord record) {
  final data = ManualRegisterNotes.tryDecode(record.notes);
  if (data == null) return false;
  return data['status'] == 'temporary' ||
      data['source'] == 'manual_baptism_register' ||
      data['source'] == 'manual_marriage_register';
}

class StaffRecordsPage extends ConsumerStatefulWidget {
  const StaffRecordsPage({super.key});

  @override
  ConsumerState<StaffRecordsPage> createState() => _StaffRecordsPageState();
}

class _StaffRecordsPageState extends ConsumerState<StaffRecordsPage> {
  final _searchCtrl = TextEditingController();
  String _type = 'all';
  String _parish = 'all';
  bool _temporaryOnly = false;
  DateTime? _from;
  DateTime? _to;
  bool _desc = true;

  @override
  void initState() {
    super.initState();
    // Refresh records when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(recordsProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _load(List<ParishRecord> records) {
    final items = records
        .map(
          (r) => {
            'id': r.id,
            'name': r.name,
            'type': r.type.name,
            'date': r.date.toIso8601String(),
            'parish': r.parish,
            'record': r,
          },
        )
        .toList();

    final q = _searchCtrl.text.trim().toLowerCase();
    Iterable<Map<String, dynamic>> it = items;
    if (_type != 'all') {
      it = it.where((m) => (m['type'] ?? '').toString() == _type);
    }
    if (_temporaryOnly) {
      it = it.where((m) {
        final record = m['record'] as ParishRecord?;
        return record != null && _isTemporaryManualRecord(record);
      });
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
    list.sort((a, b) {
      final ad = ((a['date'] ?? '')).toString();
      final bd = ((b['date'] ?? '')).toString();
      final cmp = ad.compareTo(bd);
      return _desc ? -cmp : cmp;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(recordsProvider);
    final meta = ref.watch(recordsMetaProvider);
    final items = _load(records);

    final parishSet = <String>{};
    for (final r in records) {
      final p = (r.parish ?? '').trim();
      if (p.isNotEmpty) parishSet.add(p);
    }
    final parishOptions = ['all', ...parishSet.toList()..sort()];

    if (meta.isLoading && records.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (meta.lastError != null && records.isEmpty) {
      final colorScheme = Theme.of(context).colorScheme;
      return Center(
        child: Text(
          'Error: ${meta.lastError}',
          style: TextStyle(color: colorScheme.error),
        ),
      );
    }

    return Container(
      decoration: AdminDesignSystem.pageBackground(context),
      child: Column(
        children: [
          AdminDesignSystem.pageHeader(
            context,
            title: 'Records Management',
            subtitle:
                'Manage, search, and view ${items.length} parish records.',
            icon: Icons.folder_shared_outlined,
            actions: [
              AdminDesignSystem.actionButton(
                context,
                label: 'Manual Register',
                icon: Icons.edit_note_outlined,
                onPressed: () => ManualRegisterLauncher.open(context),
                isPrimary: true,
                color: Colors.white,
              ),
              AdminDesignSystem.actionButton(
                context,
                label: 'Refresh',
                icon: Icons.refresh,
                onPressed: () => ref.read(recordsProvider.notifier).load(),
                isPrimary: false,
                color: Colors.white,
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
                              onClear: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
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
                            onPressed: () =>
                                ref.read(recordsProvider.notifier).load(),
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Refresh',
                          ),
                          FilterChip(
                            label: const Text('Temporary only'),
                            selected: _temporaryOnly,
                            onSelected: (v) =>
                                setState(() => _temporaryOnly = v),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: items.isEmpty
                          ? AdminDesignSystem.emptyState(
                              context,
                              message: _temporaryOnly
                                  ? 'No temporary manual register records yet.'
                                  : 'No records found matching your filters.',
                              icon: _temporaryOnly
                                  ? Icons.edit_note_outlined
                                  : Icons.search_off,
                              actionLabel: _temporaryOnly
                                  ? 'Open Manual Register'
                                  : 'Clear Filters',
                              onAction: () {
                                if (_temporaryOnly) {
                                  ManualRegisterLauncher.open(context);
                                  return;
                                }
                                _searchCtrl.clear();
                                setState(() {
                                  _type = 'all';
                                  _parish = 'all';
                                  _from = null;
                                  _to = null;
                                  _desc = true;
                                  _temporaryOnly = false;
                                });
                              },
                            )
                          : _buildTable(items),
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

  Widget _buildTable(List<Map<String, dynamic>> items) {
    final colorScheme = Theme.of(context).colorScheme;
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
              final record = m['record'] as ParishRecord?;

              final badgeColor = _badgeColorForType(type);
              final isTemporary =
                  record != null && _isTemporaryManualRecord(record);

              return DataRow(
                cells: [
                  DataCell(Text(df.format(date))),
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          m['name']?.toString() ?? 'Untitled',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (isTemporary)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: AdminDesignSystem.statusBadge(
                              context,
                              'TEMPORARY',
                              Colors.amber.shade800,
                            ),
                          ),
                      ],
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
                            if (id.isNotEmpty && record != null) {
                              _openRecord(record);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'Edit',
                          color: colorScheme.primary,
                          onPressed: () {
                            if (record != null) _editRecord(record);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.card_membership, size: 20),
                          tooltip: 'Certificate',
                          color: Colors.orange,
                          onPressed: () {
                            if (record != null) _openCertificate(record);
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

  Color _badgeColorForType(String type) {
    switch (type.toLowerCase()) {
      case 'baptism':
        return Colors.blue;
      case 'marriage':
        return Colors.pink;
      case 'funeral':
        return Colors.grey;
      case 'confirmation':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  void _openRecord(ParishRecord record) {
    context.push('/staff/records/${record.id}');
  }

  void _openCertificate(ParishRecord record) {
    context.push('/staff/records/${record.id}/certificate', extra: record.type);
  }

  void _editRecord(ParishRecord record) {
    final data = ManualRegisterNotes.tryDecode(record.notes);
    if (record.type == RecordType.baptism &&
        data != null &&
        ManualRegisterNotes.usesFlatRegisterLayout(data)) {
      context.push('/staff/records/manual-baptism', extra: record);
      return;
    }
    if (record.type == RecordType.marriage &&
        data != null &&
        ManualRegisterNotes.usesFlatMarriageRegisterLayout(data)) {
      context.push('/staff/records/manual-marriage', extra: record);
      return;
    }

    final extra = {'record': record, 'fromStaff': true};
    switch (record.type) {
      case RecordType.baptism:
        context.push('/records/new/baptism', extra: extra);
        break;
      case RecordType.marriage:
        context.push('/records/new/marriage', extra: extra);
        break;
      case RecordType.confirmation:
        context.push('/records/new/confirmation', extra: extra);
        break;
      case RecordType.funeral:
        context.push('/records/new/death', extra: extra);
        break;
    }
  }
}
