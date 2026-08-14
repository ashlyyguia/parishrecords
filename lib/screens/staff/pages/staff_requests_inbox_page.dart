import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../providers/requests_provider.dart';
import '../../../services/requests_repository.dart';
import '../../../services/audit_service.dart';
import '../../../widgets/app_search_bar.dart';
import '../../../widgets/page_header.dart';

class StaffRequestsInboxPage extends ConsumerStatefulWidget {
  const StaffRequestsInboxPage({super.key});

  @override
  ConsumerState<StaffRequestsInboxPage> createState() =>
      _StaffRequestsInboxPageState();
}

class _StaffRequestsInboxPageState
    extends ConsumerState<StaffRequestsInboxPage> {
  final _searchCtrl = TextEditingController();
  String _selectedFilter = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    ref.invalidate(certificateRequestsProvider(100));
  }

  Future<void> _setStatus(Map<String, dynamic> row, String status) async {
    final id = (row['request_id'] ?? '').toString();
    if (id.isEmpty) return;

    final repo = RequestsRepository();
    await repo.updateStatus(id, status: status, notificationSent: true);

    final requester = RequestsRepository.personOnCertificate(row);
    final type = (row['request_type'] ?? '').toString();

    try {
      await AuditService.log(
        action: 'request_status_change',
        userId: 'staff',
        details: 'Request $id ($type / $requester) updated to $status',
      );
    } catch (_) {}

    _reload();

    if (!mounted) return;
    final snackMessage = status == 'approved'
        ? 'Approved. User notified: certificate ready for pickup in ~5 minutes.'
        : 'Request updated: ${status.toUpperCase()}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(snackMessage),
        backgroundColor: status == 'approved' ? Colors.green : Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _viewRequestDetails(BuildContext context, Map<String, dynamic> request) {
    final type = request['request_type']?.toString() ?? 'Certificate';
    final typeLabel = RequestsRepository.certificateTypeLabel(type);
    final personName = RequestsRepository.personOnCertificate(request);
    final submittedBy = RequestsRepository.submittedByName(request);
    final status = request['status']?.toString() ?? 'pending';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$typeLabel certificate request'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (personName.isNotEmpty)
                Text(
                  'Person on certificate: $personName',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              if (submittedBy.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Requested by: $submittedBy'),
              ],
              const SizedBox(height: 8),
              Text('Status: ${status.toUpperCase()}'),
              const SizedBox(height: 8),
              if (request['purpose'] != null)
                Text('Purpose: ${request['purpose']}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildHeader(colorScheme, theme, isMobile),
              const SizedBox(height: 16),
              _buildFilterChips(colorScheme, theme),
              const SizedBox(height: 16),
              _buildSearchBar(colorScheme, theme),
              const SizedBox(height: 16),
            ]),
          ),
        ),
        _buildRequestsSliver(colorScheme, theme, isMobile),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildHeader(ColorScheme colorScheme, ThemeData theme, bool isMobile) {
    return PageHeader(
      icon: Icons.description_outlined,
      title: 'Certificate Requests',
      subtitle: 'Review and process certificate requests from parishioners',
      actions: [_buildRefreshButton(colorScheme, isMobile)],
    );
  }

  Widget _buildRefreshButton(ColorScheme colorScheme, bool isMobile) {
    return OutlinedButton.icon(
      onPressed: _reload,
      icon: Icon(Icons.refresh, size: isMobile ? 16 : 18),
      label: Text(isMobile ? 'Refresh' : 'Refresh'),
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        side: BorderSide(color: colorScheme.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: isMobile
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildFilterChips(ColorScheme colorScheme, ThemeData theme) {
    final filters = [
      ('all', 'All Requests'),
      ('pending', 'Pending'),
      ('approved', 'Approved'),
      ('rejected', 'Rejected'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          final isSelected = _selectedFilter == filter.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              label: Text(filter.$2),
              onSelected: (_) => setState(() => _selectedFilter = filter.$1),
              selectedColor: colorScheme.primaryContainer,
              checkmarkColor: colorScheme.primary,
              labelStyle: TextStyle(
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme colorScheme, ThemeData theme) {
    return AppSearchBar(
      controller: _searchCtrl,
      hintText: 'Search by name, type, or status...',
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildRequestsSliver(
    ColorScheme colorScheme,
    ThemeData theme,
    bool isMobile,
  ) {
    return ref
        .watch(certificateRequestsProvider(100))
        .when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => SliverFillRemaining(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: colorScheme.error,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load requests',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      e.toString(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          data: (rows) {
            final query = _searchCtrl.text.trim().toLowerCase();
            var filtered = query.isEmpty
                ? rows
                : rows.where((r) {
                    final person = RequestsRepository.personOnCertificate(r);
                    final submitted = RequestsRepository.submittedByName(r);
                    final type = (r['request_type'] ?? '').toString();
                    final status = (r['status'] ?? '').toString();
                    return person.toLowerCase().contains(query) ||
                        submitted.toLowerCase().contains(query) ||
                        type.toLowerCase().contains(query) ||
                        status.toLowerCase().contains(query);
                  }).toList();

            if (_selectedFilter != 'all') {
              filtered = filtered
                  .where(
                    (r) => (r['status'] ?? '').toString() == _selectedFilter,
                  )
                  .toList();
            }

            if (filtered.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No requests found',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        if (query.isNotEmpty)
                          Text(
                            'Try adjusting your search',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 16.0 : 24.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  final r = filtered[i];
                  final personName =
                      RequestsRepository.personOnCertificate(r);
                  final submittedBy = RequestsRepository.submittedByName(r);
                  final type = (r['request_type'] ?? 'certificate').toString();
                  final status = (r['status'] ?? 'pending').toString();
                  final createdAt = (r['created_at'] ?? '').toString();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RequestCard(
                      personName: personName.isNotEmpty
                          ? personName
                          : 'Unknown',
                      submittedByName: submittedBy,
                      type: type,
                      status: status,
                      createdAt: createdAt,
                      onTap: () => _viewRequestDetails(context, r),
                      onApprove: status == 'pending'
                          ? () => _setStatus(r, 'approved')
                          : null,
                      onReject: status == 'pending'
                          ? () => _setStatus(r, 'rejected')
                          : null,
                      colorScheme: colorScheme,
                      theme: theme,
                    ),
                  );
                }, childCount: filtered.length),
              ),
            );
          },
        );
  }
}

class _RequestCard extends StatelessWidget {
  final String personName;
  final String submittedByName;
  final String type;
  final String status;
  final String createdAt;
  final VoidCallback onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _RequestCard({
    required this.personName,
    required this.submittedByName,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.onTap,
    this.onApprove,
    this.onReject,
    required this.colorScheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);

    return Card(
      elevation: 2,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          RequestsRepository.certificateTypeLabel(type),
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Person: $personName',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.75),
                          ),
                        ),
                        if (submittedByName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Requested by: $submittedByName',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.75,
                              ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          status.toUpperCase(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (createdAt.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Submitted: $createdAt',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
              if (status == 'pending' &&
                  (onApprove != null || onReject != null)) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (onApprove != null)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onApprove,
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 18,
                          ),
                          label: const Text('Approve'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    if (onApprove != null && onReject != null)
                      const SizedBox(width: 12),
                    if (onReject != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onReject,
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text('Reject'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
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
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.pending_outlined;
      case 'approved':
        return Icons.check_circle_outline;
      case 'rejected':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }
}
