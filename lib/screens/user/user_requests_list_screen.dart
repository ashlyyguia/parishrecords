import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/user_providers.dart';
import '../../services/requests_repository.dart';
import '../../services/user_requests_repository.dart';

class UserRequestsListScreen extends ConsumerStatefulWidget {
  const UserRequestsListScreen({super.key});

  @override
  ConsumerState<UserRequestsListScreen> createState() =>
      _UserRequestsListScreenState();
}

class _UserRequestsListScreenState
    extends ConsumerState<UserRequestsListScreen> {
  final _searchCtrl = TextEditingController();
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(myRequestsProvider);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final async = ref.watch(myRequestsProvider);
    final sacramentsAsync = ref.watch(mySacramentsProvider);
    final hasSacraments = sacramentsAsync.maybeWhen(
      data: (rows) => rows.isNotEmpty,
      orElse: () => false,
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('My Requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(myRequestsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filter Bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Search
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by type or ID...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear),
                          )
                        : null,
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                // Status Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        isSelected: _statusFilter == null,
                        onTap: () => setState(() => _statusFilter = null),
                      ),
                      _FilterChip(
                        label: 'Pending',
                        isSelected: _statusFilter == 'pending',
                        onTap: () => setState(() => _statusFilter = 'pending'),
                      ),
                      _FilterChip(
                        label: 'Processing',
                        isSelected: _statusFilter == 'processing',
                        onTap: () =>
                            setState(() => _statusFilter = 'processing'),
                      ),
                      _FilterChip(
                        label: 'Completed',
                        isSelected: _statusFilter == 'completed',
                        onTap: () =>
                            setState(() => _statusFilter = 'completed'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // List
          Expanded(
            child: async.when(
              data: (rows) {
                // Apply filters
                var filtered = rows;
                if (_searchCtrl.text.isNotEmpty) {
                  final query = _searchCtrl.text.toLowerCase();
                  filtered = filtered.where((r) {
                    final type = (r['request_type'] ?? '')
                        .toString()
                        .toLowerCase();
                    final id = (r['request_id'] ?? '').toString().toLowerCase();
                    return type.contains(query) || id.contains(query);
                  }).toList();
                }
                if (_statusFilter != null) {
                  filtered = filtered.where((r) {
                    final status = (r['status'] ?? 'pending').toString();
                    return UserRequestsRepository.filterBucket(status) ==
                        _statusFilter;
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return _buildEmptyState(theme, colorScheme, hasSacraments);
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(myRequestsProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) =>
                        _buildRequestCard(filtered[i], theme, colorScheme),
                  ),
                );
              },
              loading: () => _buildSkeletonList(colorScheme),
              error: (e, _) =>
                  Center(child: Text('Failed to load requests: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.go('/records/certificate-request?user=1');
        },
        icon: const Icon(Icons.add),
        label: const Text('New Request'),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
    );
  }

  Widget _buildSkeletonList(ColorScheme colorScheme) {
    final shimmer = colorScheme.onSurface.withValues(alpha: 0.08);
    final shimmerDark = colorScheme.onSurface.withValues(alpha: 0.12);
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: 5,
      separatorBuilder: (_, _a) => const SizedBox(height: 8),
      itemBuilder: (_, _b) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: shimmer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: shimmerDark,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: shimmerDark,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 100,
                    height: 11,
                    decoration: BoxDecoration(
                      color: shimmer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 72,
              height: 28,
              decoration: BoxDecoration(
                color: shimmerDark,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    ThemeData theme,
    ColorScheme colorScheme,
    bool hasSacraments,
  ) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 64,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No requests yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Submit a new certificate request to get started.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  context.go('/records/certificate-request?user=1');
                },
                icon: const Icon(Icons.add),
                label: const Text('New Request'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestCard(
    Map<String, dynamic> r,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final id = (r['request_id'] ?? r['id'] ?? '').toString();
    final type = (r['request_type'] ?? 'certificate').toString();
    final when = (r['requested_at_display'] ??
            r['requested_at'] ??
            r['created_at'] ??
            '')
        .toString();
    final personName = (r['certificate_for_name'] ??
            r['requester_name'] ??
            r['requesterName'] ??
            r['name'] ??
            '')
        .toString();
    final submittedBy = (r['submitted_by_name'] ?? '').toString();
    final status = (r['status'] ?? 'pending').toString();
    final statusLabel = UserRequestsRepository.statusLabel(status);
    final statusHint = _statusHintMessage(r, status);

    Color statusColor() {
      switch (UserRequestsRepository.filterBucket(status)) {
        case 'pending':
          return Colors.orange;
        case 'processing':
          return Colors.blue;
        case 'completed':
          return status.toLowerCase() == 'rejected'
              ? Colors.red
              : Colors.green;
        default:
          return colorScheme.primary;
      }
    }

    IconData typeIcon() {
      switch (type.toLowerCase()) {
        case 'baptism':
          return Icons.water_drop_outlined;
        case 'confirmation':
          return Icons.verified_outlined;
        default:
          return Icons.assignment_outlined;
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: id.isEmpty ? null : () => context.go('/user/requests/$id'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.6,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      typeIcon(),
                      color: colorScheme.onPrimaryContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          personName.isNotEmpty ? personName : 'Request',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          type.toUpperCase(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (submittedBy.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Requested by: $submittedBy',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (when.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            when,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor().withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: statusColor().withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor(),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (statusHint != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statusColor().withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: statusColor().withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        status.toLowerCase() == 'rejected'
                            ? Icons.info_outline
                            : Icons.check_circle_outline,
                        size: 18,
                        color: statusColor(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          statusHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? _statusHintMessage(Map<String, dynamic> r, String status) {
    final s = status.trim().toLowerCase();
    if (s == 'pending') {
      return 'Your request is being reviewed. You will be notified when it is approved or if more information is needed.';
    }
    if (s != 'approved' && s != 'rejected' && s != 'ready' && s != 'completed') {
      return null;
    }
    final typeLabel = RequestsRepository.certificateTypeLabel(
      (r['request_type'] ?? 'certificate').toString(),
    );
    final name = (r['requester_name'] ?? '').toString();
    return RequestsRepository.notificationForStatus(
      status: s,
      typeLabel: typeLabel,
      requesterName: name,
    ).body;
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
