// ignore_for_file: unnecessary_underscores, deprecated_member_use

import 'package:flutter/material.dart';
import '../../../services/requests_repository.dart';
import '../admin_design_system.dart';

class AdminRequestsCenterPage extends StatefulWidget {
  const AdminRequestsCenterPage({super.key});

  @override
  State<AdminRequestsCenterPage> createState() =>
      _AdminRequestsCenterPageState();
}

class _AdminRequestsCenterPageState extends State<AdminRequestsCenterPage> {
  final RequestsRepository _repo = RequestsRepository();
  final TextEditingController _searchCtrl = TextEditingController();

  Future<List<Map<String, dynamic>>>? _requestsFuture;
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  void _loadRequests() {
    setState(() {
      _requestsFuture = _repo.list(limit: 100);
    });
  }

  Future<void> _updateStatus(String requestId, String newStatus) async {
    try {
      await _repo.updateStatus(requestId, status: newStatus);
      if (!mounted) return;
      final snackMessage = newStatus == 'approved'
          ? 'Request approved. The parishioner was notified they can receive their certificate in about 5 minutes.'
          : newStatus == 'rejected'
          ? 'Request rejected. The parishioner was notified.'
          : 'Request marked as $newStatus';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(snackMessage)));
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _deleteRequest(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Request'),
        content: const Text(
          'Are you sure you want to delete this request? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _repo.delete(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Request deleted')));
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete request: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'completed':
        return Colors.green;
      case 'rejected':
      case 'cancelled':
        return Colors.red;
      case 'pending':
      case 'in_progress':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'completed':
        return Icons.check_circle;
      case 'rejected':
      case 'cancelled':
        return Icons.cancel;
      case 'pending':
        return Icons.pending;
      case 'in_progress':
        return Icons.sync;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: AdminDesignSystem.pageBackground(context),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminDesignSystem.pageHeader(
                context,
                title: 'Requests & Approvals',
                subtitle: 'Manage certificate and document requests',
                icon: Icons.assignment_outlined,
              ),
              const SizedBox(height: 20),

              // Search and Filter Bar
              Container(
                decoration: AdminDesignSystem.cardDecoration(context),
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 720;
                    return Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        // Search Field
                        SizedBox(
                          width: isNarrow ? constraints.maxWidth : 340,
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: 'Search requests...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: colorScheme.surfaceContainerHighest
                                  .withOpacity(0.5),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),

                        // Status Filter
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildFilterTab('All', 'all'),
                                _buildFilterTab('Pending', 'pending'),
                                _buildFilterTab('Approved', 'approved'),
                                _buildFilterTab('Rejected', 'rejected'),
                              ],
                            ),
                          ),
                        ),

                        // Refresh Button
                        FilledButton.icon(
                          onPressed: _loadRequests,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // Requests List
              Expanded(
                child: Container(
                  decoration: AdminDesignSystem.cardDecoration(context),
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _requestsFuture,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: colorScheme.error,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Failed to load requests',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${snap.error}',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.error,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: _loadRequests,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      var requests = snap.data ?? [];

                      // Apply status filter
                      if (_filterStatus != 'all') {
                        requests = requests
                            .where(
                              (r) =>
                                  (r['status']?.toString().toLowerCase() ??
                                      'pending') ==
                                  _filterStatus,
                            )
                            .toList();
                      }

                      // Apply search filter
                      final searchQuery = _searchCtrl.text.trim().toLowerCase();
                      if (searchQuery.isNotEmpty) {
                        requests = requests
                            .where(
                              (r) => r.values.any(
                                (v) => v.toString().toLowerCase().contains(
                                  searchQuery,
                                ),
                              ),
                            )
                            .toList();
                      }

                      if (requests.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 64,
                                color: colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No requests found',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.outline,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Requests will appear here when submitted',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: requests.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final request = requests[index];
                          return _buildRequestCard(context, request);
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterTab(String label, String value) {
    final isSelected = _filterStatus == value;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => setState(() => _filterStatus = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildRequestCard(BuildContext context, Map<String, dynamic> request) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final requestId = request['request_id']?.toString() ?? '';
    final requestType = request['request_type']?.toString() ?? 'Unknown';
    final typeLabel = RequestsRepository.certificateTypeLabel(requestType);
    final personName = RequestsRepository.personOnCertificate(request);
    final submittedBy = RequestsRepository.submittedByName(request);
    final status = request['status']?.toString() ?? 'pending';
    final requestedAt = request['requested_at']?.toString() ?? '';
    final recordId = request['record_id']?.toString();
    final parishId = request['parish_id']?.toString();

    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(statusIcon, color: statusColor, size: 24),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '$typeLabel certificate',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                status.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (personName.isNotEmpty)
              Text(
                'Person on certificate: $personName',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            if (submittedBy.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Requested by: $submittedBy',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else if (personName.isEmpty)
              Text(
                'Requested by: Unknown',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            if (recordId != null)
              Text(
                'Record ID: $recordId',
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
            if (parishId != null)
              Text(
                'Parish ID: $parishId',
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
            if (requestedAt.isNotEmpty)
              Text(
                'Requested: ${_formatDateTime(requestedAt)}',
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
          ],
        ),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status.toLowerCase() == 'pending') ...[
                IconButton(
                  tooltip: 'Approve',
                  onPressed: () => _updateStatus(requestId, 'approved'),
                  icon: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  tooltip: 'Reject',
                  onPressed: () => _updateStatus(requestId, 'rejected'),
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
              IconButton(
                tooltip: 'Delete',
                onPressed: requestId.isEmpty
                    ? null
                    : () => _deleteRequest(requestId),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inDays > 365) {
        return '${(diff.inDays / 365).floor()} years ago';
      } else if (diff.inDays > 30) {
        return '${(diff.inDays / 30).floor()} months ago';
      } else if (diff.inDays > 7) {
        return '${(diff.inDays / 7).floor()} weeks ago';
      } else if (diff.inDays > 0) {
        return '${diff.inDays} days ago';
      } else if (diff.inHours > 0) {
        return '${diff.inHours} hours ago';
      } else if (diff.inMinutes > 0) {
        return '${diff.inMinutes} minutes ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return isoString;
    }
  }
}
