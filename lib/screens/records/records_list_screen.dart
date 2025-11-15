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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ParishRecord> _filteredRecords(List<ParishRecord> records) {
    if (_searchCtrl.text.isEmpty) return records;
    final query = _searchCtrl.text.toLowerCase();
    return records.where((r) =>
        r.name.toLowerCase().contains(query) ||
        r.type.name.toLowerCase().contains(query)).toList();
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
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'certificate_request'),
            child: const Text('Certificate Request'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'enhanced_baptism'),
            child: const Text('Enhanced Baptism Form'),
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
        case 'certificate_request':
          await context.push('/records/certificate-request');
          break;
        case 'enhanced_baptism':
          await context.push('/records/enhanced-baptism');
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
                  icon: Icon(
                    Icons.add_rounded,
                    color: colorScheme.onPrimary,
                  ),
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
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    labelText: 'Search records...',
                    hintText: 'Enter name, type, or date',
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
                              color: colorScheme.onSurface.withValues(alpha: 0.6),
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
              ),
            ),
          ),
          
          // Records List
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            sliver: records.isEmpty
                ? SliverFillRemaining(
                    child: _buildEmptyState(colorScheme),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final filteredRecords = _filteredRecords(records);
                        if (index >= filteredRecords.length) return null;
                        
                        final record = filteredRecords[index];
                        return _buildRecordCard(record, colorScheme, df);
                      },
                      childCount: _filteredRecords(records).length,
                    ),
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

  Widget _buildRecordCard(ParishRecord record, ColorScheme colorScheme, DateFormat df) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
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
                    color: _getRecordTypeColor(record.type).withValues(alpha: 0.1),
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
                
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(record.certificateStatus).withValues(alpha: 0.1),
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
                
                const SizedBox(width: 8),
                
                // Actions Menu
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'scan') {
                      await context.push('/records/${record.id}/scan');
                    } else if (v == 'verify') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Verify & submit feature coming soon'),
                          backgroundColor: colorScheme.inverseSurface,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    } else if (v == 'issue') {
                      if (record.certificateStatus == CertificateStatus.approved) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Certificate issued successfully'),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Certificate must be approved by admin first'),
                            backgroundColor: Colors.orange,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'scan',
                      child: Row(
                        children: [
                          Icon(Icons.document_scanner_outlined, size: 18, color: colorScheme.primary),
                          const SizedBox(width: 12),
                          const Text('Scan Certificate (OCR)'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'verify',
                      child: Row(
                        children: [
                          Icon(Icons.verified_outlined, size: 18, color: colorScheme.secondary),
                          const SizedBox(width: 12),
                          const Text('Verify & Submit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'issue',
                      child: Row(
                        children: [
                          Icon(Icons.print_outlined, size: 18, color: colorScheme.tertiary),
                          const SizedBox(width: 12),
                          const Text('Issue Certificate'),
                        ],
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

  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
