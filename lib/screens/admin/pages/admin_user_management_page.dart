// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../../utils/firestore_date.dart';
import '../../../utils/record_date_filter.dart';
import '../../../widgets/app_loading.dart';
import '../../../widgets/record_date_range_filters.dart';
import '../../../services/users_repository.dart';
import '../admin_design_system.dart';

/// User management with search, role filters, and registration date range.
class AdminUserManagementPage extends ConsumerStatefulWidget {
  const AdminUserManagementPage({super.key});

  @override
  ConsumerState<AdminUserManagementPage> createState() =>
      _AdminUserManagementPageState();
}

class _AdminUserManagementPageState
    extends ConsumerState<AdminUserManagementPage> {
  final _searchCtrl = TextEditingController();
  String _selectedRole = 'all';
  bool _showDisabled = false;
  DateTime? _from;
  DateTime? _to;
  int _refreshKey = 0;

  static const _roleFilters = [
    ('all', 'All'),
    ('admin', 'Admin'),
    ('staff', 'Staff'),
    ('finance', 'Finance'),
    ('parishioner', 'Parishioner'),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Container(
        decoration: AdminDesignSystem.pageBackground(context),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'User Management',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Search, filter by role and registration date',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.55),
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Refresh',
                      onPressed: () => setState(() => _refreshKey++),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _UsersFilterToolbar(
                  searchCtrl: _searchCtrl,
                  from: _from,
                  to: _to,
                  onSearchChanged: () => setState(() {}),
                  onFromChanged: (d) => setState(() => _from = d),
                  onToChanged: (d) => setState(() => _to = d),
                  onClearDates: () => setState(() {
                    _from = null;
                    _to = null;
                  }),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _RoleFilterBar(
                  selectedRole: _selectedRole,
                  showDisabled: _showDisabled,
                  onRoleSelected: (r) => setState(() => _selectedRole = r),
                  onShowDisabledChanged: (v) =>
                      setState(() => _showDisabled = v),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  key: ValueKey('$_refreshKey-$_selectedRole'),
                  future: _loadUsers(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const AppLoading(message: 'Loading users...');
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    final users = _applyFilters(snapshot.data ?? []);

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _UsersStatsGrid(users: users),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Users (${users.length})',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: users.isEmpty
                              ? _buildEmptyState()
                              : RefreshIndicator(
                                  onRefresh: () async {
                                    setState(() => _refreshKey++);
                                  },
                                  child: _UsersDataTable(
                                    users: users,
                                    onEdit: (id, data) => _showEditUserDialog(
                                      context,
                                      id,
                                      data,
                                    ),
                                    onResetPassword: (email) =>
                                        _resetPassword(context, email),
                                    onToggleStatus: (id, disabled) =>
                                        _toggleUserStatus(
                                          context,
                                          id,
                                          disabled,
                                        ),
                                    onDelete: (id, data) => _confirmDeleteUser(
                                      context,
                                      id,
                                      data,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> raw) {
    var users = List<Map<String, dynamic>>.from(raw);

    if (!_showDisabled) {
      users = users.where((u) => u['disabled'] != true).toList();
    }

    if (_from != null || _to != null) {
      users = users
          .where(
            (u) => RecordDateFilter.matchesValue(
              _userRegistrationRaw(u),
              from: _from,
              to: _to,
            ),
          )
          .toList();
    }

    if (_searchCtrl.text.isNotEmpty) {
      final query = _searchCtrl.text.toLowerCase();
      users = users.where((u) {
        final email = u['email']?.toString().toLowerCase() ?? '';
        final name =
            u['display_name']?.toString().toLowerCase() ??
            u['displayName']?.toString().toLowerCase() ??
            '';
        return email.contains(query) || name.contains(query);
      }).toList();
    }

    if (_selectedRole != 'all') {
      users = users.where((u) {
        final role = (u['role'] ?? 'parishioner').toString().toLowerCase();
        return role == _selectedRole;
      }).toList();
    }

    return users;
  }

  static Object? _userRegistrationRaw(Map<String, dynamic> u) =>
      u['created_at'] ?? u['createdAt'] ?? u['updatedAt'];

  Future<List<Map<String, dynamic>>> _loadUsers() async {
    final repo = UsersRepository();
    return repo.list(role: 'all', limit: 200);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'No users found',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 6),
          Text(
            'Try adjusting search, role, or date filters',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditUserDialog(
    BuildContext context,
    String userId,
    Map<String, dynamic> data,
  ) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditUserDialog(data: data),
    );

    if (result != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .update({
              'displayName': result['displayName'],
              'role': result['role'],
              'updatedAt': FieldValue.serverTimestamp(),
            });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User updated successfully')),
          );
          setState(() => _refreshKey++);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _resetPassword(BuildContext context, String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset email sent to $email')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _toggleUserStatus(
    BuildContext context,
    String userId,
    bool currentlyDisabled,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'disabled': !currentlyDisabled,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentlyDisabled ? 'User enabled' : 'User disabled'),
          ),
        );
        setState(() => _refreshKey++);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _confirmDeleteUser(
    BuildContext context,
    String userId,
    Map<String, dynamic> data,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
          'Are you sure you want to delete ${data['email'] ?? 'this user'}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await UsersRepository().delete(userId);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User deleted successfully')),
          );
          setState(() => _refreshKey++);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }
}

class _UsersFilterToolbar extends StatelessWidget {
  const _UsersFilterToolbar({
    required this.searchCtrl,
    required this.from,
    required this.to,
    required this.onSearchChanged,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onClearDates,
  });

  final TextEditingController searchCtrl;
  final DateTime? from;
  final DateTime? to;
  final VoidCallback onSearchChanged;
  final ValueChanged<DateTime?> onFromChanged;
  final ValueChanged<DateTime?> onToChanged;
  final VoidCallback onClearDates;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 720;
          final search = TextField(
            controller: searchCtrl,
            onChanged: (_) => onSearchChanged(),
            decoration: InputDecoration(
              hintText: 'Search by name or email…',
              prefixIcon: const Icon(Icons.search_rounded, size: 22),
              suffixIcon: searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        searchCtrl.clear();
                        onSearchChanged();
                      },
                    )
                  : null,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          );
          final dates = RecordDateRangeFilters(
            from: from,
            to: to,
            fromLabel: 'From',
            toLabel: 'To',
            onFromChanged: onFromChanged,
            onToChanged: onToChanged,
            onClear: onClearDates,
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [search, const SizedBox(height: 10), dates],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 2, child: search),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: dates),
            ],
          );
        },
      ),
    );
  }
}

class _RoleFilterBar extends StatelessWidget {
  const _RoleFilterBar({
    required this.selectedRole,
    required this.showDisabled,
    required this.onRoleSelected,
    required this.onShowDisabledChanged,
  });

  final String selectedRole;
  final bool showDisabled;
  final ValueChanged<String> onRoleSelected;
  final ValueChanged<bool> onShowDisabledChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (id, label) in _AdminUserManagementPageState._roleFilters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(label),
                selected: selectedRole == id,
                showCheckmark: true,
                onSelected: (_) => onRoleSelected(id),
                selectedColor: cs.primary.withValues(alpha: 0.18),
                checkmarkColor: cs.primary,
              ),
            ),
          FilterChip(
            label: const Text('Show disabled'),
            selected: showDisabled,
            onSelected: onShowDisabledChanged,
            avatar: Icon(
              showDisabled ? Icons.visibility : Icons.visibility_off_outlined,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersStatsGrid extends StatelessWidget {
  const _UsersStatsGrid({required this.users});

  final List<Map<String, dynamic>> users;

  @override
  Widget build(BuildContext context) {
    var admins = 0;
    var staff = 0;
    var finance = 0;
    var parishioners = 0;
    var disabled = 0;

    for (final user in users) {
      final role = user['role']?.toString().toLowerCase() ?? 'parishioner';
      if (user['disabled'] == true) disabled++;
      switch (role) {
        case 'admin':
          admins++;
        case 'staff':
          staff++;
        case 'finance':
          finance++;
        default:
          parishioners++;
      }
    }

    final items = [
      _StatData('Total', '${users.length}', Colors.indigo),
      _StatData('Admins', '$admins', Colors.red.shade400),
      _StatData('Staff', '$staff', Colors.orange.shade700),
      _StatData('Finance', '$finance', Colors.green.shade600),
      _StatData('Parish', '$parishioners', Colors.purple.shade400),
      _StatData('Disabled', '$disabled', Colors.grey.shade600),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w > 900 ? 6 : (w > 520 ? 3 : 2);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: cols >= 6 ? 2.2 : 2.0,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => _CompactStatCard(data: items[i]),
        );
      },
    );
  }
}

class _StatData {
  const _StatData(this.label, this.count, this.color);
  final String label;
  final String count;
  final Color color;
}

class _CompactStatCard extends StatelessWidget {
  const _CompactStatCard({required this.data});
  final _StatData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: data.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              color: data.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data.count,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: data.color,
                    height: 1.1,
                  ),
                ),
                Text(
                  data.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersDataTable extends StatelessWidget {
  const _UsersDataTable({
    required this.users,
    required this.onEdit,
    required this.onResetPassword,
    required this.onToggleStatus,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> users;
  final void Function(String id, Map<String, dynamic> data) onEdit;
  final void Function(String email) onResetPassword;
  final void Function(String id, bool disabled) onToggleStatus;
  final void Function(String id, Map<String, dynamic> data) onDelete;

  static Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.red.shade400;
      case 'staff':
        return Colors.orange.shade700;
      case 'finance':
        return Colors.green.shade600;
      default:
        return Colors.purple.shade400;
    }
  }

  static String _name(Map<String, dynamic> d) =>
      d['display_name']?.toString() ??
      d['displayName']?.toString() ??
      'Unnamed';

  static String _registeredLabel(Map<String, dynamic> d) {
    final dt = parseFirestoreDate(
      d['created_at'] ?? d['createdAt'] ?? d['updatedAt'],
    );
    return dt != null ? DateFormat('MMM d, yyyy').format(dt) : '—';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final primary = cs.primary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.sizeOf(context).width - 40,
                ),
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                    primary.withValues(alpha: 0.1),
                  ),
                  headingTextStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: primary,
                  ),
                  dataRowMinHeight: 48,
                  columnSpacing: 24,
                  horizontalMargin: 16,
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Email')),
                    DataColumn(label: Text('Role')),
                    DataColumn(label: Text('Registered')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: users.map((d) {
                    final id =
                        d['uid']?.toString() ?? d['id']?.toString() ?? '';
                    final role =
                        (d['role'] ?? 'parishioner').toString().toLowerCase();
                    final roleColor = _roleColor(role);
                    final disabled = d['disabled'] == true;
                    final email = d['email']?.toString() ?? '—';

                    return DataRow(
                      cells: [
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: roleColor.withValues(
                                  alpha: 0.12,
                                ),
                                child: Text(
                                  _name(d).isNotEmpty
                                      ? _name(d)[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: roleColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  _name(d),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 200,
                            child: Text(
                              email,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: roleColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              role.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: roleColor,
                              ),
                            ),
                          ),
                        ),
                        DataCell(Text(_registeredLabel(d))),
                        DataCell(
                          Text(
                            disabled ? 'Disabled' : 'Active',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: disabled
                                  ? Colors.grey.shade600
                                  : Colors.green.shade700,
                            ),
                          ),
                        ),
                        DataCell(
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded),
                            onSelected: (value) {
                              switch (value) {
                                case 'edit':
                                  onEdit(id, d);
                                case 'reset':
                                  onResetPassword(email);
                                case 'toggle':
                                  onToggleStatus(id, disabled);
                                case 'delete':
                                  onDelete(id, d);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              const PopupMenuItem(
                                value: 'reset',
                                child: Text('Reset password'),
                              ),
                              PopupMenuItem(
                                value: 'toggle',
                                child: Text(
                                  disabled ? 'Enable' : 'Disable',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EditUserDialog extends StatefulWidget {
  final Map<String, dynamic> data;

  const _EditUserDialog({required this.data});

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final TextEditingController _nameCtrl;
  late String _role;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text:
          widget.data['display_name']?.toString() ??
          widget.data['displayName']?.toString() ??
          '',
    );
    _role = widget.data['role']?.toString() ?? 'parishioner';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit User'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Display Name'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(
                  value: 'parishioner',
                  child: Text('Parishioner'),
                ),
                DropdownMenuItem(value: 'staff', child: Text('Staff')),
                DropdownMenuItem(value: 'finance', child: Text('Finance')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: (v) => setState(() => _role = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, {
              'displayName': _nameCtrl.text.trim(),
              'role': _role,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
