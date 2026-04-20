// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth_provider.dart';
import '../../providers/user_providers.dart';
import '../../providers/household_provider.dart';
import '../../models/household.dart';
import '../../widgets/app_loading.dart';

class UserProfileHouseholdScreen extends ConsumerStatefulWidget {
  const UserProfileHouseholdScreen({super.key});

  @override
  ConsumerState<UserProfileHouseholdScreen> createState() =>
      _UserProfileHouseholdScreenState();
}

class _UserProfileHouseholdScreenState
    extends ConsumerState<UserProfileHouseholdScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _consent = false;
  bool _saving = false;
  bool _initialized = false;
  bool _sendingMessage = false;
  Household? _household;
  String? _linkedHouseholdId;
  List<HouseholdMember> _members = [];
  List<Map<String, dynamic>> _sacraments = const [];
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _activities = const [];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    final formOk = _formKey.currentState?.validate() ?? true;
    if (!formOk) return;

    setState(() => _saving = true);
    debugPrint('[Profile Save] Household data: $_household');
    try {
      await ref.read(userProfileRepositoryProvider).updateMyProfile({
        'displayName': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'household': _household,
        'privacy_consent': _consent,
      });
      ref.invalidate(myProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadLinkedHousehold() async {
    try {
      // First get user's linked household ID from profile
      final profile = await ref
          .read(userProfileRepositoryProvider)
          .getMyProfile();
      _linkedHouseholdId = profile['linkedHouseholdId'] as String?;

      if (_linkedHouseholdId != null && _linkedHouseholdId!.isNotEmpty) {
        // Load household details
        final repo = ref.read(householdRepositoryProvider);
        _household = await repo.getHousehold(_linkedHouseholdId!);

        // Load members from household_members collection
        _members = await repo.getHouseholdMembers(_linkedHouseholdId!);
      }
    } catch (e) {
      debugPrint('Error loading linked household: $e');
    }
  }

  Future<void> _openMemberDialog({HouseholdMember? initial, int? index}) async {
    final firstNameCtrl = TextEditingController(text: initial?.firstName ?? '');
    final middleNameCtrl = TextEditingController(
      text: initial?.middleName ?? '',
    );
    final lastNameCtrl = TextEditingController(text: initial?.lastName ?? '');
    final suffixCtrl = TextEditingController(text: initial?.suffix ?? '');
    final birthPlaceCtrl = TextEditingController(
      text: initial?.birthPlace ?? '',
    );
    final occupationCtrl = TextEditingController(
      text: initial?.occupation ?? '',
    );
    final contactCtrl = TextEditingController(
      text: initial?.contactNumber ?? '',
    );
    final emailCtrl = TextEditingController(text: initial?.email ?? '');

    String selectedRole = initial?.role ?? 'Child';
    String selectedGender = initial?.gender ?? 'Male';
    String selectedCivilStatus = initial?.civilStatus ?? 'Single';
    DateTime? birthDate = initial?.birthDate;

    final saved = await showDialog<HouseholdMember?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                index == null
                    ? 'Add household member'
                    : 'Edit household member',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Role Dropdown
                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Role in Family *',
                        prefixIcon: Icon(Icons.family_restroom_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items:
                          [
                                'Father',
                                'Mother',
                                'Son',
                                'Daughter',
                                'Grandfather',
                                'Grandmother',
                                'Other',
                              ]
                              .map(
                                (r) =>
                                    DropdownMenuItem(value: r, child: Text(r)),
                              )
                              .toList(),
                      onChanged: (v) => setDialogState(() => selectedRole = v!),
                    ),
                    const SizedBox(height: 12),
                    // First Name
                    TextFormField(
                      controller: firstNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'First Name *',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Middle Name
                    TextFormField(
                      controller: middleNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Middle Name',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: lastNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Last Name *',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: suffixCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Suffix',
                              hintText: 'Jr, Sr',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Gender Dropdown
                    DropdownButtonFormField<String>(
                      value: selectedGender,
                      decoration: const InputDecoration(
                        labelText: 'Gender *',
                        prefixIcon: Icon(Icons.wc_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: ['Male', 'Female']
                          .map(
                            (g) => DropdownMenuItem(value: g, child: Text(g)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedGender = v!),
                    ),
                    const SizedBox(height: 12),
                    // Civil Status
                    DropdownButtonFormField<String>(
                      value: selectedCivilStatus,
                      decoration: const InputDecoration(
                        labelText: 'Civil Status',
                        prefixIcon: Icon(Icons.favorite_border),
                        border: OutlineInputBorder(),
                      ),
                      items:
                          [
                                'Single',
                                'Married',
                                'Widowed',
                                'Separated',
                                'Divorced',
                              ]
                              .map(
                                (s) =>
                                    DropdownMenuItem(value: s, child: Text(s)),
                              )
                              .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedCivilStatus = v!),
                    ),
                    const SizedBox(height: 12),
                    // Birth Date
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: birthDate ?? DateTime(2000),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => birthDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Birth Date',
                          prefixIcon: Icon(Icons.cake_outlined),
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          birthDate != null
                              ? '${birthDate!.month}/${birthDate!.day}/${birthDate!.year}'
                              : 'Select Date',
                          style: TextStyle(
                            color: birthDate != null
                                ? Theme.of(context).textTheme.bodyLarge?.color
                                : Theme.of(context).textTheme.bodyMedium?.color
                                      ?.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Birth Place
                    TextFormField(
                      controller: birthPlaceCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Birth Place',
                        prefixIcon: Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Occupation
                    TextFormField(
                      controller: occupationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Occupation',
                        prefixIcon: Icon(Icons.work_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Contact
                    TextFormField(
                      controller: contactCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Contact Number',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    // Email
                    TextFormField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
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
                    final firstName = firstNameCtrl.text.trim();
                    final lastName = lastNameCtrl.text.trim();
                    if (firstName.isEmpty || lastName.isEmpty) return;

                    final fullName = HouseholdMember.generateFullName(
                      firstName,
                      middleNameCtrl.text.trim(),
                      lastName,
                      suffixCtrl.text.trim(),
                    );

                    final member = HouseholdMember(
                      id: initial?.id ?? '',
                      householdId: _linkedHouseholdId ?? '',
                      firstName: firstName,
                      middleName: middleNameCtrl.text.trim(),
                      lastName: lastName,
                      suffix: suffixCtrl.text.trim(),
                      fullName: fullName,
                      role: selectedRole,
                      gender: selectedGender,
                      civilStatus: selectedCivilStatus,
                      birthDate: birthDate,
                      birthPlace: birthPlaceCtrl.text.trim(),
                      occupation: occupationCtrl.text.trim(),
                      contactNumber: contactCtrl.text.trim(),
                      email: emailCtrl.text.trim(),
                      dateAdded: initial?.dateAdded ?? DateTime.now(),
                      isActive: true,
                    );
                    Navigator.pop(context, member);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == null) return;

    // Save to household_members collection via repository
    try {
      final repo = ref.read(householdRepositoryProvider);
      if (index == null) {
        // Add new member
        await repo.addMember(saved);
      } else if (initial != null) {
        // Update existing
        await repo.updateMember(saved);
      }

      // Refresh members list
      if (_linkedHouseholdId != null) {
        final members = await repo.getHouseholdMembers(_linkedHouseholdId!);
        setState(() => _members = members);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving member: $e')));
      }
    }
  }

  Widget _buildStatsCard(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.3),
            colorScheme.secondaryContainer.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics_outlined,
                color: colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Household Stats',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  icon: Icons.people_outline,
                  value: '${_members.length}',
                  label: 'Members',
                  color: Colors.blue,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              Expanded(
                child: _StatItem(
                  icon: Icons.pending_actions_outlined,
                  value:
                      '${_requests.where((r) => r['status']?.toString().toLowerCase() == 'pending').length}',
                  label: 'Pending',
                  color: Colors.orange,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              Expanded(
                child: _StatItem(
                  icon: Icons.verified_outlined,
                  value:
                      '${_sacraments.where((s) => s['status']?.toString().toLowerCase() == 'completed').length}',
                  label: 'Sacraments',
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMembersCard(ThemeData theme, ColorScheme colorScheme) {
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
                Icon(
                  Icons.people_alt_outlined,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Household Members',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (_members.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_members.length}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_members.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 48,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No household members added yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...List.generate(_members.length, (i) {
                final member = _members[i];
                final name = member.fullName;
                final relationship = member.role;
                final birthDate = member.birthDate != null
                    ? '${member.birthDate!.month}/${member.birthDate!.day}/${member.birthDate!.year}'
                    : '';

                // Generate avatar color based on name
                final colors = [
                  Colors.blue,
                  Colors.green,
                  Colors.orange,
                  Colors.purple,
                  Colors.teal,
                  Colors.pink,
                ];
                final avatarColor = colors[name.hashCode.abs() % colors.length];

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            avatarColor.withValues(alpha: 0.8),
                            avatarColor,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: relationship.isEmpty && birthDate.isEmpty
                        ? null
                        : Text(
                            [
                              relationship,
                              birthDate,
                            ].where((s) => s.isNotEmpty).join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'View Sacraments',
                          onPressed: () =>
                              _viewMemberSacraments(member.toJson()),
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.church_outlined,
                              color: Colors.purple,
                              size: 18,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit',
                          onPressed: () =>
                              _openMemberDialog(initial: member, index: i),
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.edit_outlined,
                              color: colorScheme.primary,
                              size: 18,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () => _removeMember(i),
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.delete_outline,
                              color: colorScheme.error,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _members.length >= 20
                    ? null
                    : () => _openMemberDialog(),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Add member'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _removeMember(int index) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove member'),
        content: const Text('Remove this household member?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed != true || !mounted) return;
      // Delete member via repository
      _deleteMember(index);
    });
  }

  Future<void> _deleteMember(int index) async {
    if (_linkedHouseholdId == null || index >= _members.length) return;

    final member = _members[index];
    try {
      final repo = ref.read(householdRepositoryProvider);
      await repo.deleteMember(member.id);

      // Refresh members list
      final members = await repo.getHouseholdMembers(_linkedHouseholdId!);
      setState(() => _members = members);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member removed successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error removing member: $e')));
      }
    }
  }

  Future<void> _export() async {
    try {
      final resp = await ref.read(userProfileRepositoryProvider).exportMyData();
      final file = resp['file'] is Map ? (resp['file'] as Map) : const {};
      final url = (file['download_url'] ?? '').toString();
      final name = (file['name'] ?? 'export.json').toString();
      if (url.isEmpty) throw Exception('Missing download url');

      if (kIsWeb && url.startsWith('data:')) {
        (html.AnchorElement(href: url)..setAttribute('download', name)).click();
      } else {
        final uri = Uri.tryParse(url);
        if (uri == null) throw Exception('Invalid download url');
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok) throw Exception('Could not open export link');
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Export generated.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  List<Map<String, dynamic>> _normalizeSacraments(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  List<Map<String, dynamic>> _normalizeRequests(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  List<Map<String, dynamic>> _generateActivities() {
    final activities = <Map<String, dynamic>>[];

    for (final s in _sacraments) {
      activities.add({
        'type': 'sacrament',
        'title': s['type']?.toString() ?? 'Sacrament',
        'date': s['date']?.toString() ?? '',
        'status': s['status']?.toString() ?? 'completed',
        'icon': Icons.church_outlined,
        'color': Colors.purple,
      });
    }

    for (final r in _requests) {
      activities.add({
        'type': 'request',
        'title': r['title']?.toString() ?? 'Request',
        'date': r['submittedAt']?.toString() ?? '',
        'status': r['status']?.toString() ?? 'pending',
        'icon': Icons.assignment_outlined,
        'color': _getStatusColor(r['status']?.toString() ?? 'pending'),
      });
    }

    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
      if (v is DateTime) return v;
      final s = v.toString();
      return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    activities.sort(
      (a, b) => parseDate(b['date']).compareTo(parseDate(a['date'])),
    );
    return activities.take(10).toList();
  }

  Color _getStatusColor(String status) {
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
      default:
        return Colors.orange;
    }
  }

  Future<void> _sendMessage() async {
    if (_sendingMessage || _messageCtrl.text.trim().isEmpty) return;

    if (_nameCtrl.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your full name first.')),
        );
      }
      return;
    }

    setState(() => _sendingMessage = true);

    try {
      final auth = ref.read(authProvider);
      final user = auth.user;

      await ref.read(userRequestsRepositoryProvider).createRequest({
        'type': 'parish_message',
        'subject': 'Message from Household: ${_nameCtrl.text.trim()}',
        'message': _messageCtrl.text.trim(),
        'senderInfo': {
          'name': _nameCtrl.text.trim(),
          'email': user?.email ?? '',
          'phone': _phoneCtrl.text.trim(),
          'address': _addressCtrl.text.trim(),
          'householdCount': _members.length,
        },
        'submittedAt': DateTime.now().toIso8601String(),
        'status': 'pending',
      });

      _messageCtrl.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Message sent to parish office. We\'ll respond soon!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    } finally {
      if (mounted) setState(() => _sendingMessage = false);
    }
  }

  Future<void> _viewMemberSacraments(Map<String, dynamic> member) async {
    final memberName = member['name']?.toString() ?? 'Member';
    final memberSacraments = _sacraments.where((s) {
      final sName = s['recipientName']?.toString().toLowerCase() ?? '';
      return sName == memberName.toLowerCase();
    }).toList();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$memberName\'s Sacraments'),
        content: SizedBox(
          width: double.maxFinite,
          child: memberSacraments.isEmpty
              ? const Text('No sacrament records found for this member.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: memberSacraments.length,
                  itemBuilder: (context, i) {
                    final s = memberSacraments[i];
                    return ListTile(
                      leading: const Icon(
                        Icons.church_outlined,
                        color: Colors.purple,
                      ),
                      title: Text(s['type']?.toString() ?? 'Sacrament'),
                      subtitle: Text(s['date']?.toString() ?? 'Date unknown'),
                      trailing: Chip(
                        label: Text(
                          s['status']?.toString() ?? 'completed',
                          style: const TextStyle(fontSize: 12),
                        ),
                        backgroundColor: _getStatusColor(
                          s['status']?.toString() ?? 'completed',
                        ).withValues(alpha: 0.2),
                        side: BorderSide.none,
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final async = ref.watch(myProfileProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('My Profile & Household'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              setState(() => _initialized = false);
              ref.invalidate(myProfileProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: async.when(
        data: (m) {
          if (!_initialized) {
            _initialized = true;
            _nameCtrl.text = (m['displayName'] ?? '').toString();
            _phoneCtrl.text = (m['phone'] ?? '').toString();
            _addressCtrl.text = (m['address'] ?? '').toString();
            _consent = (m['privacy_consent'] == true);
            // Load linked household from collection
            _loadLinkedHousehold().then((_) => setState(() {}));
            _sacraments = _normalizeSacraments(m['sacraments']);
            _requests = _normalizeRequests(m['requests']);
            _activities = _generateActivities();
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Personal Info',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return 'Full name is required';
                            if (value.length < 2)
                              return 'Please enter a valid name';
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _phoneCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Contact number',
                          ),
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.phone,
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return null;
                            // Basic sanity check: allow digits + common phone symbols
                            final ok = RegExp(
                              r'^[0-9+()\-\s]{7,}$',
                            ).hasMatch(value);
                            if (!ok)
                              return 'Please enter a valid contact number';
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _addressCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Address',
                          ),
                          maxLines: 2,
                          textInputAction: TextInputAction.newline,
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _consent,
                          onChanged: (v) => setState(() => _consent = v),
                          title: const Text('Privacy consent'),
                          subtitle: const Text(
                            'Allow the parish to store and process my data for parish services.',
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save changes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Quick Stats Card
                _buildStatsCard(theme, colorScheme),
                const SizedBox(height: 16),
                // Household Members Card
                _buildMembersCard(theme, colorScheme),
                const SizedBox(height: 12),
                // Activity History Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Recent Activity',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_activities.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  // Navigate to full activity history
                                },
                                child: const Text('View all'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_activities.isEmpty)
                          Text(
                            'No recent activity.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _activities.length > 5
                                ? 5
                                : _activities.length,
                            itemBuilder: (context, i) {
                              final activity = _activities[i];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (activity['color'] as Color)
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    activity['icon'] as IconData,
                                    color: activity['color'] as Color,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  activity['title']?.toString() ?? '',
                                ),
                                subtitle: Text(
                                  activity['date']?.toString() ?? '',
                                ),
                                trailing: Chip(
                                  label: Text(
                                    activity['status']?.toString() ?? '',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  backgroundColor: (activity['color'] as Color)
                                      .withValues(alpha: 0.1),
                                  side: BorderSide.none,
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Direct Messaging Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Message Parish Office',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Send a direct message to the parish office. We\'ll respond as soon as possible.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _messageCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Type your message here...',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                          maxLength: 500,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _sendingMessage ? null : _sendMessage,
                            icon: _sendingMessage
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send_outlined),
                            label: Text(
                              _sendingMessage ? 'Sending...' : 'Send Message',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Data Export',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Request a copy of your data. A file will be generated for download.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: _export,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Generate export'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const AppLoading(message: 'Loading profile...'),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 64, color: colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'Failed to load profile',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(() => _initialized = false);
                    ref.invalidate(myProfileProvider);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
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
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }
}
