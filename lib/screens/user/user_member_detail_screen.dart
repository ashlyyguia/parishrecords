// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../models/household.dart';
import '../../../providers/household_provider.dart';

/// User Member Details Screen - shows detailed information of a specific household member
class UserMemberDetailScreen extends ConsumerStatefulWidget {
  final String householdId;
  final String memberId;

  const UserMemberDetailScreen({
    super.key,
    required this.householdId,
    required this.memberId,
  });

  @override
  ConsumerState<UserMemberDetailScreen> createState() => _UserMemberDetailScreenState();
}

class _UserMemberDetailScreenState extends ConsumerState<UserMemberDetailScreen> {
  bool _isLoading = true;
  HouseholdMember? _member;
  List<Map<String, dynamic>> _sacraments = [];
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadMember();
  }

  Future<void> _loadMember() async {
    try {
      final member = await ref.read(householdRepositoryProvider).getMember(widget.memberId);
      if (mounted && member != null) {
        setState(() {
          _member = member;
          _isLoading = false;
        });
        _loadSacraments();
        _loadRequests();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _loadSacraments() async {
    // This would load sacrament records for the member
    // Placeholder implementation
    setState(() {
      _sacraments = [
        {
          'type': 'Baptism',
          'date': '2010-05-15',
          'location': 'St. Mary\'s Church',
          'status': 'completed',
        },
      ];
    });
  }

  Future<void> _loadRequests() async {
    // This would load certificate requests for the member
    // Placeholder implementation
    setState(() {
      _requests = [
        {
          'type': 'Baptismal Certificate',
          'date': '2024-01-15',
          'status': 'completed',
        },
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: const Text('Member Details'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_member == null) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: const Text('Member Details'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: Text('Member not found')),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(_member!.fullName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            onPressed: () => _showEditMemberDialog(),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: () => _showDeleteDialog(),
            icon: const Icon(Icons.delete_outline, color: Colors.red),
          ),
        ],
      ),
      body: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            // Member Header
            _buildMemberHeader(theme, colorScheme),
            
            // Tab Bar
            const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.person_outlined), text: 'Profile'),
                Tab(icon: Icon(Icons.church_outlined), text: 'Sacraments'),
                Tab(icon: Icon(Icons.assignment_outlined), text: 'Requests'),
              ],
            ),
            
            // Tab Content
            Expanded(
              child: TabBarView(
                children: [
                  _buildProfileTab(theme, colorScheme),
                  _buildSacramentsTab(theme, colorScheme),
                  _buildRequestsTab(theme, colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/user/households/${widget.householdId}/members/${widget.memberId}/ocr-link'),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Link Sacrament'),
      ),
    );
  }

  Widget _buildMemberHeader(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                _member!.fullName.isNotEmpty ? _member!.fullName[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _member!.fullName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    _Chip(label: _member!.role),
                    _Chip(
                      label: _member!.gender,
                      color: _member!.gender == 'Male' ? Colors.blue : Colors.pink,
                    ),
                    _Chip(
                      label: _member!.civilStatus,
                      color: Colors.orange,
                    ),
                  ],
                ),
                if (_member!.birthDate != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Born: ${_member!.birthDate!.month}/${_member!.birthDate!.day}/${_member!.birthDate!.year}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTab(ThemeData theme, ColorScheme colorScheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoCard(
          theme,
          colorScheme,
          'Personal Information',
          [
            _InfoRow(icon: Icons.badge_outlined, label: 'Full Name', value: _member!.fullName),
            _InfoRow(icon: Icons.people_outline, label: 'Role', value: _member!.role),
            _InfoRow(icon: Icons.wc_outlined, label: 'Gender', value: _member!.gender),
            _InfoRow(icon: Icons.favorite_border, label: 'Civil Status', value: _member!.civilStatus),
            if (_member!.birthDate != null)
              _InfoRow(
                icon: Icons.cake_outlined,
                label: 'Birth Date',
                value: '${_member!.birthDate!.month}/${_member!.birthDate!.day}/${_member!.birthDate!.year}',
              ),
            if (_member!.birthPlace?.isNotEmpty == true)
              _InfoRow(icon: Icons.location_on_outlined, label: 'Birth Place', value: _member!.birthPlace!),
            if (_member!.occupation?.isNotEmpty == true)
              _InfoRow(icon: Icons.work_outline, label: 'Occupation', value: _member!.occupation!),
          ],
        ),
        const SizedBox(height: 16),
        _buildInfoCard(
          theme,
          colorScheme,
          'Contact Information',
          [
            if (_member!.contactNumber?.isNotEmpty == true)
              _InfoRow(icon: Icons.phone_outlined, label: 'Phone', value: _member!.contactNumber!),
            if (_member!.email?.isNotEmpty == true)
              _InfoRow(icon: Icons.email_outlined, label: 'Email', value: _member!.email!),
            if (_member!.contactNumber?.isEmpty == true && _member!.email?.isEmpty == true)
              const _InfoRow(
                icon: Icons.info_outline,
                label: 'Contact',
                value: 'No contact information provided',
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSacramentsTab(ThemeData theme, ColorScheme colorScheme) {
    if (_sacraments.isEmpty) {
      return _buildEmptyTab(
        icon: Icons.church_outlined,
        title: 'No Sacrament Records',
        subtitle: 'Link sacrament records to see them here',
        actionLabel: 'Link Record',
        onAction: () => context.push('/user/households/${widget.householdId}/members/${widget.memberId}/ocr-link'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _sacraments.length,
      itemBuilder: (context, index) {
        final sacrament = _sacraments[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.church_outlined, color: Colors.purple),
            ),
            title: Text(sacrament['type']),
            subtitle: Text('${sacrament['date']} • ${sacrament['location']}'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                sacrament['status'],
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRequestsTab(ThemeData theme, ColorScheme colorScheme) {
    if (_requests.isEmpty) {
      return _buildEmptyTab(
        icon: Icons.assignment_outlined,
        title: 'No Requests',
        subtitle: 'You have not submitted any certificate requests',
        actionLabel: 'New Request',
        onAction: () => context.go('/user/requests'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final request = _requests[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.description_outlined, color: Colors.blue),
            ),
            title: Text(request['type']),
            subtitle: Text('Requested on ${request['date']}'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: request['status'] == 'completed'
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                request['status'],
                style: TextStyle(
                  fontSize: 12,
                  color: request['status'] == 'completed' ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
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

  Widget _buildInfoCard(
    ThemeData theme,
    ColorScheme colorScheme,
    String title,
    List<Widget> children,
  ) {
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
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  void _showEditMemberDialog() {
    // Navigate to edit member screen
    context.push('/user/households/${widget.householdId}/members/${widget.memberId}/edit');
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Member'),
        content: Text('Are you sure you want to delete ${_member!.fullName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(householdRepositoryProvider).deleteMember(widget.memberId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Member deleted')),
                  );
                  context.pop();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
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

/// Chip Widget
class _Chip extends StatelessWidget {
  final String label;
  final Color? color;

  const _Chip({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = color ?? Colors.purple;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
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
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
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
          ),
        ],
      ),
    );
  }
}
