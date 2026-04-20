// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../widgets/app_loading.dart';
import '../../../services/users_repository.dart';

/// Enhanced User Management with complete CRUD, roles, and account control
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
  int _refreshKey = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => setState(() => _refreshKey++),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Search and Action Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 600;
                return Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: isNarrow
                          ? constraints.maxWidth
                          : constraints.maxWidth - 140,
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search by name, email...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () =>
                                      setState(() => _searchCtrl.clear()),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showCreateUserDialog(context),
                      icon: const Icon(Icons.person_add),
                      label: const Text('Add User'),
                    ),
                  ],
                );
              },
            ),
          ),

          // Filter Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _selectedRole == 'all',
                    onSelected: (v) => setState(() => _selectedRole = 'all'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Admin'),
                    selected: _selectedRole == 'admin',
                    onSelected: (v) => setState(() => _selectedRole = 'admin'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Staff'),
                    selected: _selectedRole == 'staff',
                    onSelected: (v) => setState(() => _selectedRole = 'staff'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Parishioner'),
                    selected: _selectedRole == 'parishioner',
                    onSelected: (v) =>
                        setState(() => _selectedRole = 'parishioner'),
                  ),
                  const SizedBox(width: 16),
                  FilterChip(
                    label: const Text('Show Disabled'),
                    selected: _showDisabled,
                    onSelected: (v) => setState(() => _showDisabled = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Users Stats & List
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey(_refreshKey),
              future: _loadUsers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoading(message: 'Loading users...');
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                var users = snapshot.data ?? [];
                debugPrint(
                  '[Users UI] Received ${users.length} users from repository',
                );
                if (users.isNotEmpty) {
                  debugPrint('[Users UI] First user: ${users.first}');
                }

                // Apply client-side filters
                debugPrint('[Users UI] Before filters: ${users.length} users');

                if (!_showDisabled) {
                  users = users.where((u) {
                    final disabled = u['disabled'] == true;
                    if (disabled) {
                      debugPrint(
                        '[Users UI] Filtering out disabled user: ${u['id']}',
                      );
                    }
                    return !disabled;
                  }).toList();
                  debugPrint(
                    '[Users UI] After disabled filter: ${users.length} users',
                  );
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

                return Column(
                  children: [
                    _buildStatsRow(users),
                    const SizedBox(height: 16),
                    Expanded(
                      child: users.isEmpty
                          ? _buildEmptyState()
                          : RefreshIndicator(
                              onRefresh: () async {
                                setState(() => _refreshKey++);
                              },
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                itemCount: users.length,
                                itemBuilder: (context, index) {
                                  final user = users[index];
                                  final userId = user['id']?.toString() ?? '';
                                  return _UserCard(
                                    userId: userId,
                                    data: user,
                                    onEdit: () => _showEditUserDialog(
                                      context,
                                      userId,
                                      user,
                                    ),
                                    onResetPassword: () => _resetPassword(
                                      context,
                                      user['email'] ?? '',
                                    ),
                                    onToggleStatus: () => _toggleUserStatus(
                                      context,
                                      userId,
                                      user['disabled'] == true,
                                    ),
                                    onDelete: () => _confirmDeleteUser(
                                      context,
                                      userId,
                                      user,
                                    ),
                                  );
                                },
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
    );
  }

  Future<List<Map<String, dynamic>>> _loadUsers() async {
    try {
      final repo = UsersRepository();
      final users = await repo.list(role: _selectedRole);
      debugPrint(
        '[Users] Loaded ${users.length} users with role: $_selectedRole',
      );
      return users;
    } catch (e) {
      debugPrint('[Users] Error loading users: $e');
      rethrow;
    }
  }

  Widget _buildStatsRow(List<Map<String, dynamic>> users) {
    int total = users.length;
    int admins = 0;
    int staff = 0;
    int finance = 0;
    int parishioners = 0;
    int disabled = 0;

    for (final user in users) {
      final role = user['role']?.toString().toLowerCase() ?? 'parishioner';
      final isDisabled = user['disabled'] == true;

      if (isDisabled) disabled++;

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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _StatItem(count: '$total', label: 'Total', color: Colors.blue),
              _StatItem(count: '$admins', label: 'Admins', color: Colors.red),
              _StatItem(count: '$staff', label: 'Staff', color: Colors.orange),
              _StatItem(
                count: '$finance',
                label: 'Finance',
                color: Colors.green,
              ),
              _StatItem(
                count: '$parishioners',
                label: 'Parish',
                color: Colors.purple,
              ),
              _StatItem(
                count: '$disabled',
                label: 'Disabled',
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No users found',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filters',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateUserDialog(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _CreateUserDialog(),
    );

    if (result != null) {
      try {
        // Create Firebase Auth user
        final userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: result['email'],
              password: result['password'],
            );

        // Create Firestore user document
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
              'uid': userCredential.user!.uid,
              'email': result['email'],
              'displayName': result['displayName'],
              'role': result['role'],
              'emailVerified': true,
              'createdAt': FieldValue.serverTimestamp(),
              'lastLogin': null,
              'disabled': false,
            });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('User ${result['email']} created successfully'),
            ),
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
        final repo = UsersRepository();
        await repo.delete(userId);

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

class _StatItem extends StatelessWidget {
  final String count;
  final String label;
  final Color color;

  const _StatItem({
    required this.count,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          Text(
            count,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final String userId;
  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final VoidCallback onResetPassword;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  const _UserCard({
    required this.userId,
    required this.data,
    required this.onEdit,
    required this.onResetPassword,
    required this.onToggleStatus,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final email = data['email']?.toString() ?? 'No email';
    final name =
        data['display_name']?.toString() ??
        data['displayName']?.toString() ??
        'Unnamed';
    final role = data['role']?.toString().toLowerCase() ?? 'parishioner';
    final isDisabled = data['disabled'] == true;

    Color roleColor;
    switch (role) {
      case 'admin':
        roleColor = Colors.red;
      case 'staff':
        roleColor = Colors.orange;
      case 'finance':
        roleColor = Colors.green;
      default:
        roleColor = Colors.purple;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: roleColor.withValues(alpha: 0.1),
          child: Icon(Icons.person, color: roleColor),
        ),
        title: Text(name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    role.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      color: roleColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isDisabled) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'DISABLED',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                onEdit();
              case 'reset':
                onResetPassword();
              case 'toggle':
                onToggleStatus();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(value: 'reset', child: Text('Reset Password')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(isDisabled ? 'Enable' : 'Disable'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _role = 'parishioner';

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New User'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Display Name'),
                validator: (v) => v?.isEmpty == true ? 'Required' : null,
              ),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v?.isEmpty == true ? 'Required' : null,
              ),
              TextFormField(
                controller: _passwordCtrl,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) =>
                    ((v?.length ?? 0) < 6) ? 'Min 6 characters' : null,
              ),
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'email': _emailCtrl.text.trim(),
                'password': _passwordCtrl.text,
                'displayName': _nameCtrl.text.trim(),
                'role': _role,
              });
            }
          },
          child: const Text('Create'),
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
