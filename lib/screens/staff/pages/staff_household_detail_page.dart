// ignore_for_file: deprecated_member_use, unnecessary_underscores, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/household.dart';
import '../../../providers/household_provider.dart';
import '../../../widgets/app_loading.dart';

/// Staff/Admin screen for viewing household details and managing members
class StaffHouseholdDetailPage extends ConsumerStatefulWidget {
  final String householdId;

  const StaffHouseholdDetailPage({super.key, required this.householdId});

  @override
  ConsumerState<StaffHouseholdDetailPage> createState() =>
      _StaffHouseholdDetailPageState();
}

class _StaffHouseholdDetailPageState
    extends ConsumerState<StaffHouseholdDetailPage>
    with SingleTickerProviderStateMixin {
  int _selectedTab = 0;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      setState(() => _selectedTab = _tabController.index);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final householdAsync = ref.watch(householdProvider(widget.householdId));
    final membersAsync = ref.watch(
      householdMembersStreamProvider(widget.householdId),
    );
    final statsAsync = ref.watch(householdStatsProvider(widget.householdId));

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: householdAsync.when(
        data: (household) {
          if (household == null) {
            return const Center(child: Text('Household not found'));
          }

          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                expandedHeight: 200,
                floating: true,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    household.familyName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  background: Container(
                    color: colorScheme.primaryContainer,
                    child: Center(
                      child: Icon(
                        Icons.home,
                        size: 64,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Edit Household',
                    onPressed: () =>
                        _showEditHouseholdDialog(context, household),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'Delete Household',
                    color: colorScheme.error,
                    onPressed: () => _confirmDelete(context, household),
                  ),
                ],
              ),
            ],
            body: Column(
              children: [
                // Tab Bar
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabs: const [
                    Tab(icon: Icon(Icons.people), text: 'Members'),
                    Tab(icon: Icon(Icons.church), text: 'Sacraments'),
                    Tab(icon: Icon(Icons.request_page), text: 'Requests'),
                    Tab(
                      icon: Icon(Icons.volunteer_activism),
                      text: 'Donations',
                    ),
                  ],
                ),

                // Tab Content
                Expanded(
                  child: IndexedStack(
                    index: _selectedTab,
                    children: [
                      // Members Tab
                      _MembersTab(
                        household: household,
                        membersAsync: membersAsync,
                        statsAsync: statsAsync,
                      ),
                      // Sacraments Tab
                      _SacramentsTab(
                        household: household,
                        membersAsync: membersAsync,
                      ),
                      // Requests Tab
                      _RequestsTab(householdId: household.id),
                      // Donations Tab
                      _DonationsTab(householdId: household.id),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const AppLoading(message: 'Loading household...'),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text('Error: $e'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    ref.invalidate(householdProvider(widget.householdId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditHouseholdDialog(
    BuildContext context,
    Household household,
  ) async {
    // Navigate to edit or show dialog
    final result = await showDialog<Household>(
      context: context,
      builder: (context) => _HouseholdEditDialog(household: household),
    );

    if (result != null) {
      final notifier = ref.read(householdOperationsProvider.notifier);
      final success = await notifier.updateHousehold(result);

      if (success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Household updated')));
        ref.invalidate(householdProvider(widget.householdId));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, Household household) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Household?'),
        content: Text(
          'This will permanently delete ${household.familyName} (${household.householdId}) and all its members. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final notifier = ref.read(householdOperationsProvider.notifier);
      final success = await notifier.deleteHousehold(household.id);

      if (success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Household deleted')));
        if (mounted) context.pop();
      }
    }
  }
}

/// Members Tab
class _MembersTab extends ConsumerWidget {
  final Household household;
  final AsyncValue<List<HouseholdMember>> membersAsync;
  final AsyncValue<Map<String, dynamic>> statsAsync;

  const _MembersTab({
    required this.household,
    required this.membersAsync,
    required this.statsAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return membersAsync.when(
      data: (members) {
        // Find head of family
        HouseholdMember? headOfFamily;
        try {
          headOfFamily = members.firstWhere(
            (m) => m.id == household.headOfFamilyId,
          );
        } catch (_) {
          headOfFamily = members.isNotEmpty ? members.first : null;
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Quick Stats
            statsAsync.when(
              data: (stats) => _StatsCard(stats: stats),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 16),

            // Head of Family
            if (headOfFamily != null)
              Card(
                color: colorScheme.primaryContainer,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colorScheme.onPrimaryContainer,
                    foregroundColor: colorScheme.primaryContainer,
                    child: Text(headOfFamily.initials),
                  ),
                  title: Text(headOfFamily.fullName),
                  subtitle: const Text('Head of Family'),
                  trailing: const Icon(Icons.star, color: Colors.amber),
                ),
              ),

            const SizedBox(height: 16),

            // Members List Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Family Members (${members.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _showAddMemberDialog(context, ref),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add Member'),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Members List
            if (members.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No members yet. Add your first family member.',
                    ),
                  ),
                ),
              )
            else
              ...members.map(
                (member) => _MemberCard(
                  member: member,
                  isHeadOfFamily: member.id == household.headOfFamilyId,
                  onTap: () => _showMemberDetails(context, ref, member),
                  onEdit: () => _showEditMemberDialog(context, ref, member),
                  onSetAsHead: () =>
                      _setAsHeadOfFamily(context, ref, member.id),
                  onDelete: () => _confirmDeleteMember(context, ref, member),
                ),
              ),
          ],
        );
      },
      loading: () => const AppLoading(message: 'Loading members...'),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text('Error: $e'),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddMemberDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<HouseholdMember>(
      context: context,
      builder: (context) => _MemberFormDialog(householdId: household.id),
    );

    if (result != null) {
      final notifier = ref.read(householdOperationsProvider.notifier);
      final created = await notifier.addMember(result);

      if (created != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${created.fullName} added to household')),
        );
      }
    }
  }

  Future<void> _showEditMemberDialog(
    BuildContext context,
    WidgetRef ref,
    HouseholdMember member,
  ) async {
    final result = await showDialog<HouseholdMember>(
      context: context,
      builder: (context) =>
          _MemberFormDialog(householdId: household.id, member: member),
    );

    if (result != null) {
      final notifier = ref.read(householdOperationsProvider.notifier);
      final success = await notifier.updateMember(result);

      if (success && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Member updated')));
      }
    }
  }

  Future<void> _setAsHeadOfFamily(
    BuildContext context,
    WidgetRef ref,
    String memberId,
  ) async {
    final notifier = ref.read(householdOperationsProvider.notifier);
    final success = await notifier.setHeadOfFamily(household.id, memberId);

    if (success && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Head of family updated')));
    }
  }

  Future<void> _confirmDeleteMember(
    BuildContext context,
    WidgetRef ref,
    HouseholdMember member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member?'),
        content: Text('Remove ${member.fullName} from this household?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final notifier = ref.read(householdOperationsProvider.notifier);
      final success = await notifier.deleteMember(member.id);

      if (success && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${member.fullName} removed')));
      }
    }
  }

  void _showMemberDetails(
    BuildContext context,
    WidgetRef ref,
    HouseholdMember member,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 48,
                      child: Text(
                        member.initials,
                        style: const TextStyle(fontSize: 32),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      member.fullName,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Chip(
                      label: Text(member.role),
                      avatar: const Icon(Icons.badge),
                    ),
                  ),
                  const Divider(height: 32),
                  _DetailRow('Gender', member.gender),
                  _DetailRow('Civil Status', member.civilStatus),
                  if (member.birthDate != null)
                    _DetailRow('Birth Date', _formatDate(member.birthDate!)),
                  if (member.birthPlace?.isNotEmpty == true)
                    _DetailRow('Birth Place', member.birthPlace!),
                  if (member.occupation?.isNotEmpty == true)
                    _DetailRow('Occupation', member.occupation!),
                  if (member.contactNumber?.isNotEmpty == true)
                    _DetailRow('Contact', member.contactNumber!),
                  if (member.email?.isNotEmpty == true)
                    _DetailRow('Email', member.email!),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showEditMemberDialog(context, ref, member);
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () =>
                              _setAsHeadOfFamily(context, ref, member.id),
                          icon: const Icon(Icons.star),
                          label: const Text('Set as Head'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stats Card
class _StatsCard extends StatelessWidget {
  final Map<String, dynamic> stats;

  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _StatItem(
              icon: Icons.people,
              value: stats['totalMembers']?.toString() ?? '0',
              label: 'Members',
              color: Colors.blue,
            ),
            _StatItem(
              icon: Icons.water,
              value: stats['baptized']?.toString() ?? '0',
              label: 'Baptized',
              color: Colors.cyan,
            ),
            _StatItem(
              icon: Icons.church,
              value: stats['confirmed']?.toString() ?? '0',
              label: 'Confirmed',
              color: Colors.purple,
            ),
            _StatItem(
              icon: Icons.favorite,
              value: stats['married']?.toString() ?? '0',
              label: 'Married',
              color: Colors.pink,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Member Card
class _MemberCard extends StatelessWidget {
  final HouseholdMember member;
  final bool isHeadOfFamily;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onSetAsHead;
  final VoidCallback onDelete;

  const _MemberCard({
    required this.member,
    required this.isHeadOfFamily,
    required this.onTap,
    required this.onEdit,
    required this.onSetAsHead,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isHeadOfFamily
              ? Colors.amber
              : colorScheme.primaryContainer,
          foregroundColor: isHeadOfFamily
              ? Colors.black
              : colorScheme.onPrimaryContainer,
          child: Text(member.initials),
        ),
        title: Text(member.fullName),
        subtitle: Text(
          '${member.role}${member.age != null ? ' • ${member.age} years old' : ''}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'view':
                onTap();
              case 'edit':
                onEdit();
              case 'setHead':
                onSetAsHead();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'view', child: Text('View Details')),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (!isHeadOfFamily)
              const PopupMenuItem(
                value: 'setHead',
                child: Text('Set as Head of Family'),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Remove', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

/// Sacraments Tab
class _SacramentsTab extends StatelessWidget {
  final Household household;
  final AsyncValue<List<HouseholdMember>> membersAsync;

  const _SacramentsTab({required this.household, required this.membersAsync});

  @override
  Widget build(BuildContext context) {
    return membersAsync.when(
      data: (members) {
        final membersWithSacraments = members
            .where(
              (m) =>
                  m.baptismRecordId != null ||
                  m.confirmationRecordId != null ||
                  m.marriageRecordId != null,
            )
            .toList();

        if (membersWithSacraments.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.church_outlined,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No sacrament records yet',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    // Navigate to OCR sacrament matching
                    context.go('/staff/households/${household.id}/ocr-match');
                  },
                  icon: const Icon(Icons.document_scanner),
                  label: const Text('Scan Sacrament Book'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: membersWithSacraments.length,
          itemBuilder: (context, index) {
            final member = membersWithSacraments[index];
            return Card(
              child: Column(
                children: [
                  ListTile(
                    leading: CircleAvatar(child: Text(member.initials)),
                    title: Text(member.fullName),
                    subtitle: Text(member.role),
                  ),
                  if (member.baptismRecordId != null)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.water, color: Colors.cyan),
                      title: const Text('Baptized'),
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () {
                          // Navigate to baptism record
                        },
                      ),
                    ),
                  if (member.confirmationRecordId != null)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.church, color: Colors.purple),
                      title: const Text('Confirmed'),
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () {
                          // Navigate to confirmation record
                        },
                      ),
                    ),
                  if (member.marriageRecordId != null)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.favorite, color: Colors.pink),
                      title: const Text('Married'),
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_new),
                        onPressed: () {
                          // Navigate to marriage record
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const AppLoading(message: 'Loading...'),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

/// Requests Tab - Shows certificate requests for this household
class _RequestsTab extends ConsumerWidget {
  final String householdId;

  const _RequestsTab({required this.householdId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Placeholder - will integrate with certificate requests
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.request_page_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Certificate Requests',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'View and track certificate requests from this household',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              // Navigate to create certificate request
              context.go(
                '/records/certificate-request?householdId=$householdId',
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('New Request'),
          ),
        ],
      ),
    );
  }
}

/// Donations Tab - Shows donation history for this household
class _DonationsTab extends ConsumerWidget {
  final String householdId;

  const _DonationsTab({required this.householdId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Placeholder - will integrate with donations
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.volunteer_activism_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Donation History',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Track tithes, offerings, and special donations from this household',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              // Navigate to add donation
            },
            icon: const Icon(Icons.add),
            label: const Text('Record Donation'),
          ),
        ],
      ),
    );
  }
}

/// Household Edit Dialog
class _HouseholdEditDialog extends StatefulWidget {
  final Household household;

  const _HouseholdEditDialog({required this.household});

  @override
  State<_HouseholdEditDialog> createState() => _HouseholdEditDialogState();
}

class _HouseholdEditDialogState extends State<_HouseholdEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _familyNameCtrl = TextEditingController(
    text: widget.household.familyName,
  );
  late final _addressCtrl = TextEditingController(
    text: widget.household.address,
  );
  late final _barangayCtrl = TextEditingController(
    text: widget.household.barangay,
  );
  late final _cityCtrl = TextEditingController(text: widget.household.city);
  late final _contactCtrl = TextEditingController(
    text: widget.household.contactNumber,
  );

  @override
  void dispose() {
    _familyNameCtrl.dispose();
    _addressCtrl.dispose();
    _barangayCtrl.dispose();
    _cityCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Household'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _familyNameCtrl,
                decoration: const InputDecoration(labelText: 'Family Name'),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(labelText: 'Address'),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              TextFormField(
                controller: _barangayCtrl,
                decoration: const InputDecoration(labelText: 'Barangay'),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              TextFormField(
                controller: _cityCtrl,
                decoration: const InputDecoration(labelText: 'City'),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              TextFormField(
                controller: _contactCtrl,
                decoration: const InputDecoration(labelText: 'Contact Number'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final updated = widget.household.copyWith(
      familyName: _familyNameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      barangay: _barangayCtrl.text.trim(),
      city: _cityCtrl.text.trim(),
      contactNumber: _contactCtrl.text.trim(),
      updatedAt: DateTime.now(),
    );

    Navigator.pop(context, updated);
  }
}

/// Member Form Dialog
class _MemberFormDialog extends StatefulWidget {
  final String householdId;
  final HouseholdMember? member;

  const _MemberFormDialog({required this.householdId, this.member});

  @override
  State<_MemberFormDialog> createState() => _MemberFormDialogState();
}

class _MemberFormDialogState extends State<_MemberFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _suffixCtrl = TextEditingController();
  final _birthPlaceCtrl = TextEditingController();
  final _occupationCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  String _role = 'Child';
  String _gender = 'Male';
  String _civilStatus = 'Single';
  DateTime? _birthDate;

  @override
  void initState() {
    super.initState();
    if (widget.member != null) {
      _firstNameCtrl.text = widget.member!.firstName;
      _middleNameCtrl.text = widget.member!.middleName;
      _lastNameCtrl.text = widget.member!.lastName;
      _suffixCtrl.text = widget.member!.suffix ?? '';
      _birthPlaceCtrl.text = widget.member!.birthPlace ?? '';
      _occupationCtrl.text = widget.member!.occupation ?? '';
      _contactCtrl.text = widget.member!.contactNumber ?? '';
      _emailCtrl.text = widget.member!.email ?? '';
      _role = widget.member!.role;
      _gender = widget.member!.gender;
      _civilStatus = widget.member!.civilStatus;
      _birthDate = widget.member!.birthDate;
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _suffixCtrl.dispose();
    _birthPlaceCtrl.dispose();
    _occupationCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.member != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Member' : 'Add Family Member'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _firstNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'First Name *',
                      ),
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _suffixCtrl,
                      decoration: const InputDecoration(labelText: 'Suffix'),
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: _middleNameCtrl,
                decoration: const InputDecoration(labelText: 'Middle Name'),
              ),
              TextFormField(
                controller: _lastNameCtrl,
                decoration: const InputDecoration(labelText: 'Last Name *'),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              // Role Dropdown
              DropdownButtonFormField<String>(
                value: _role,
                decoration: const InputDecoration(labelText: 'Role in Family'),
                items: FamilyRoles.all
                    .map(
                      (role) =>
                          DropdownMenuItem(value: role, child: Text(role)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _role = v!),
              ),

              // Gender Dropdown
              DropdownButtonFormField<String>(
                value: _gender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: Genders.all
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) => setState(() => _gender = v!),
              ),

              // Civil Status
              DropdownButtonFormField<String>(
                value: _civilStatus,
                decoration: const InputDecoration(labelText: 'Civil Status'),
                items: CivilStatuses.all
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _civilStatus = v!),
              ),

              const SizedBox(height: 16),

              // Birth Date
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Birth Date'),
                subtitle: Text(
                  _birthDate != null
                      ? '${_birthDate!.month}/${_birthDate!.day}/${_birthDate!.year}'
                      : 'Not set',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: _pickBirthDate,
                ),
              ),

              TextFormField(
                controller: _birthPlaceCtrl,
                decoration: const InputDecoration(labelText: 'Birth Place'),
              ),
              TextFormField(
                controller: _occupationCtrl,
                decoration: const InputDecoration(labelText: 'Occupation'),
              ),
              TextFormField(
                controller: _contactCtrl,
                decoration: const InputDecoration(labelText: 'Contact Number'),
                keyboardType: TextInputType.phone,
              ),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEditing ? 'Save Changes' : 'Add Member'),
        ),
      ],
    );
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final fullName = HouseholdMember.generateFullName(
      _firstNameCtrl.text.trim(),
      _middleNameCtrl.text.trim(),
      _lastNameCtrl.text.trim(),
      _suffixCtrl.text.trim().isEmpty ? null : _suffixCtrl.text.trim(),
    );

    final member = widget.member != null
        ? widget.member!.copyWith(
            firstName: _firstNameCtrl.text.trim(),
            middleName: _middleNameCtrl.text.trim(),
            lastName: _lastNameCtrl.text.trim(),
            suffix: _suffixCtrl.text.trim().isEmpty
                ? null
                : _suffixCtrl.text.trim(),
            fullName: fullName,
            role: _role,
            gender: _gender,
            civilStatus: _civilStatus,
            birthDate: _birthDate,
            birthPlace: _birthPlaceCtrl.text.trim().isEmpty
                ? null
                : _birthPlaceCtrl.text.trim(),
            occupation: _occupationCtrl.text.trim().isEmpty
                ? null
                : _occupationCtrl.text.trim(),
            contactNumber: _contactCtrl.text.trim().isEmpty
                ? null
                : _contactCtrl.text.trim(),
            email: _emailCtrl.text.trim().isEmpty
                ? null
                : _emailCtrl.text.trim(),
            updatedAt: DateTime.now(),
          )
        : HouseholdMember(
            id: '',
            householdId: widget.householdId,
            firstName: _firstNameCtrl.text.trim(),
            middleName: _middleNameCtrl.text.trim(),
            lastName: _lastNameCtrl.text.trim(),
            suffix: _suffixCtrl.text.trim().isEmpty
                ? null
                : _suffixCtrl.text.trim(),
            fullName: fullName,
            role: _role,
            gender: _gender,
            civilStatus: _civilStatus,
            birthDate: _birthDate,
            birthPlace: _birthPlaceCtrl.text.trim().isEmpty
                ? null
                : _birthPlaceCtrl.text.trim(),
            occupation: _occupationCtrl.text.trim().isEmpty
                ? null
                : _occupationCtrl.text.trim(),
            contactNumber: _contactCtrl.text.trim().isEmpty
                ? null
                : _contactCtrl.text.trim(),
            email: _emailCtrl.text.trim().isEmpty
                ? null
                : _emailCtrl.text.trim(),
          );

    Navigator.pop(context, member);
  }
}
