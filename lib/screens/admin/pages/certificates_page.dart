// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/records_provider.dart';
import '../../../models/record.dart';
import '../admin_design_system.dart';

class AdminCertificatesPage extends ConsumerWidget {
  const AdminCertificatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final records = ref.watch(recordsProvider);

    final pendingRecords = records
        .where((r) => r.certificateStatus == CertificateStatus.pending)
        .toList();
    final approvedRecords = records
        .where((r) => r.certificateStatus == CertificateStatus.approved)
        .toList();
    final rejectedRecords = records
        .where((r) => r.certificateStatus == CertificateStatus.rejected)
        .toList();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Container(
        decoration: AdminDesignSystem.pageBackground(context),
        child: SafeArea(
          child: Column(
            children: [
              // Modern Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: AdminDesignSystem.pageHeader(
                  context,
                  title: 'Certificate Management',
                  subtitle: 'Review and approve certificate requests',
                  icon: Icons.verified,
                ),
              ),

              // Statistics Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildCompactStatCard(
                        context,
                        title: 'Pending',
                        value: pendingRecords.length.toString(),
                        icon: Icons.pending_actions,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactStatCard(
                        context,
                        title: 'Approved',
                        value: approvedRecords.length.toString(),
                        icon: Icons.verified,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCompactStatCard(
                        context,
                        title: 'Rejected',
                        value: rejectedRecords.length.toString(),
                        icon: Icons.cancel,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Tabs
              Expanded(
                child: DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: AdminDesignSystem.cardDecoration(context),
                        child: TabBar(
                          isScrollable: true,
                          labelColor: colorScheme.primary,
                          unselectedLabelColor: colorScheme.onSurface
                              .withOpacity(0.6),
                          indicatorColor: colorScheme.primary,
                          tabs: [
                            Tab(text: 'Pending (${pendingRecords.length})'),
                            Tab(text: 'Approved (${approvedRecords.length})'),
                            Tab(text: 'Rejected (${rejectedRecords.length})'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildRecordsList(
                              pendingRecords,
                              'pending',
                              ref,
                              colorScheme,
                              context,
                            ),
                            _buildRecordsList(
                              approvedRecords,
                              'approved',
                              ref,
                              colorScheme,
                              context,
                            ),
                            _buildRecordsList(
                              rejectedRecords,
                              'rejected',
                              ref,
                              colorScheme,
                              context,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordsList(
    List<ParishRecord> records,
    String status,
    WidgetRef ref,
    ColorScheme colorScheme,
    BuildContext context,
  ) {
    if (records.isEmpty) {
      return AdminDesignSystem.emptyState(
        context,
        message: 'No $status certificates',
        icon: _getStatusIcon(status),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        return _buildRecordCard(context, record, status, ref, colorScheme);
      },
    );
  }

  Widget _buildRecordCard(
    BuildContext context,
    ParishRecord record,
    String status,
    WidgetRef ref,
    ColorScheme colorScheme,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AdminDesignSystem.cardDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: _getRecordTypeColor(record.type).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getRecordTypeIcon(record.type),
                    color: _getRecordTypeColor(record.type),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${record.type.value.toUpperCase()} • ${_formatDate(record.date)}',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                AdminDesignSystem.statusBadge(
                  context,
                  status.toUpperCase(),
                  _getStatusColor(status),
                ),
              ],
            ),
            if (record.notes != null && record.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                record.notes!,
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.7),
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (status == 'pending') ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _updateCertificateStatus(record.id, 'approved', ref),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _updateCertificateStatus(record.id, 'rejected', ref),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompactStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AdminDesignSystem.cardDecoration(context),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _updateCertificateStatus(
    String recordId,
    String newStatus,
    WidgetRef ref,
  ) {
    CertificateStatus status;
    switch (newStatus) {
      case 'approved':
        status = CertificateStatus.approved;
        break;
      case 'rejected':
        status = CertificateStatus.rejected;
        break;
      default:
        status = CertificateStatus.pending;
    }
    ref
        .read(recordsProvider.notifier)
        .updateCertificateStatus(recordId, status);
  }

  IconData _getRecordTypeIcon(RecordType? type) {
    switch (type) {
      case RecordType.baptism:
        return Icons.child_care;
      case RecordType.marriage:
        return Icons.favorite;
      case RecordType.confirmation:
        return Icons.verified_user;
      case RecordType.funeral:
        return Icons.person_outline;
      default:
        return Icons.description;
    }
  }

  Color _getRecordTypeColor(RecordType? type) {
    switch (type) {
      case RecordType.baptism:
        return Colors.blue;
      case RecordType.marriage:
        return Colors.pink;
      case RecordType.confirmation:
        return Colors.purple;
      case RecordType.funeral:
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'approved':
        return Icons.check_circle_outline;
      case 'rejected':
        return Icons.cancel_outlined;
      case 'pending':
      default:
        return Icons.pending_outlined;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inMinutes}m ago';
    }
  }
}
