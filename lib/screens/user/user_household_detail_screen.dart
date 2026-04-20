// ignore_for_file: unnecessary_underscores, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../models/household.dart';
import '../../../providers/household_provider.dart';

/// User Household Details Screen - displays complete household information
class UserHouseholdDetailScreen extends ConsumerStatefulWidget {
  final String householdId;

  const UserHouseholdDetailScreen({super.key, required this.householdId});

  @override
  ConsumerState<UserHouseholdDetailScreen> createState() =>
      _UserHouseholdDetailScreenState();
}

class _UserHouseholdDetailScreenState
    extends ConsumerState<UserHouseholdDetailScreen> {
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final householdAsync = ref.watch(householdProvider(widget.householdId));
    final membersAsync = ref.watch(
      householdMembersStreamProvider(widget.householdId),
    );

    return DefaultTabController(
      length: 3,
      initialIndex: _currentTab,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        floatingActionButton: _currentTab == 0
            ? FloatingActionButton.extended(
                onPressed: () => context.push(
                  '/user/households/${widget.householdId}/members/new',
                ),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add Member'),
              )
            : null,
        body: householdAsync.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(
            appBar: AppBar(
              title: const Text('Household Details'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            body: Center(child: Text('Error: $e')),
          ),
          data: (household) {
            if (household == null) {
              return Scaffold(
                appBar: AppBar(
                  title: const Text('Household Details'),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                  ),
                ),
                body: const Center(child: Text('Household not found')),
              );
            }

            return NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverAppBar(
                    pinned: true,
                    floating: true,
                    snap: true,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.pop(),
                    ),
                    title: Text(household.familyName),
                    actions: [
                      IconButton(
                        onPressed: () => context.push(
                          '/user/households/${widget.householdId}/edit',
                        ),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'archive') {
                            _archiveHousehold(household);
                          } else if (value == 'delete') {
                            _showDeleteDialog();
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'archive',
                            child: ListTile(
                              leading: Icon(
                                household.isArchived
                                    ? Icons.unarchive_outlined
                                    : Icons.archive_outlined,
                              ),
                              title: Text(
                                household.isArchived ? 'Unarchive' : 'Archive',
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              title: Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ],
                    bottom: TabBar(
                      onTap: (index) => setState(() => _currentTab = index),
                      tabs: const [
                        Tab(icon: Icon(Icons.people_outlined), text: 'Members'),
                        Tab(
                          icon: Icon(Icons.church_outlined),
                          text: 'Sacraments',
                        ),
                        Tab(
                          icon: Icon(Icons.assignment_outlined),
                          text: 'Requests',
                        ),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: _buildHouseholdSummaryCard(
                        theme,
                        colorScheme,
                        household,
                        membersAsync,
                      ),
                    ),
                  ),
                ];
              },
              body: TabBarView(
                children: [
                  _buildMembersTab(theme, colorScheme, membersAsync),
                  _buildSacramentsTab(theme, colorScheme),
                  _buildRequestsTab(theme, colorScheme),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHouseholdSummaryCard(
    ThemeData theme,
    ColorScheme colorScheme,
    Household household,
    AsyncValue<List<HouseholdMember>> membersAsync,
  ) {
    final statusText = household.isArchived ? 'Archived' : 'Active';
    final statusColor = household.isArchived ? Colors.grey : Colors.green;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.home_outlined,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        household.familyName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${household.address}, ${household.barangay}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusText,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _InfoRow(
                  icon: Icons.person_outline,
                  label: 'Head',
                  value: household.headOfFamilyId,
                ),
                _InfoRow(
                  icon: Icons.phone_outlined,
                  label: 'Contact',
                  value: household.contactNumber.isNotEmpty
                      ? household.contactNumber
                      : 'Not provided',
                ),
                _InfoRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: household.email.isNotEmpty
                      ? household.email
                      : 'Not provided',
                ),
                membersAsync.when(
                  loading: () => _InfoRow(
                    icon: Icons.people_outline,
                    label: 'Members',
                    value: 'Loading...',
                  ),
                  error: (_, __) => _InfoRow(
                    icon: Icons.people_outline,
                    label: 'Members',
                    value: '—',
                  ),
                  data: (rows) => _InfoRow(
                    icon: Icons.people_outline,
                    label: 'Members',
                    value: '${rows.length}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersTab(
    ThemeData theme,
    ColorScheme colorScheme,
    AsyncValue<List<HouseholdMember>> membersAsync,
  ) {
    return membersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (members) {
        if (members.isEmpty) {
          return _buildEmptyTab(
            icon: Icons.people_outline,
            title: 'No Members Yet',
            subtitle: 'Add family members to your household',
            actionLabel: 'Add Member',
            onAction: () => context.push(
              '/user/households/${widget.householdId}/members/new',
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          itemCount: members.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final m = members[index];
            return _MemberTile(
              member: m,
              onTap: () => context.push(
                '/user/households/${widget.householdId}/members/${m.id}',
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSacramentsTab(ThemeData theme, ColorScheme colorScheme) {
    return _buildEmptyTab(
      icon: Icons.church_outlined,
      title: 'Sacrament Records',
      subtitle: 'No sacrament records linked yet',
      actionLabel: 'Link Sacrament',
      onAction: () =>
          context.push('/user/households/${widget.householdId}/ocr-link'),
    );
  }

  Widget _buildRequestsTab(ThemeData theme, ColorScheme colorScheme) {
    return _buildEmptyTab(
      icon: Icons.assignment_outlined,
      title: 'No Requests',
      subtitle: 'You haven\'t submitted any requests yet',
      actionLabel: 'New Request',
      onAction: () => context.go('/user/requests'),
    );
  }

  Widget _buildEmptyTab({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 80,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _archiveHousehold(Household household) async {
    try {
      final updated = household.copyWith(
        isArchived: !household.isArchived,
        updatedAt: DateTime.now(),
      );
      await ref.read(householdRepositoryProvider).updateHousehold(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              updated.isArchived
                  ? 'Household archived'
                  : 'Household unarchived',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Household'),
        content: const Text(
          'Are you sure you want to delete this household? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref
                    .read(householdRepositoryProvider)
                    .deleteHousehold(widget.householdId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Household deleted')),
                  );
                  context.pop();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Info Row Widget
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  final HouseholdMember member;
  final VoidCallback onTap;

  const _MemberTile({required this.member, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final initials = member.fullName.isNotEmpty
        ? member.fullName.trim().split(RegExp(r'\s+')).take(2).map((p) {
            if (p.isEmpty) return '';
            return p[0].toUpperCase();
          }).join()
        : '?';

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    initials,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.fullName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${member.role} • ${member.gender} • ${member.civilStatus}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Member Card Widget
// ignore: unused_element
class _MemberCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final VoidCallback onTap;

  const _MemberCard({required this.member, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    (member['name'] as String).isNotEmpty
                        ? (member['name'] as String)[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member['name'],
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        _Chip(label: member['role']),
                        if (member['birthDate'].isNotEmpty)
                          _Chip(
                            label: _formatDate(member['birthDate']),
                            color: Colors.blue,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return '${date.month}/${date.day}/${date.year}';
    } catch (e) {
      return isoDate;
    }
  }
}

/// Chip Widget
class _Chip extends StatelessWidget {
  final String label;
  final Color? color;

  const _Chip({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = color ?? Colors.purple;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: scheme,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
