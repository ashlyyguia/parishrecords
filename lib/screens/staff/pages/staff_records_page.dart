import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../models/record.dart';
import '../../../providers/records_provider.dart';
import '../../../services/records_repository.dart';

class StaffRecordsPage extends ConsumerStatefulWidget {
  const StaffRecordsPage({super.key});

  @override
  ConsumerState<StaffRecordsPage> createState() => _StaffRecordsPageState();
}

class _StaffRecordsPageState extends ConsumerState<StaffRecordsPage> {
  final _searchCtrl = TextEditingController();
  String _type = 'all';
  String _status = 'all';

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

  List<ParishRecord> _filterRecords(List<ParishRecord> records) {
    return records.where((r) {
      // Type filter
      if (_type != 'all' && r.type.value != _type) {
        return false;
      }

      // Status filter
      if (_status != 'all') {
        if (_status == 'pending' &&
            r.certificateStatus != CertificateStatus.pending) {
          return false;
        }
        if (_status == 'approved' &&
            r.certificateStatus != CertificateStatus.approved) {
          return false;
        }
        if (_status == 'rejected' &&
            r.certificateStatus != CertificateStatus.rejected) {
          return false;
        }
      }

      // Search filter
      final query = _searchCtrl.text.toLowerCase();
      if (query.isNotEmpty) {
        final nameMatch = r.name.toLowerCase().contains(query);
        final typeMatch = r.type.value.toLowerCase().contains(query);
        final parishMatch = (r.parish ?? '').toLowerCase().contains(query);
        if (!nameMatch && !typeMatch && !parishMatch) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final records = ref.watch(recordsProvider);
    final meta = ref.watch(recordsMetaProvider);

    final filtered = _filterRecords(records);

    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                _buildHeader(theme, colorScheme),

                // Filters
                _buildFilters(colorScheme),

                const SizedBox(height: 16),

                meta.isLoading && records.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : meta.lastError != null && records.isEmpty
                    ? Center(
                        child: Text(
                          'Error: ${meta.lastError}',
                          style: TextStyle(color: colorScheme.error),
                        ),
                      )
                    : _buildRecordsList(filtered, theme, colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: 0.1),
            colorScheme.secondary.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.folder_copy_outlined,
                  color: colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sacrament Records',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'View and manage parish sacrament records',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Search bar
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search by name, type, or parish...',
              prefixIcon: Icon(Icons.search, color: colorScheme.primary),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),

          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(
                  width: 180,
                  child: _buildFilterDropdown(
                    value: _type,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Types')),
                      DropdownMenuItem(
                        value: 'baptism',
                        child: Text('Baptism'),
                      ),
                      DropdownMenuItem(
                        value: 'marriage',
                        child: Text('Marriage'),
                      ),
                      DropdownMenuItem(
                        value: 'confirmation',
                        child: Text('Confirmation'),
                      ),
                      DropdownMenuItem(
                        value: 'funeral',
                        child: Text('Death/Burial'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? 'all'),
                    icon: Icons.category_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 180,
                  child: _buildFilterDropdown(
                    value: _status,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Status')),
                      DropdownMenuItem(
                        value: 'pending',
                        child: Text('Pending'),
                      ),
                      DropdownMenuItem(
                        value: 'approved',
                        child: Text('Approved'),
                      ),
                      DropdownMenuItem(
                        value: 'rejected',
                        child: Text('Rejected'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? 'all'),
                    icon: Icons.verified_outlined,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: Icon(icon, size: 18),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildRecordsList(
    List<ParishRecord> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No records found',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (_searchCtrl.text.isNotEmpty ||
                _type != 'all' ||
                _status != 'all')
              TextButton(
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() {
                    _type = 'all';
                    _status = 'all';
                  });
                },
                child: const Text('Clear filters'),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        return _buildRecordCard(record, theme, colorScheme);
      },
    );
  }

  Widget _buildRecordCard(
    ParishRecord record,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final typeColor = _getTypeColor(record.type);
    final statusColor = _getStatusColor(record.certificateStatus);
    final statusText = _getStatusText(record.certificateStatus);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: () => _viewRecordDetails(record),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getTypeIcon(record.type),
                      color: typeColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${record.type.value.toUpperCase()} • ${DateFormat('MMM dd, yyyy').format(record.date)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (record.parish != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.church_outlined,
                      size: 16,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        record.parish!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (record.notes != null && record.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  record.notes!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _viewRecordDetails(ParishRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(record.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Type', record.type.value),
              _buildDetailRow(
                'Date',
                DateFormat('MMMM dd, yyyy').format(record.date),
              ),
              if (record.parish != null)
                _buildDetailRow('Parish', record.parish!),
              _buildDetailRow(
                'Status',
                _getStatusText(record.certificateStatus),
              ),
              if (record.notes != null && record.notes!.isNotEmpty)
                _buildDetailRow('Notes', record.notes!),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showCorrectionDialog(record);
            },
            icon: const Icon(Icons.report_outlined),
            label: const Text('Request Correction'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  IconData _getTypeIcon(RecordType type) {
    switch (type) {
      case RecordType.baptism:
        return Icons.child_care;
      case RecordType.marriage:
        return Icons.favorite;
      case RecordType.confirmation:
        return Icons.verified_user;
      case RecordType.funeral:
        return Icons.local_florist;
    }
  }

  Color _getTypeColor(RecordType type) {
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

  Future<void> _showCorrectionDialog(ParishRecord record) async {
    final messageCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request Correction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Record: ${record.name}'),
            const SizedBox(height: 12),
            TextField(
              controller: messageCtrl,
              decoration: const InputDecoration(
                labelText: 'Correction Details',
                hintText: 'Describe what needs to be corrected...',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (messageCtrl.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (confirmed == true && messageCtrl.text.trim().isNotEmpty) {
      try {
        await ref
            .read(recordsRepositoryProvider)
            .submitCorrectionRequest(record.id, messageCtrl.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Correction request submitted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
        }
      }
    }
    messageCtrl.dispose();
  }

  Color _getStatusColor(CertificateStatus status) {
    switch (status) {
      case CertificateStatus.approved:
        return Colors.green;
      case CertificateStatus.rejected:
        return Colors.red;
      case CertificateStatus.pending:
        return Colors.orange;
    }
  }

  String _getStatusText(CertificateStatus status) {
    switch (status) {
      case CertificateStatus.approved:
        return 'Approved';
      case CertificateStatus.rejected:
        return 'Rejected';
      case CertificateStatus.pending:
        return 'Pending';
    }
  }
}
