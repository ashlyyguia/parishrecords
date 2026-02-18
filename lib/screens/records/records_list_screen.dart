import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/records_provider.dart';
import '../../models/record.dart';
import 'ocr_record_type_screen.dart';

class RecordsListScreen extends ConsumerStatefulWidget {
  const RecordsListScreen({super.key});

  @override
  ConsumerState<RecordsListScreen> createState() => _RecordsListScreenState();
}

class _RecordsListScreenState extends ConsumerState<RecordsListScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;
  RecordType? _typeFilter;

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
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const OcrRecordTypeScreen(),
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
      if (_typeFilter != null && r.type != _typeFilter) {
        return false;
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
    final type = await Navigator.of(context).push<RecordType?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => const _AddRecordTypeScreen(),
      ),
    );

    if (!mounted || type == null) return;

    switch (type) {
      case RecordType.baptism:
        await context.push('/records/new/baptism');
        break;
      case RecordType.marriage:
        await context.push('/records/new/marriage');
        break;
      case RecordType.confirmation:
        await context.push('/records/new/confirmation');
        break;
      case RecordType.funeral:
        await context.push('/records/new/death');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(recordsProvider);
    final meta = ref.watch(recordsMetaProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final df = DateFormat.yMd();

    final filteredRecords = _filteredRecords(records);
    final showInitialLoading = meta.isLoading && !meta.hasLoadedOnce;
    final showLoadError = meta.lastError != null && records.isEmpty;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(recordsProvider.notifier).load();
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Records refreshed')));
        },
        child: CustomScrollView(
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: 0.6),
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
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
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
                              icon: const Icon(Icons.calendar_today_outlined),
                              label: Text(
                                _dateRange == null
                                    ? 'Filter by date'
                                    : '${df.format(_dateRange!.start)} - ${df.format(_dateRange!.end)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (_dateRange != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Clear date filter',
                              icon: Icon(
                                Icons.clear,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              onPressed: () {
                                setState(() => _dateRange = null);
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildTypeChip(
                              null,
                              'All',
                              Icons.all_inclusive,
                              colorScheme,
                            ),
                            _buildTypeChip(
                              RecordType.baptism,
                              'Baptism',
                              Icons.water_drop_outlined,
                              colorScheme,
                            ),
                            _buildTypeChip(
                              RecordType.marriage,
                              'Marriage',
                              Icons.favorite_outline,
                              colorScheme,
                            ),
                            _buildTypeChip(
                              RecordType.confirmation,
                              'Confirmation',
                              Icons.verified_outlined,
                              colorScheme,
                            ),
                            _buildTypeChip(
                              RecordType.funeral,
                              'Death',
                              Icons.person_outline,
                              colorScheme,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Records List
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              sliver: showInitialLoading
                  ? SliverFillRemaining(child: _buildLoadingState(colorScheme))
                  : showLoadError
                  ? SliverFillRemaining(
                      child: _buildErrorState(colorScheme, meta.lastError),
                    )
                  : filteredRecords.isEmpty
                  ? SliverFillRemaining(
                      child: records.isEmpty
                          ? _buildEmptyState(colorScheme)
                          : _buildNoMatchesState(colorScheme),
                    )
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
      ),
    );
  }

  Widget _buildLoadingState(ColorScheme colorScheme) {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildErrorState(ColorScheme colorScheme, Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'Failed to load records',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error?.toString() ?? 'Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref.read(recordsProvider.notifier).load(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoMatchesState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off,
                size: 48,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No matching records',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filters.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                _searchCtrl.clear();
                setState(() {
                  _dateRange = null;
                  _typeFilter = null;
                });
              },
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear filters'),
            ),
          ],
        ),
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

  Widget _buildTypeChip(
    RecordType? type,
    String label,
    IconData icon,
    ColorScheme colorScheme,
  ) {
    final selected = _typeFilter == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) {
          setState(() {
            _typeFilter = type;
          });
        },
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected
                  ? colorScheme.onPrimary
                  : colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        visualDensity: VisualDensity.compact,
        selectedColor: colorScheme.primary,
        backgroundColor: colorScheme.surfaceContainerHighest.withValues(
          alpha: selected ? 0.4 : 0.2,
        ),
        side: BorderSide(
          color: selected
              ? colorScheme.primary
              : colorScheme.outline.withValues(alpha: 0.4),
        ),
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
    final additional = _parseAdditionalInfo(record);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.08)),
        ),
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
                      Row(
                        children: [
                          Text(
                            _capitalize(record.type.name),
                            style: TextStyle(
                              fontSize: 13,
                              color: _getRecordTypeColor(record.type),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            df.format(record.date),
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (additional.remarks != null &&
                          additional.remarks!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          additional.remarks!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (additional.staffName != null &&
                          additional.staffName!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Prepared by: ${additional.staffName}',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Status / certificate badges
                if (isCertificateRequest || additional.certificateIssued)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (isCertificateRequest)
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
                        )
                      else if (additional.certificateIssued)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'CERT ISSUED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
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

class _RecordAdditionalInfo {
  final bool certificateIssued;
  final String? remarks;
  final String? staffName;

  const _RecordAdditionalInfo({
    required this.certificateIssued,
    this.remarks,
    this.staffName,
  });
}

_RecordAdditionalInfo _parseAdditionalInfo(ParishRecord record) {
  bool issued = false;
  String? remarks;
  String? staffName;

  final raw = record.notes;
  if (raw == null || raw.trim().isEmpty) {
    return const _RecordAdditionalInfo(certificateIssued: false);
  }

  try {
    final decoded = json.decode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const _RecordAdditionalInfo(certificateIssued: false);
    }

    if (record.type == RecordType.baptism) {
      final metadata = decoded['metadata'] as Map<String, dynamic>?;
      if (metadata != null) {
        issued = metadata['certificateIssued'] == true;
        final r = metadata['remarks']?.toString();
        if (r != null && r.isNotEmpty) remarks = r;
        final s = metadata['staffName']?.toString();
        if (s != null && s.isNotEmpty) staffName = s;
      }
    } else {
      final r = decoded['remarks']?.toString();
      if (r != null && r.isNotEmpty) remarks = r;
      final meta = decoded['meta'] as Map<String, dynamic>?;
      if (meta != null) {
        if (meta['certificateIssued'] == true) issued = true;
        final s = meta['staffName']?.toString();
        if (s != null && s.isNotEmpty) staffName = s;
      }
    }
  } catch (_) {
    // ignore parse errors; fall back to defaults
  }

  return _RecordAdditionalInfo(
    certificateIssued: issued,
    remarks: remarks,
    staffName: staffName,
  );
}

class _AddRecordTypeScreen extends StatelessWidget {
  const _AddRecordTypeScreen();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Record')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RecordTypeButton(
              label: 'Baptism',
              description: 'Create a new baptism record',
              color: Colors.blue,
              icon: Icons.water_drop_outlined,
              onTap: () => Navigator.of(context).pop(RecordType.baptism),
            ),
            const SizedBox(height: 12),
            _RecordTypeButton(
              label: 'Marriage',
              description: 'Create a new marriage record',
              color: Colors.pink,
              icon: Icons.favorite_outline,
              onTap: () => Navigator.of(context).pop(RecordType.marriage),
            ),
            const SizedBox(height: 12),
            _RecordTypeButton(
              label: 'Confirmation',
              description: 'Create a new confirmation record',
              color: Colors.purple,
              icon: Icons.verified_outlined,
              onTap: () => Navigator.of(context).pop(RecordType.confirmation),
            ),
            const SizedBox(height: 12),
            _RecordTypeButton(
              label: 'Death',
              description: 'Create a new death / funeral record',
              color: Colors.grey,
              icon: Icons.person_outline,
              onTap: () => Navigator.of(context).pop(RecordType.funeral),
            ),
            const Spacer(),
            Text(
              'Choose a record type to continue',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordTypeButton extends StatelessWidget {
  final String label;
  final String description;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _RecordTypeButton({
    required this.label,
    required this.description,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
