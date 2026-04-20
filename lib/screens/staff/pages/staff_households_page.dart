// ignore_for_file: unnecessary_underscores, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/household.dart';
import '../../../providers/household_provider.dart';
import '../../../widgets/app_loading.dart';

/// Enhanced Staff/Admin screen for managing households with modern UI
class StaffHouseholdsPage extends ConsumerStatefulWidget {
  const StaffHouseholdsPage({super.key});

  @override
  ConsumerState<StaffHouseholdsPage> createState() =>
      _StaffHouseholdsPageState();
}

class _StaffHouseholdsPageState extends ConsumerState<StaffHouseholdsPage> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String? _selectedBarangay;
  bool _includeArchived = false;
  int _currentPage = 0;
  final int _itemsPerPage = 10;
  bool _isTableView = true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final filter = HouseholdFilter(
      barangay: _selectedBarangay,
      includeArchived: _includeArchived,
      searchQuery: _searchCtrl.text.isEmpty ? null : _searchCtrl.text,
    );

    final householdsAsync = ref.watch(householdsStreamProvider(filter));
    final barangaysAsync = ref.watch(barangaysProvider);

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: householdsAsync.when(
        data: (allHouseholds) {
          // Pagination logic
          final totalItems = allHouseholds.length;
          final totalPages = (totalItems / _itemsPerPage).ceil();
          final startIndex = _currentPage * _itemsPerPage;
          final endIndex = (startIndex + _itemsPerPage).clamp(0, totalItems);
          final households = allHouseholds.sublist(
            startIndex,
            endIndex.clamp(0, totalItems),
          );

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Navigation Bar
                _buildNavigationBar(colorScheme),

                // Search & Filter Bar
                _buildSearchAndFilterBar(colorScheme, barangaysAsync),

                // Active Filters
                _buildActiveFilters(colorScheme),

                // Stats Row
                _buildStatsRow(colorScheme, totalItems),

                // Households Content
                households.isEmpty
                    ? _buildEmptyState(colorScheme)
                    : _isTableView
                    ? _buildTableView(colorScheme, households)
                    : _buildListView(colorScheme, households),

                // Pagination
                if (totalPages > 1)
                  _buildPagination(colorScheme, totalPages, totalItems),
              ],
            ),
          );
        },
        loading: () =>
            const Center(child: AppLoading(message: 'Loading households...')),
        error: (e, _) => _buildErrorState(colorScheme, e),
      ),
    );
  }

  // ==================== NAVIGATION BAR ====================
  Widget _buildNavigationBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.home_work_rounded,
                color: colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              'Household Management',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 32),
            _NavLink(
              label: 'Dashboard',
              icon: Icons.dashboard_outlined,
              onTap: () => context.go('/staff/dashboard'),
            ),
            _NavLink(
              label: 'Households',
              icon: Icons.home_work_outlined,
              isActive: true,
              onTap: () {},
            ),
            _NavLink(
              label: 'Sacraments',
              icon: Icons.church_outlined,
              onTap: () => context.go('/staff/records'),
            ),
            _NavLink(
              label: 'Requests',
              icon: Icons.assignment_outlined,
              onTap: () => context.go('/staff/requests'),
            ),
            _NavLink(
              label: 'Reports',
              icon: Icons.assessment_outlined,
              onTap: () => context.go('/staff/reports'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== SEARCH & FILTER BAR ====================
  Widget _buildSearchAndFilterBar(
    ColorScheme colorScheme,
    AsyncValue<List<String>> barangaysAsync,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 720;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Search Bar
              SizedBox(
                width: isNarrow ? constraints.maxWidth : 400,
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      hintText: 'Search by household name or member name...',
                      prefixIcon: Icon(
                        Icons.search,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              // Barangay Filter
              SizedBox(
                width: isNarrow ? constraints.maxWidth : 220,
                child: barangaysAsync.when(
                  data: (barangays) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: _selectedBarangay,
                        hint: Text(
                          'All Barangays',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All Barangays'),
                          ),
                          ...barangays.map(
                            (b) => DropdownMenuItem(value: b, child: Text(b)),
                          ),
                        ],
                        onChanged: (v) => setState(() => _selectedBarangay = v),
                      ),
                    ),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
              // View Toggle
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Table'),
                    icon: Icon(Icons.table_rows),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('List'),
                    icon: Icon(Icons.view_list),
                  ),
                ],
                selected: {_isTableView},
                onSelectionChanged: (v) =>
                    setState(() => _isTableView = v.first),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==================== STATS ROW ====================
  Widget _buildStatsRow(ColorScheme colorScheme, int totalItems) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _StatCard(
              label: 'Total Households',
              value: totalItems.toString(),
              icon: Icons.home_work,
              color: Colors.blue,
            ),
            const SizedBox(width: 16),
            _StatCard(
              label: 'Active',
              value: (totalItems * 0.8).round().toString(),
              icon: Icons.check_circle,
              color: Colors.green,
            ),
            const SizedBox(width: 16),
            _StatCard(
              label: 'Archived',
              value: (totalItems * 0.2).round().toString(),
              icon: Icons.archive,
              color: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== TABLE VIEW ====================
  Widget _buildTableView(ColorScheme colorScheme, List<Household> households) {
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                _TableHeader('Household Name', flex: 2),
                _TableHeader('Head of Family', flex: 2),
                _TableHeader('Members', flex: 1),
                _TableHeader('Barangay', flex: 2),
                _TableHeader('Status', flex: 1),
                _TableHeader('Actions', flex: 1),
              ],
            ),
          ),
          // Table Body
          Expanded(
            child: ListView.separated(
              itemCount: households.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              itemBuilder: (context, index) {
                final household = households[index];
                return _TableRow(
                  household: household,
                  onView: () => context.go('/staff/households/${household.id}'),
                  onEdit: () => _showEditHouseholdDialog(context, household),
                  onArchive: () => _toggleArchive(context, household),
                  onDelete: () => _confirmDelete(context, household),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==================== LIST VIEW ====================
  Widget _buildListView(ColorScheme colorScheme, List<Household> households) {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: households.length,
      itemBuilder: (context, index) {
        final household = households[index];
        return _HouseholdCard(
          household: household,
          onTap: () => context.go('/staff/households/${household.id}'),
          onEdit: () => _showEditHouseholdDialog(context, household),
          onArchive: () => _toggleArchive(context, household),
          onDelete: () => _confirmDelete(context, household),
        );
      },
    );
  }

  // ==================== PAGINATION ====================
  Widget _buildPagination(
    ColorScheme colorScheme,
    int totalPages,
    int totalItems,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _currentPage > 0
                ? () => setState(() => _currentPage--)
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          const SizedBox(width: 16),
          Text(
            'Page ${_currentPage + 1} of $totalPages',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '($totalItems total)',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: _currentPage < totalPages - 1
                ? () => setState(() => _currentPage++)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilters(ColorScheme colorScheme) {
    final hasFilters =
        _selectedBarangay != null ||
        _includeArchived ||
        _searchCtrl.text.isNotEmpty;

    if (!hasFilters) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (_searchCtrl.text.isNotEmpty)
              _FilterChip(
                label: 'Search: ${_searchCtrl.text}',
                onRemove: () {
                  _searchCtrl.clear();
                  setState(() {});
                },
                color: colorScheme.primary,
              ),
            if (_selectedBarangay != null)
              _FilterChip(
                label: 'Barangay: $_selectedBarangay',
                onRemove: () {
                  setState(() => _selectedBarangay = null);
                },
                color: colorScheme.tertiary,
              ),
            if (_includeArchived)
              _FilterChip(
                label: 'Include Archived',
                onRemove: () {
                  setState(() => _includeArchived = false);
                },
                color: colorScheme.secondary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Something went wrong',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => ref.invalidate(householdsStreamProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.home_work_outlined,
                size: 64,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _searchCtrl.text.isEmpty && _selectedBarangay == null
                  ? 'No households yet'
                  : 'No matches found',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _searchCtrl.text.isEmpty && _selectedBarangay == null
                  ? 'Start by adding your first household to the parish registry'
                  : 'Try adjusting your search or filter criteria',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }



  Future<void> _showEditHouseholdDialog(
    BuildContext context,
    Household household,
  ) async {
    final result = await showDialog<Household>(
      context: context,
      builder: (context) => _HouseholdFormDialog(household: household),
    );

    if (result != null) {
      final notifier = ref.read(householdOperationsProvider.notifier);
      final success = await notifier.updateHousehold(result);

      if (success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Household updated')));
      }
    }
  }

  Future<void> _toggleArchive(BuildContext context, Household household) async {
    final notifier = ref.read(householdOperationsProvider.notifier);
    final success = await notifier.setArchiveStatus(
      household.id,
      !household.isArchived,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            household.isArchived ? 'Household restored' : 'Household archived',
          ),
        ),
      );
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
      }
    }
  }
}

/// Enhanced card widget for displaying a household
class _HouseholdCard extends StatelessWidget {
  final Household household;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  const _HouseholdCard({
    required this.household,
    required this.onTap,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Generate a consistent color based on family name
    final colorIndex = household.familyName.hashCode % 5;
    final colors = [
      colorScheme.primary,
      colorScheme.secondary,
      colorScheme.tertiary,
      Colors.orange,
      Colors.purple,
    ];
    final familyColor = colors[colorIndex.abs()];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.surface,
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar with family initial
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            familyColor.withValues(alpha: 0.8),
                            familyColor,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: familyColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          household.familyName.isNotEmpty
                              ? household.familyName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  household.familyName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    decoration: household.isArchived
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (household.isArchived)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'ARCHIVED',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: familyColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              household.householdId,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: familyColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Action menu
                    _buildActionMenu(colorScheme),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                // Info rows
                _InfoRow(
                  icon: Icons.location_on_outlined,
                  text: '${household.address}, ${household.barangay}',
                  color: colorScheme.onSurfaceVariant,
                ),
                if (household.contactNumber.isNotEmpty)
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    text: household.contactNumber,
                    color: colorScheme.onSurfaceVariant,
                  ),
                if (household.email.isNotEmpty)
                  _InfoRow(
                    icon: Icons.email_outlined,
                    text: household.email,
                    color: colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionMenu(ColorScheme colorScheme) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'edit':
              onEdit();
            case 'archive':
              onArchive();
            case 'delete':
              onDelete();
          }
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, color: colorScheme.primary, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Edit',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'archive',
            child: Row(
              children: [
                Icon(
                  household.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                  color: colorScheme.secondary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  household.isArchived ? 'Restore' : 'Archive',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                const SizedBox(width: 12),
                const Text(
                  'Delete',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.more_vert, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Info row widget for household details
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _InfoRow({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = color ?? colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: iconColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Navigation link widget
class _NavLink extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _NavLink({
    required this.label,
    required this.icon,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: isActive
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
          backgroundColor: isActive
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}

/// Stat card widget for stats row
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Table header widget
class _TableHeader extends StatelessWidget {
  final String label;
  final int flex;

  const _TableHeader(this.label, {required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Table row widget
class _TableRow extends StatelessWidget {
  final Household household;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  const _TableRow({
    required this.household,
    required this.onView,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Household Name
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      household.familyName.isNotEmpty
                          ? household.familyName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        household.familyName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        household.householdId,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Head of Family — show name from metadata or indicate pending
          Expanded(
            flex: 2,
            child: Text(
              household.metadata['headOfFamilyName'] as String? ??
                  (household.headOfFamilyId.isNotEmpty
                      ? household.headOfFamilyId
                      : '—'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color:
                    household.headOfFamilyId.isEmpty &&
                        (household.metadata['headOfFamilyName'] == null)
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onSurface,
              ),
            ),
          ),
          // Members count — fetched live
          Expanded(
            flex: 1,
            child: _MemberCountBadge(householdId: household.id),
          ),
          // Barangay
          Expanded(flex: 2, child: Text(household.barangay)),
          // Status
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: household.isArchived
                    ? Colors.orange.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                household.isArchived ? 'Archived' : 'Active',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: household.isArchived ? Colors.orange : Colors.green,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          // Actions
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: onView,
                  icon: const Icon(Icons.visibility_outlined),
                  color: colorScheme.primary,
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  color: colorScheme.secondary,
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  color: colorScheme.error,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog for adding/editing a household
class _HouseholdFormDialog extends StatefulWidget {
  final Household? household;

  const _HouseholdFormDialog({this.household});

  @override
  State<_HouseholdFormDialog> createState() => _HouseholdFormDialogState();
}

class _HouseholdFormDialogState extends State<_HouseholdFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _familyNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _zipCodeCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.household != null) {
      _familyNameCtrl.text = widget.household!.familyName;
      _addressCtrl.text = widget.household!.address;
      _barangayCtrl.text = widget.household!.barangay;
      _cityCtrl.text = widget.household!.city;
      _provinceCtrl.text = widget.household!.province;
      _zipCodeCtrl.text = widget.household!.zipCode;
      _contactCtrl.text = widget.household!.contactNumber;
      _emailCtrl.text = widget.household!.email;
      _notesCtrl.text = widget.household!.notes ?? '';
    }
  }

  @override
  void dispose() {
    _familyNameCtrl.dispose();
    _addressCtrl.dispose();
    _barangayCtrl.dispose();
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
    _zipCodeCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.household != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Household' : 'Add New Household'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _familyNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Family Name *',
                  hintText: 'e.g., Dela Cruz Family',
                ),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address *',
                  hintText: 'Street address',
                ),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _barangayCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Barangay *',
                      ),
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _cityCtrl,
                      decoration: const InputDecoration(
                        labelText: 'City/Municipality *',
                      ),
                      validator: (v) =>
                          v?.trim().isEmpty == true ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _provinceCtrl,
                      decoration: const InputDecoration(labelText: 'Province'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _zipCodeCtrl,
                      decoration: const InputDecoration(labelText: 'ZIP Code'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactCtrl,
                decoration: const InputDecoration(
                  labelText: 'Contact Number',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
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
          child: Text(isEditing ? 'Save Changes' : 'Add Household'),
        ),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final household = widget.household != null
        ? widget.household!.copyWith(
            familyName: _familyNameCtrl.text.trim(),
            address: _addressCtrl.text.trim(),
            barangay: _barangayCtrl.text.trim(),
            city: _cityCtrl.text.trim(),
            province: _provinceCtrl.text.trim(),
            zipCode: _zipCodeCtrl.text.trim(),
            contactNumber: _contactCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            notes: _notesCtrl.text.trim(),
            updatedAt: DateTime.now(),
          )
        : Household(
            id: '',
            householdId: '',
            familyName: _familyNameCtrl.text.trim(),
            headOfFamilyId: '',
            address: _addressCtrl.text.trim(),
            barangay: _barangayCtrl.text.trim(),
            city: _cityCtrl.text.trim(),
            province: _provinceCtrl.text.trim(),
            zipCode: _zipCodeCtrl.text.trim(),
            contactNumber: _contactCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            notes: _notesCtrl.text.trim(),
            registeredAt: DateTime.now(),
          );

    Navigator.pop(context, household);
  }
}

/// Filter chip widget for active filters
class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  final Color color;

  const _FilterChip({
    required this.label,
    required this.onRemove,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: color.withValues(alpha: 0.1),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
        deleteIcon: Icon(Icons.close, size: 16, color: color),
        onDeleted: onRemove,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}

/// Badge widget that shows member count for a household in the table view.
/// Uses a one-shot future fetch — NOT a polling stream — to avoid the N×poll
/// problem that causes 429 Too Many Requests when many rows are visible.
class _MemberCountBadge extends ConsumerStatefulWidget {
  final String householdId;
  const _MemberCountBadge({required this.householdId});

  @override
  ConsumerState<_MemberCountBadge> createState() => _MemberCountBadgeState();
}

class _MemberCountBadgeState extends ConsumerState<_MemberCountBadge> {
  int? _count;

  @override
  void initState() {
    super.initState();
    _fetchCount();
  }

  Future<void> _fetchCount() async {
    try {
      final repo = ref.read(householdRepositoryProvider);
      final members = await repo.getHouseholdMembers(widget.householdId);
      if (mounted) setState(() => _count = members.length);
    } catch (_) {
      // Silently ignore — badge will show '?' if fetch fails
      if (mounted) setState(() => _count = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = _count == null ? '…' : '$_count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
