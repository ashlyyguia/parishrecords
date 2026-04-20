// ignore_for_file: unnecessary_underscores, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../admin_design_system.dart';

class AdminRolesPage extends StatefulWidget {
  const AdminRolesPage({super.key});

  @override
  State<AdminRolesPage> createState() => _AdminRolesPageState();
}

class _AdminRolesPageState extends State<AdminRolesPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  String _selectedRole = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateUserRole(String userId, String newRole) async {
    try {
      await _db.collection('users').doc(userId).update({
        'role': newRole,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User role updated to $newRole'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating role: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _disableUser(String userId, bool disabled) async {
    try {
      await _db.collection('users').doc(userId).update({
        'disabled': disabled,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(disabled ? 'User disabled' : 'User enabled'),
          backgroundColor: disabled ? Colors.orange : Colors.green,
        ),
      );
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

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.purple;
      case 'staff':
        return Colors.blue;
      case 'finance':
        return Colors.green;
      case 'parishioner':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'staff':
        return Icons.badge;
      case 'finance':
        return Icons.account_balance;
      case 'parishioner':
        return Icons.person;
      default:
        return Icons.person_outline;
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
                title: 'Roles & Permissions',
                subtitle: 'Manage user roles and access levels',
                icon: Icons.admin_panel_settings_outlined,
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
                              hintText: 'Search users...',
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

                        // Role Filter
                        Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildFilterTab('All', 'all'),
                              _buildFilterTab('Admin', 'admin'),
                              _buildFilterTab('Staff', 'staff'),
                              _buildFilterTab('Finance', 'finance'),
                              _buildFilterTab('User', 'parishioner'),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // Users List
              Expanded(
                child: Container(
                  decoration: AdminDesignSystem.cardDecoration(context),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _db
                        .collection('users')
                        .orderBy('role')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
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
                                  'Failed to load users',
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
                              ],
                            ),
                          ),
                        );
                      }

                      var users = snap.data?.docs ?? [];

                      // Apply role filter
                      if (_selectedRole != 'all') {
                        users = users
                            .where(
                              (u) =>
                                  (u['role']?.toString().toLowerCase() ??
                                      'parishioner') ==
                                  _selectedRole,
                            )
                            .toList();
                      }

                      // Apply search filter
                      final searchQuery = _searchCtrl.text.trim().toLowerCase();
                      if (searchQuery.isNotEmpty) {
                        users = users.where((u) {
                          final data = u.data() as Map<String, dynamic>;
                          return data.values.any(
                            (v) => v.toString().toLowerCase().contains(
                              searchQuery,
                            ),
                          );
                        }).toList();
                      }

                      if (users.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 64,
                                color: colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No users found',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.outline,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Users will appear here when they register',
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
                        itemCount: users.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final user = users[index];
                          return _buildUserCard(context, user);
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
    final isSelected = _selectedRole == value;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => setState(() => _selectedRole = value),
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

  Widget _buildUserCard(BuildContext context, DocumentSnapshot user) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final data = user.data() as Map<String, dynamic>;
    final userId = user.id;
    final email = data['email']?.toString() ?? 'No email';
    final displayName =
        data['displayName']?.toString() ?? email.split('@').first;
    final role = data['role']?.toString() ?? 'parishioner';
    final disabled = data['disabled'] == true;
    final photoUrl = data['photoURL']?.toString();

    final roleColor = _getRoleColor(role);
    final roleIcon = _getRoleIcon(role);

    return Container(
      decoration: BoxDecoration(
        color: disabled
            ? colorScheme.surfaceContainerHighest.withOpacity(0.5)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: disabled
              ? colorScheme.outline.withOpacity(0.3)
              : colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        leading: CircleAvatar(
          backgroundColor: roleColor.withOpacity(0.1),
          backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
          child: photoUrl == null
              ? Icon(roleIcon, color: roleColor, size: 20)
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                displayName,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  decoration: disabled ? TextDecoration.lineThrough : null,
                  color: disabled ? colorScheme.outline : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: roleColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(roleIcon, size: 12, color: roleColor),
                  const SizedBox(width: 4),
                  Text(
                    role.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: roleColor,
                    ),
                  ),
                ],
              ),
            ),
            if (disabled)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'DISABLED',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.red,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              email,
              style: TextStyle(
                color: disabled
                    ? colorScheme.outline
                    : colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            if (userId.isNotEmpty)
              Text(
                'ID: ${userId.substring(0, userId.length > 8 ? 8 : userId.length)}...',
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'disable') {
              await _disableUser(userId, true);
            } else if (value == 'enable') {
              await _disableUser(userId, false);
            } else {
              await _updateUserRole(userId, value);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'admin',
              child: Row(
                children: [
                  Icon(Icons.admin_panel_settings, color: Colors.purple),
                  SizedBox(width: 8),
                  Text('Make Admin'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'staff',
              child: Row(
                children: [
                  Icon(Icons.badge, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Make Staff'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'finance',
              child: Row(
                children: [
                  Icon(Icons.account_balance, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Make Finance'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'parishioner',
              child: Row(
                children: [
                  Icon(Icons.person, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Make Parishioner'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            if (!disabled)
              const PopupMenuItem(
                value: 'disable',
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Disable User'),
                  ],
                ),
              ),
            if (disabled)
              const PopupMenuItem(
                value: 'enable',
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Enable User'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
