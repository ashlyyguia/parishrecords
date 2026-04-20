// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../widgets/app_loading.dart';
import '../admin_design_system.dart';

class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});

  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Container(
        decoration: AdminDesignSystem.pageBackground(context),
        child: SafeArea(
          child: Column(
            children: [
              // Modern Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: AdminDesignSystem.pageHeader(
                  context,
                  title: 'User Management',
                  subtitle: 'Manage user accounts and permissions',
                  icon: Icons.people,
                  actions: [
                    AdminDesignSystem.actionButton(
                      context,
                      label: 'Add User',
                      icon: Icons.person_add,
                      onPressed: () => _showAddUserDialog(context, colorScheme),
                    ),
                  ],
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AdminDesignSystem.searchBar(
                  context,
                  controller: _searchController,
                  hint: 'Search users by name or email...',
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  onClear: () {
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                ),
              ),
              const SizedBox(height: 20),

              // Users List
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const AppLoading(message: 'Loading users...');
                    }

                    if (snapshot.hasError) {
                      return AdminDesignSystem.emptyState(
                        context,
                        message: 'Error loading users',
                        icon: Icons.error_outline,
                        actionLabel: 'Retry',
                        onAction: () => setState(() {}),
                      );
                    }
                    final docs = snapshot.data?.docs ?? const [];
                    final filteredUsers = docs.where((doc) {
                      final data = doc.data();
                      final email = (data['email'] ?? '')
                          .toString()
                          .toLowerCase();
                      final displayName = (data['displayName'] ?? '')
                          .toString()
                          .toLowerCase();
                      return email.contains(_searchQuery) ||
                          displayName.contains(_searchQuery);
                    }).toList();

                    if (filteredUsers.isEmpty) {
                      return AdminDesignSystem.emptyState(
                        context,
                        message: _searchQuery.isEmpty
                            ? 'No users found'
                            : 'No users match your search',
                        icon: Icons.people_outline,
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, index) {
                        final doc = filteredUsers[index];
                        final data = doc.data();
                        return _buildModernUserCard(doc.id, data);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: context.isWide
          ? null
          : FloatingActionButton(
              onPressed: () => _showAddUserDialog(context, colorScheme),
              backgroundColor: colorScheme.primary,
              child: const Icon(Icons.person_add),
            ),
    );
  }

  // Modern User Card
  Widget _buildModernUserCard(String userId, Map<String, dynamic> data) {
    final email = data['email'] ?? 'No email';
    final displayName = data['displayName'] ?? 'No name';
    final role = data['role'] ?? 'parishioner';
    final emailVerified = data['emailVerified'] ?? false;
    final lastLogin = data['lastLogin'];
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AdminDesignSystem.cardDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _getRoleColor(role).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getRoleIcon(role),
                color: _getRoleColor(role),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      AdminDesignSystem.statusBadge(
                        context,
                        role.toUpperCase(),
                        _getRoleColor(role),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        emailVerified ? Icons.verified : Icons.warning,
                        size: 14,
                        color: emailVerified ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        emailVerified ? 'Verified' : 'Not verified',
                        style: TextStyle(
                          fontSize: 12,
                          color: emailVerified ? Colors.green : Colors.orange,
                        ),
                      ),
                      if (lastLogin != null) ...[
                        const SizedBox(width: 16),
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatTimestamp(lastLogin),
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) => _handleUserAction(value, userId, data),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit_role',
                  child: Row(
                    children: [
                      Icon(Icons.edit),
                      SizedBox(width: 8),
                      Text('Change Role'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete User', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.red;
      case 'staff':
        return Colors.blue;
      case 'finance':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'staff':
        return Icons.work;
      case 'finance':
        return Icons.account_balance_wallet;
      default:
        return Icons.person;
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Never';

    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is String) {
      date = DateTime.tryParse(timestamp) ?? DateTime.now();
    } else {
      return 'Unknown';
    }

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

  void _handleUserAction(
    String action,
    String userId,
    Map<String, dynamic> userData,
  ) {
    switch (action) {
      case 'edit_role':
        _showChangeRoleDialog(userId, userData['role'] ?? 'staff');
        break;
      case 'delete':
        _showDeleteUserDialog(userId, userData['email'] ?? 'Unknown');
        break;
    }
  }

  void _showChangeRoleDialog(String userId, String currentRole) {
    String selectedRole = currentRole;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Change User Role'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['admin', 'staff', 'finance'].map((role) {
                  final isSelected = selectedRole == role;
                  return ChoiceChip(
                    label: Text(role[0].toUpperCase() + role.substring(1)),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => selectedRole = role);
                      }
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .update({'role': selectedRole});
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to update role: $e')),
                  );
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteUserDialog(String userId, String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Are you sure you want to delete user: $email?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .delete();
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete user: $e')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddUserDialog(BuildContext parentContext, ColorScheme colorScheme) {
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    String selectedRole = 'staff';

    showDialog(
      context: parentContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add New User'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selectedRole,
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(value: 'staff', child: Text('Staff')),
                DropdownMenuItem(value: 'finance', child: Text('Finance')),
                DropdownMenuItem(
                  value: 'parishioner',
                  child: Text('Parishioner'),
                ),
              ],
              onChanged: (value) => selectedRole = value!,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              final name = nameController.text.trim();

              if (email.isEmpty || name.isEmpty) {
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter both email and display name.'),
                  ),
                );
                return;
              }

              if (!email.contains('@')) {
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid email address.'),
                  ),
                );
                return;
              }

              try {
                // Create pending user document in Firestore
                // Note: Firebase Auth user must be created via Admin SDK or Firebase Console
                final docRef = FirebaseFirestore.instance
                    .collection('pending_users')
                    .doc();

                await docRef.set({
                  'email': email,
                  'displayName': name,
                  'role': selectedRole,
                  'status': 'pending_creation',
                  'createdAt': FieldValue.serverTimestamp(),
                  'createdBy': FirebaseAuth.instance.currentUser?.uid,
                });

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                ScaffoldMessenger.of(parentContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      'User request created for $email with role: $selectedRole. '
                      'Create the user in Firebase Auth Console or use a backend function.',
                    ),
                    duration: const Duration(seconds: 5),
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(
                  parentContext,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Add User'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
