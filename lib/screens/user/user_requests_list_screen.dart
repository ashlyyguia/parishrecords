import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/user_providers.dart';
import '../../widgets/app_loading.dart';

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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'ready':
      case 'completed':
        return Colors.green;
      case 'processing':
      case 'in_progress':
        return Colors.blue;
      case 'cancelled':
      case 'rejected':
        return Colors.red;
      case 'draft':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'ready':
      case 'completed':
        return Icons.check_circle_outline;
      case 'processing':
      case 'in_progress':
        return Icons.sync_outlined;
      case 'cancelled':
      case 'rejected':
        return Icons.cancel_outlined;
      default:
        return Icons.hourglass_empty_outlined;
    }
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
                    final status = (r['status'] ?? '').toString().toLowerCase();
                    return status == _statusFilter;
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
              loading: () => const AppLoading(message: 'Loading requests...'),
              error: (e, _) =>
                  Center(child: Text('Failed to load requests: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (!hasSacraments) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You cannot request a certificate because there are no sacrament records linked to your account.'),
              ),
            );
            return;
          }
          context.go('/records/certificate-request');
        },
        icon: const Icon(Icons.add),
        label: const Text('New Request'),
        backgroundColor: hasSacraments ? colorScheme.primaryContainer : Colors.grey.shade300,
        foregroundColor: hasSacraments ? colorScheme.onPrimaryContainer : Colors.grey.shade700,
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme, bool hasSacraments) {
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
                  if (!hasSacraments) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('You cannot request a certificate because there are no sacrament records linked to your account.'),
                      ),
                    );
                    return;
                  }
                  context.go('/records/certificate-request');
                },
                style: FilledButton.styleFrom(
                  backgroundColor: hasSacraments ? colorScheme.primary : Colors.grey,
                ),
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
    dynamic r,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final id = (r['request_id'] ?? '').toString();
    final type = (r['request_type'] ?? 'certificate').toString();
    final status = (r['status'] ?? 'pending').toString();
    final when = (r['requested_at'] ?? '').toString();

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
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _statusIcon(status),
                      color: _statusColor(status),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type.toUpperCase(),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (when.isNotEmpty)
                          Text(
                            when,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
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
                      color: _statusColor(status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: _statusColor(status),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (id.isNotEmpty) ...[
                const Divider(height: 24),
                Row(
                  children: [
                    Icon(
                      Icons.confirmation_number_outlined,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ID: $id',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => context.go('/user/requests/$id'),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View'),
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
