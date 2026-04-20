// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/app_loading.dart';
import '../../../providers/household_provider.dart';

/// Admin Parishioner Records Management - view all parishioners across households
class AdminParishionersPage extends ConsumerStatefulWidget {
  const AdminParishionersPage({super.key});

  @override
  ConsumerState<AdminParishionersPage> createState() =>
      _AdminParishionersPageState();
}

class _AdminParishionersPageState extends ConsumerState<AdminParishionersPage> {
  final _searchCtrl = TextEditingController();
  String? _selectedSacramentStatus;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Parishioner Records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Export',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter',
            onPressed: () => _showFilterDialog(context),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by name, household...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _searchCtrl.clear()),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Stats & Parishioners List
          Expanded(
            child: StreamBuilder<List<dynamic>>(
              stream: ref
                  .watch(householdRepositoryProvider)
                  .watchMembersGlobal(
                    searchQuery: _searchCtrl.text.isNotEmpty
                        ? _searchCtrl.text
                        : null,
                    sacramentStatus: _selectedSacramentStatus,
                  )
                  .map((rows) => rows.cast<dynamic>()),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoading(message: 'Loading parishioners...');
                }

                final members = snapshot.data ?? const <dynamic>[];
                final analytics = _calculateAnalytics(members);

                return Column(
                  children: [
                    _buildStatsRow(analytics),
                    const SizedBox(height: 16),
                    Expanded(
                      child: members.isEmpty
                          ? _buildEmptyState()
                          : _buildParishionersList(members),
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

  Map<String, int> _calculateAnalytics(List<dynamic> members) {
    int total = members.length;
    int baptized = 0;
    int confirmed = 0;
    int married = 0;
    int children = 0;

    for (final m in members) {
      final data = m is Map<String, dynamic> ? m : <String, dynamic>{};
      final sacraments = data['sacraments'];
      if (sacraments is List) {
        for (final s in sacraments) {
          final sacramentName = (s is Map ? s['name'] ?? s['type'] : s)
              ?.toString()
              .toLowerCase();
          if (sacramentName?.contains('baptism') == true) baptized++;
          if (sacramentName?.contains('confirmation') == true) confirmed++;
          if (sacramentName?.contains('marriage') == true) married++;
        }
      }
      // Check age or role for children
      final role = data['role']?.toString().toLowerCase();
      final age = data['age'];
      if (role == 'child' || (age is num && age < 18)) {
        children++;
      }
    }

    return {
      'total': total,
      'baptized': baptized,
      'confirmed': confirmed,
      'married': married,
      'children': children,
    };
  }

  Widget _buildStatsRow(Map<String, int> analytics) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _StatItem(
                count: '${analytics['total']}',
                label: 'Total',
                color: Colors.blue,
              ),
              _StatItem(
                count: '${analytics['baptized']}',
                label: 'Baptized',
                color: Colors.cyan,
              ),
              _StatItem(
                count: '${analytics['confirmed']}',
                label: 'Confirmed',
                color: Colors.purple,
              ),
              _StatItem(
                count: '${analytics['married']}',
                label: 'Married',
                color: Colors.pink,
              ),
              _StatItem(
                count: '${analytics['children']}',
                label: 'Children',
                color: Colors.orange,
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
            'No parishioners found',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildParishionersList(List<dynamic> members) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final row = members[index] as dynamic;
        final data = (row is Map)
            ? row.cast<String, dynamic>()
            : <String, dynamic>{};
        final memberId = (data['id'] ?? data['memberId'] ?? '').toString();
        return _ParishionerCard(
          memberId: memberId,
          data: data,
          onView: () => _viewParishionerDetails(context, memberId, data),
          onEdit: () => _editParishioner(context, memberId, data),
        );
      },
    );
  }

  Future<void> _showFilterDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Parishioners'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String?>(
              value: _selectedSacramentStatus,
              decoration: const InputDecoration(labelText: 'Sacrament Status'),
              items: const [
                DropdownMenuItem(value: null, child: Text('All')),
                DropdownMenuItem(value: 'baptized', child: Text('Baptized')),
                DropdownMenuItem(value: 'confirmed', child: Text('Confirmed')),
                DropdownMenuItem(value: 'married', child: Text('Married')),
              ],
              onChanged: (v) => setState(() => _selectedSacramentStatus = v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selectedSacramentStatus = null;
              });
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _viewParishionerDetails(
    BuildContext context,
    String memberId,
    Map<String, dynamic> data,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
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
                        (data['firstName']?.toString().substring(0, 1) ?? '') +
                            (data['lastName']?.toString().substring(0, 1) ??
                                ''),
                        style: const TextStyle(fontSize: 32),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      data['fullName'] ?? 'Unknown',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Chip(
                      label: Text(data['role'] ?? 'Member'),
                      avatar: const Icon(Icons.badge),
                    ),
                  ),
                  const Divider(height: 32),

                  // Personal Information
                  Text(
                    'Personal Information',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InfoRow('Gender', data['gender'] ?? 'Not specified'),
                  _InfoRow(
                    'Civil Status',
                    data['civilStatus'] ?? 'Not specified',
                  ),
                  if (data['birthDate'] != null)
                    _InfoRow('Birth Date', _formatBirthDate(data['birthDate'])),
                  if (data['birthPlace'] != null)
                    _InfoRow('Birth Place', data['birthPlace']),
                  if (data['occupation'] != null)
                    _InfoRow('Occupation', data['occupation']),

                  const SizedBox(height: 24),

                  // Contact Information
                  Text(
                    'Contact Information',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (data['contactNumber'] != null)
                    _InfoRow('Phone', data['contactNumber']),
                  if (data['email'] != null) _InfoRow('Email', data['email']),

                  const SizedBox(height: 24),

                  // Sacrament History
                  Text(
                    'Sacrament History',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSacramentStatus(
                    'Baptism',
                    data['baptismRecordId'] != null,
                    Icons.water,
                    Colors.cyan,
                  ),
                  _buildSacramentStatus(
                    'Confirmation',
                    data['confirmationRecordId'] != null,
                    Icons.church,
                    Colors.purple,
                  ),
                  _buildSacramentStatus(
                    'Marriage',
                    data['marriageRecordId'] != null,
                    Icons.favorite,
                    Colors.pink,
                  ),
                  _buildSacramentStatus(
                    'Death',
                    data['deathRecordId'] != null,
                    Icons.sentiment_very_dissatisfied,
                    Colors.grey,
                  ),

                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _editParishioner(context, memberId, data);
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.print),
                          label: const Text('Print Profile'),
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

  Widget _buildSacramentStatus(
    String label,
    bool completed,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: completed ? color : Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: completed
                  ? color.withValues(alpha: 0.1)
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              completed ? 'Completed' : 'Not Recorded',
              style: TextStyle(
                fontSize: 12,
                color: completed ? color : Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _editParishioner(
    BuildContext context,
    String memberId,
    Map<String, dynamic> data,
  ) {
    // Show edit dialog or navigate to edit page
  }

  String _formatBirthDate(dynamic value) {
    DateTime? dt;
    if (value is DateTime) {
      dt = value;
    } else if (value is int) {
      // millisecondsSinceEpoch
      dt = DateTime.fromMillisecondsSinceEpoch(value);
    } else if (value is String) {
      dt = DateTime.tryParse(value);
    } else if (value is Map) {
      final m = value;
      final seconds = m['seconds'] ?? m['_seconds'];
      final nanos = m['nanoseconds'] ?? m['_nanoseconds'];
      if (seconds is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000 + ((nanos is int) ? (nanos ~/ 1000000) : 0),
        );
      }
    }
    if (dt == null) return 'Not specified';
    return _formatDate(dt);
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
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
    return Expanded(
      child: Column(
        children: [
          Text(
            count,
            style: TextStyle(
              fontSize: 20,
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
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

class _ParishionerCard extends StatelessWidget {
  final String memberId;
  final Map<String, dynamic> data;
  final VoidCallback onView;
  final VoidCallback onEdit;

  const _ParishionerCard({
    required this.memberId,
    required this.data,
    required this.onView,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['fullName'] ?? 'Unknown';
    final role = data['role'] ?? 'Member';
    final initials =
        (data['firstName']?.toString().substring(0, 1) ?? '') +
        (data['lastName']?.toString().substring(0, 1) ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(child: Text(initials)),
        title: Text(name),
        subtitle: Row(
          children: [
            Text(role),
            const SizedBox(width: 8),
            if (data['baptismRecordId'] != null)
              _SacramentBadge(icon: Icons.water, color: Colors.cyan),
            if (data['confirmationRecordId'] != null)
              _SacramentBadge(icon: Icons.church, color: Colors.purple),
            if (data['marriageRecordId'] != null)
              _SacramentBadge(icon: Icons.favorite, color: Colors.pink),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'view') onView();
            if (value == 'edit') onEdit();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'view', child: Text('View Details')),
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
          ],
        ),
        onTap: onView,
      ),
    );
  }
}

class _SacramentBadge extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _SacramentBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Icon(icon, size: 14, color: color),
    );
  }
}
