import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/records_provider.dart';
import '../../models/record.dart';

class RecordsListScreen extends ConsumerStatefulWidget {
  const RecordsListScreen({super.key});

  @override
  ConsumerState<RecordsListScreen> createState() => _RecordsListScreenState();
}

class _RecordsListScreenState extends ConsumerState<RecordsListScreen> {
  final _searchCtrl = TextEditingController();
  RecordType? _selectedType;
  CertificateStatus? _selectedStatus;
  String? _selectedParish;
  DateTimeRange? _dateRange;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isCertificateRequest(ParishRecord record) {
    final notes = record.notes;
    if (notes == null || notes.isEmpty) return false;
    try {
      final decoded = json.decode(notes);
      if (decoded is! Map<String, dynamic>) return false;
      final type =
          (decoded['requestType'] as String?) ??
          (decoded['request_type'] as String?);
      return type == 'certificate_request';
    } catch (_) {
      return false;
    }
  }

  Future<void> _openNewRecordWithOcr() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Scan New Record'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'baptism'),
            child: const Text('Baptism (OCR)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'marriage'),
            child: const Text('Marriage (OCR)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'confirmation'),
            child: const Text('Confirmation (OCR)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'death'),
            child: const Text('Death (OCR)'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      switch (result) {
        case 'baptism':
          await context.push('/records/new/baptism', extra: 'ocr');
          break;
        case 'marriage':
          await context.push('/records/new/marriage', extra: 'ocr');
          break;
        case 'confirmation':
          await context.push('/records/new/confirmation', extra: 'ocr');
          break;
        case 'death':
          await context.push('/records/new/death', extra: 'ocr');
          break;
      }
    }
  }

  List<ParishRecord> _filteredRecords(List<ParishRecord> records) {
    final query = _searchCtrl.text.trim().toLowerCase();

    return records.where((r) {
      // Type filter
      if (_selectedType != null && r.type != _selectedType) {
        return false;
      }

      // Certificate status filter
      if (_selectedStatus != null && r.certificateStatus != _selectedStatus) {
        return false;
      }

      // Parish filter
      if (_selectedParish != null && _selectedParish!.isNotEmpty) {
        final parish = (r.parish ?? '').toLowerCase();
        if (parish != _selectedParish!.toLowerCase()) {
          return false;
        }
      }

      // Date range filter
      if (_dateRange != null) {
        final d = r.date;
        if (d.isBefore(_dateRange!.start) || d.isAfter(_dateRange!.end)) {
          return false;
        }
      }

      // Text search: name, type, parish, raw notes (OCR / JSON)
      if (query.isNotEmpty) {
        final name = r.name.toLowerCase();
        final type = r.type.name.toLowerCase();
        final parish = (r.parish ?? '').toLowerCase();
        final notes = (r.notes ?? '').toLowerCase();

        if (!name.contains(query) &&
            !type.contains(query) &&
            !parish.contains(query) &&
            !notes.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Future<void> _openNewRecord() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add New Record'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'baptism'),
            child: const Text('Baptism'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'marriage'),
            child: const Text('Marriage'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'confirmation'),
            child: const Text('Confirmation'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'death'),
            child: const Text('Death'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      switch (result) {
        case 'baptism':
          await context.push('/records/new/baptism');
          break;
        case 'marriage':
          await context.push('/records/new/marriage');
          break;
        case 'confirmation':
          await context.push('/records/new/confirmation');
          break;
        case 'death':
          await context.push('/records/new/death');
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(recordsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final df = DateFormat.yMd();

    // Build distinct parish list for filter dropdown
    final parishes = <String>{};
    for (final r in records) {
      final p = r.parish;
      if (p != null && p.trim().isNotEmpty) {
        parishes.add(p.trim());
      }
    }

    final filteredRecords = _filteredRecords(records);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          // Enhanced App Bar
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.primary.withValues(alpha: 0.1),
                      colorScheme.surface,
                    ],
                  ),
                ),
              ),
            ),
            title: Text(
              'Parish Records',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: colorScheme.tertiary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.tertiary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: _openNewRecordWithOcr,
                  icon: Icon(
                    Icons.document_scanner_outlined,
                    color: colorScheme.onPrimary,
                  ),
                  tooltip: 'Add Record with OCR',
                ),
              ),
              Container(
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: _openNewRecord,
                  icon: Icon(Icons.add_rounded, color: colorScheme.onPrimary),
                  tooltip: 'Add New Record',
                ),
              ),
            ],
          ),

          // Search Section
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        labelText: 'Search records...',
                        hintText: 'Enter name, parish, or notes',
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: colorScheme.primary,
                        ),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {});
                                },
                                icon: Icon(
                                  Icons.clear_rounded,
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: colorScheme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      onChanged: (value) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Type filter
                        DropdownButton<RecordType?>(
                          value: _selectedType,
                          hint: const Text('All types'),
                          onChanged: (value) {
                            setState(() => _selectedType = value);
                          },
                          items: [
                            const DropdownMenuItem<RecordType?>(
                              value: null,
                              child: Text('All types'),
                            ),
                            ...RecordType.values.map(
                              (t) => DropdownMenuItem<RecordType?>(
                                value: t,
                                child: Text(_capitalize(t.name)),
                              ),
                            ),
                          ],
                        ),
                        // Certificate status filter
                        DropdownButton<CertificateStatus?>(
                          value: _selectedStatus,
                          hint: const Text('Any status'),
                          onChanged: (value) {
                            setState(() => _selectedStatus = value);
                          },
                          items: const [
                            DropdownMenuItem<CertificateStatus?>(
                              value: null,
                              child: Text('Any status'),
                            ),
                            DropdownMenuItem<CertificateStatus?>(
                              value: CertificateStatus.pending,
                              child: Text('Pending'),
                            ),
                            DropdownMenuItem<CertificateStatus?>(
                              value: CertificateStatus.approved,
                              child: Text('Approved'),
                            ),
                            DropdownMenuItem<CertificateStatus?>(
                              value: CertificateStatus.rejected,
                              child: Text('Rejected'),
                            ),
                          ],
                        ),
                        // Parish filter
                        if (parishes.isNotEmpty)
                          DropdownButton<String?>(
                            value: _selectedParish,
                            hint: const Text('All parishes'),
                            onChanged: (value) {
                              setState(() => _selectedParish = value);
                            },
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('All parishes'),
                              ),
                              ...parishes.map(
                                (p) => DropdownMenuItem<String?>(
                                  value: p,
                                  child: Text(p),
                                ),
                              ),
                            ],
                          ),
                        // Date range filter
                        OutlinedButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final initialStart =
                                _dateRange?.start ??
                                DateTime(now.year, now.month, 1);
                            final initialEnd =
                                _dateRange?.end ??
                                now.add(const Duration(days: 1));
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(1900),
                              lastDate: DateTime(now.year + 1),
                              initialDateRange: DateTimeRange(
                                start: initialStart,
                                end: initialEnd,
                              ),
                            );
                            if (picked != null) {
                              setState(() => _dateRange = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            _dateRange == null
                                ? 'Any date'
                                : '${df.format(_dateRange!.start)} - ${df.format(_dateRange!.end)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Records List
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            sliver: records.isEmpty
                ? SliverFillRemaining(child: _buildEmptyState(colorScheme))
                : SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index >= filteredRecords.length) return null;

                      final record = filteredRecords[index];
                      return _buildRecordCard(record, colorScheme, df);
                    }, childCount: filteredRecords.length),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.folder_outlined,
              size: 64,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Records Found',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start by adding your first parish record',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _openNewRecord,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Record'),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(
    ParishRecord record,
    ColorScheme colorScheme,
    DateFormat df,
  ) {
    final isSyncing = record.id.startsWith('tmp_');
    final isCertificateRequest = _isCertificateRequest(record);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: () => context.push('/records/${record.id}'),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Record Type Icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getRecordTypeColor(
                      record.type,
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _iconForType(record.type),
                    color: _getRecordTypeColor(record.type),
                    size: 24,
                  ),
                ),

                const SizedBox(width: 16),

                // Record Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _capitalize(record.type.name),
                        style: TextStyle(
                          fontSize: 14,
                          color: _getRecordTypeColor(record.type),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        df.format(record.date),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),

                // Status Badge (only for certificate requests)
                if (isCertificateRequest)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(
                            record.certificateStatus,
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          record.certificateStatus.name.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _getStatusColor(record.certificateStatus),
                          ),
                        ),
                      ),
                      if (isSyncing)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Syncing…',
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),

                const SizedBox(width: 8),

                // Actions: View details & Edit
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'View details',
                      onPressed: () => context.push('/records/${record.id}'),
                      icon: Icon(
                        Icons.visibility_outlined,
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit record',
                      onPressed: () {
                        switch (record.type) {
                          case RecordType.baptism:
                            context.push('/records/new/baptism', extra: record);
                            break;
                          case RecordType.marriage:
                            context.push(
                              '/records/new/marriage',
                              extra: record,
                            );
                            break;
                          case RecordType.confirmation:
                            context.push(
                              '/records/new/confirmation',
                              extra: record,
                            );
                            break;
                          case RecordType.funeral:
                            context.push('/records/new/death', extra: record);
                            break;
                        }
                      },
                      icon: Icon(
                        Icons.edit_outlined,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getRecordTypeColor(RecordType type) {
    switch (type) {
      case RecordType.baptism:
        return Colors.blue;
      case RecordType.marriage:
        return Colors.pink;
      case RecordType.confirmation:
        return Colors.purple;
      case RecordType.funeral:
        return Colors.grey;
    }
  }

  IconData _iconForType(RecordType type) {
    switch (type) {
      case RecordType.baptism:
        return Icons.water_drop_outlined;
      case RecordType.marriage:
        return Icons.favorite_outline;
      case RecordType.confirmation:
        return Icons.verified_outlined;
      case RecordType.funeral:
        return Icons.person_outline;
    }
  }

  Color _getStatusColor(CertificateStatus status) {
    switch (status) {
      case CertificateStatus.approved:
        return Colors.green;
      case CertificateStatus.pending:
        return Colors.orange;
      case CertificateStatus.rejected:
        return Colors.red;
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
