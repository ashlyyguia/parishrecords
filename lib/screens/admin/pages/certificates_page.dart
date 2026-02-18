import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/requests_repository.dart';
import '../../../providers/requests_provider.dart';

class AdminCertificatesPage extends ConsumerStatefulWidget {
  const AdminCertificatesPage({super.key});

  @override
  ConsumerState<AdminCertificatesPage> createState() =>
      _AdminCertificatesPageState();
}

class _AdminCertificatesPageState extends ConsumerState<AdminCertificatesPage> {
  void _reload() {
    ref.invalidate(certificateRequestsProvider(50));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: ref
            .watch(certificateRequestsProvider(50))
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: colorScheme.error),
                      const SizedBox(height: 8),
                      Text(
                        'Failed to load certificate requests',
                        style: TextStyle(color: colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text('Details: $e', textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (rows) {
                final pending = rows
                    .where((r) => (r['status'] ?? 'pending') == 'pending')
                    .toList();
                final approved = rows
                    .where((r) => (r['status'] ?? '').toString() == 'approved')
                    .toList();
                final rejected = rows
                    .where((r) => (r['status'] ?? '').toString() == 'rejected')
                    .toList();

                return Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.verified,
                                size: 32,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Certificate Management',
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Review and approve certificate requests',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Statistics
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final cols = constraints.maxWidth < 520 ? 1 : 3;
                              return GridView.count(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisCount: cols,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: cols == 1 ? 5.2 : 2.6,
                                children: [
                                  _buildStatCard(
                                    'Pending',
                                    pending.length.toString(),
                                    Colors.orange,
                                    colorScheme,
                                  ),
                                  _buildStatCard(
                                    'Approved',
                                    approved.length.toString(),
                                    Colors.green,
                                    colorScheme,
                                  ),
                                  _buildStatCard(
                                    'Rejected',
                                    rejected.length.toString(),
                                    Colors.red,
                                    colorScheme,
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // Tabs
                    Expanded(
                      child: DefaultTabController(
                        length: 3,
                        child: Column(
                          children: [
                            TabBar(
                              isScrollable: true,
                              labelColor: colorScheme.primary,
                              unselectedLabelColor: colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                              indicatorColor: colorScheme.primary,
                              tabs: [
                                Tab(text: 'Pending (${pending.length})'),
                                Tab(text: 'Approved (${approved.length})'),
                                Tab(text: 'Rejected (${rejected.length})'),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _buildRequestsList(
                                    pending,
                                    'pending',
                                    colorScheme,
                                  ),
                                  _buildRequestsList(
                                    approved,
                                    'approved',
                                    colorScheme,
                                  ),
                                  _buildRequestsList(
                                    rejected,
                                    'rejected',
                                    colorScheme,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    Color color,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsList(
    List<Map<String, dynamic>> requests,
    String status,
    ColorScheme colorScheme,
  ) {
    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getStatusIcon(status),
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No $status certificates',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final request = requests[index];
        return _buildRequestCard(request, status, colorScheme);
      },
    );
  }

  Widget _buildRequestCard(
    Map<String, dynamic> request,
    String status,
    ColorScheme colorScheme,
  ) {
    final requester = (request['requester_name']?.toString() ?? '').trim();
    final type = (request['request_type']?.toString() ?? '').toUpperCase();
    final rawDate = request['requested_at'];
    String dateLabel = 'Unknown';
    if (rawDate is String) {
      final parsed = DateTime.tryParse(rawDate);
      if (parsed != null) dateLabel = _formatDate(parsed);
    } else if (rawDate is DateTime) {
      dateLabel = _formatDate(rawDate);
    }
    final requestId = request['request_id']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _getStatusColor(
                    status,
                  ).withValues(alpha: 0.1),
                  child: Icon(
                    _getStatusIcon(status),
                    color: _getStatusColor(status),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        requester.isEmpty ? 'Certificate Request' : requester,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        [
                          if (type.isNotEmpty) type,
                          if (requestId.isNotEmpty) '#$requestId',
                          dateLabel,
                        ].where((e) => e.isNotEmpty).join(' • '),
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: _getStatusColor(status),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (status == 'pending') ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _updateRequestStatus(request, 'approved'),
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
                          _updateRequestStatus(request, 'rejected'),
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

  Future<void> _updateRequestStatus(
    Map<String, dynamic> request,
    String newStatus,
  ) async {
    final requestId = request['request_id']?.toString();
    if (requestId == null || requestId.isEmpty) return;

    final repo = RequestsRepository();
    await repo.updateStatus(requestId, status: newStatus);
    _reload();
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
