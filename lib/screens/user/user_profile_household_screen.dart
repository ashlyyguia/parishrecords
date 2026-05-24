// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../providers/user_providers.dart';
import '../../providers/household_provider.dart';
import '../../providers/notification_provider.dart';
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
  // Personal Info / Head of Family
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String? _gender;
  DateTime? _dateOfBirth;
  String? _civilStatus;

  // Household Info
  final _householdNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _householdContactCtrl = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _consent = false;
  bool _saving = false;
  bool _initialized = false;
  Household? _household;
  String? _linkedHouseholdId;
  List<HouseholdMember> _members = [];
  List<Map<String, dynamic>> _sacraments = const [];
  List<Map<String, dynamic>> _requests = const [];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _householdNameCtrl.dispose();
    _addressCtrl.dispose();
    _barangayCtrl.dispose();
    _householdContactCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    final formOk = _formKey.currentState?.validate() ?? true;
    if (!formOk) return;

    setState(() => _saving = true);
    debugPrint('[Profile Save] Household data: $_household');
    try {
      final repo = ref.read(householdRepositoryProvider);

      // Create or update household in households collection
      final headName = _nameCtrl.text.trim();
      final headMeta = <String, dynamic>{
        if (_household != null) ..._household!.metadata,
        if (headName.isNotEmpty) 'headOfFamilyName': headName,
      };

      Household householdToSave;
      if (_linkedHouseholdId != null && _household != null) {
        // Update existing household
        householdToSave = _household!.copyWith(
          familyName: _householdNameCtrl.text.trim().isNotEmpty
              ? _householdNameCtrl.text.trim()
              : _nameCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          barangay: _barangayCtrl.text.trim(),
          contactNumber: _householdContactCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          metadata: headMeta,
          updatedAt: DateTime.now(),
        );
        await repo.updateHousehold(householdToSave);
      } else {
        // Create new household
        final householdId = await repo.generateHouseholdId();
        householdToSave = Household(
          id: '', // Will be set by Firestore
          householdId: householdId,
          familyName: _householdNameCtrl.text.trim().isNotEmpty
              ? _householdNameCtrl.text.trim()
              : _nameCtrl.text.trim(),
          headOfFamilyId: '',
          address: _addressCtrl.text.trim(),
          barangay: _barangayCtrl.text.trim(),
          city: '',
          contactNumber: _householdContactCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          metadata: headMeta,
          registeredAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final createdHousehold = await repo.createHousehold(householdToSave);
        _linkedHouseholdId = createdHousehold.id;
        _household = createdHousehold;
        householdToSave = createdHousehold;
      }

      // Update user profile with household info
      await ref.read(userProfileRepositoryProvider).updateMyProfile({
        'displayName': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'gender': _gender,
        'dateOfBirth': _dateOfBirth?.toIso8601String(),
        'civilStatus': _civilStatus,
        'address': _addressCtrl.text.trim(),
        'householdName': _householdNameCtrl.text.trim(),
        'barangay': _barangayCtrl.text.trim(),
        'householdContact': _householdContactCtrl.text.trim(),
        'linkedHouseholdId': _linkedHouseholdId,
        'household': householdToSave.toFirestore(),
        'privacy_consent': _consent,
      });

      ref.invalidate(myProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile and household updated.')),
        );
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

  String _linkedSacramentsMessage(HouseholdMember? member) {
    if (member == null) return '';
    final linked = <String>[];
    if (member.baptismRecordId != null && member.baptismRecordId!.isNotEmpty) {
      linked.add('Baptism');
    }
    if (member.confirmationRecordId != null &&
        member.confirmationRecordId!.isNotEmpty) {
      linked.add('Confirmation');
    }
    if (member.marriageRecordId != null && member.marriageRecordId!.isNotEmpty) {
      linked.add('Marriage');
    }
    if (member.deathRecordId != null && member.deathRecordId!.isNotEmpty) {
      linked.add('Death');
    }
    if (linked.isEmpty) {
      final meta = member.metadata['autoLinkedSacraments'];
      if (meta is Map) {
        var bestScore = 0;
        String? bestName;
        for (final key in ['baptism', 'confirmation', 'marriage', 'funeral']) {
          final entry = meta[key];
          if (entry is Map) {
            final score = (entry['score'] as num?)?.toInt() ?? 0;
            if (score > bestScore) {
              bestScore = score;
              bestName = entry['matchedName']?.toString();
            }
          }
        }
        if (bestScore >= 50 && bestName != null && bestName.isNotEmpty) {
          return ' Closest parish match was "$bestName" (not linked — try the exact spelling from the register).';
        }
      }
      return ' No matching parish records were found automatically.';
    }
    return ' Linked sacrament record(s): ${linked.join(', ')}.';
  }

  Future<void> _openMemberDialog({HouseholdMember? initial, int? index}) async {
    final firstNameCtrl = TextEditingController(text: initial?.firstName ?? '');
    final contactCtrl = TextEditingController(
      text: initial?.contactNumber ?? '',
    );

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
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.link_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'After saving, we automatically search parish '
                              'records (baptism, confirmation, marriage, death) '
                              'and link matches by name and birth date.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Relationship *',
                        prefixIcon: Icon(Icons.family_restroom_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Head', child: Text('Head')),
                        DropdownMenuItem(
                          value: 'Spouse',
                          child: Text('Spouse'),
                        ),
                        DropdownMenuItem(
                          value: 'Father',
                          child: Text('Father'),
                        ),
                        DropdownMenuItem(
                          value: 'Mother',
                          child: Text('Mother'),
                        ),
                        DropdownMenuItem(value: 'Son', child: Text('Son')),
                        DropdownMenuItem(
                          value: 'Daughter',
                          child: Text('Daughter'),
                        ),
                        DropdownMenuItem(value: 'Child', child: Text('Child')),
                        DropdownMenuItem(
                          value: 'Brother',
                          child: Text('Brother'),
                        ),
                        DropdownMenuItem(
                          value: 'Sister',
                          child: Text('Sister'),
                        ),
                        DropdownMenuItem(
                          value: 'Grandparent',
                          child: Text('Grandparent'),
                        ),
                        DropdownMenuItem(
                          value: 'Relative',
                          child: Text('Relative'),
                        ),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (v) => setDialogState(() => selectedRole = v!),
                    ),
                    const SizedBox(height: 12),
                    // Full Name (single field)
                    TextFormField(
                      controller: firstNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                        hintText: 'Enter complete name',
                      ),
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
                      items: const [
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(
                          value: 'Female',
                          child: Text('Female'),
                        ),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => selectedGender = v!),
                    ),
                    const SizedBox(height: 12),
                    // Date of Birth
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
                          labelText: 'Date of Birth',
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
                    // Civil Status
                    DropdownButtonFormField<String>(
                      value: selectedCivilStatus,
                      decoration: const InputDecoration(
                        labelText: 'Civil Status',
                        prefixIcon: Icon(Icons.favorite_border),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Single',
                          child: Text('Single'),
                        ),
                        DropdownMenuItem(
                          value: 'Married',
                          child: Text('Married'),
                        ),
                        DropdownMenuItem(
                          value: 'Widowed',
                          child: Text('Widowed'),
                        ),
                        DropdownMenuItem(
                          value: 'Separated',
                          child: Text('Separated'),
                        ),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => selectedCivilStatus = v!),
                    ),
                    const SizedBox(height: 12),
                    // Contact Number
                    TextFormField(
                      controller: contactCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Contact Number',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
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
                    final fullName = firstNameCtrl.text.trim();
                    if (fullName.isEmpty) return;

                    // Split full name into first and last name
                    final nameParts = fullName.split(' ');
                    final firstName = nameParts.first;
                    final lastName = nameParts.length > 1 ? nameParts.last : '';

                    final member = HouseholdMember(
                      id: initial?.id ?? '',
                      householdId: _linkedHouseholdId ?? '',
                      firstName: firstName,
                      middleName: '',
                      lastName: lastName,
                      suffix: '',
                      fullName: fullName,
                      role: selectedRole,
                      gender: selectedGender,
                      civilStatus: selectedCivilStatus,
                      birthDate: birthDate,
                      birthPlace: '',
                      occupation: '',
                      contactNumber: contactCtrl.text.trim(),
                      email: '',
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
      HouseholdMember? savedMember;
      if (index == null) {
        savedMember = await repo.addMember(saved);

        if (_linkedHouseholdId != null &&
            _household != null &&
            _household!.headOfFamilyId.isEmpty) {
          final role = savedMember.role.trim().toLowerCase();
          if (role.contains('head') ||
              role == 'father' ||
              role == 'mother' ||
              role == 'parent') {
            await repo.setHeadOfFamily(
              _linkedHouseholdId!,
              savedMember.id,
              headName: savedMember.fullName,
            );
          }
        }

        // Send system notification to the user
        try {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) {
            await ref
                .read(notificationsRepositoryProvider)
                .createSystemNotification(
                  title: 'Household Member Added',
                  body:
                      '${saved.firstName} ${saved.lastName} has been successfully added to your household.',
                  userId: uid,
                  type: 'household',
                  route: '/user/profile',
                );
            // Invalidate notifications provider to update the bell immediately
            ref.invalidate(notificationsProvider);
          }
        } catch (e) {
          debugPrint('Failed to create notification: $e');
        }
      } else if (initial != null) {
        await repo.updateMember(saved);
        savedMember = await repo.getMember(saved.id);
      }

      // Refresh members list
      if (_linkedHouseholdId != null) {
        final members = await repo.getHouseholdMembers(_linkedHouseholdId!);
        setState(() => _members = members);
      }

      if (mounted) {
        final linkMsg = _linkedSacramentsMessage(savedMember);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              index == null
                  ? 'Member added.$linkMsg'
                  : 'Member updated.$linkMsg',
            ),
          ),
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

  Widget _buildMembersCard(ThemeData theme, ColorScheme cs) {
    return _ProfileSectionCard(
      icon: Icons.people_alt_rounded,
      iconColor: Colors.teal,
      title: 'Household members',
      subtitle: _members.isEmpty
          ? 'Add family members linked to your household'
          : '${_members.length} member${_members.length == 1 ? '' : 's'}',
      child: Column(
        children: [
          if (_members.isEmpty)
            _ProfileEmptyHint(
              icon: Icons.people_outline_rounded,
              message: 'No household members yet',
            )
          else
            ...List.generate(_members.length, (i) {
              final member = _members[i];
              final name = member.fullName;
              final relationship = member.role;
              final birthDate = member.birthDate != null
                  ? DateFormat.yMMMd().format(member.birthDate!)
                  : '';
              final avatarColor = _ProfileUi.avatarColor(name);

              return Padding(
                padding: EdgeInsets.only(bottom: i < _members.length - 1 ? 8 : 0),
                child: _MemberTile(
                  name: name,
                  subtitle: [relationship, birthDate]
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  avatarColor: avatarColor,
                  onSacraments: () => _viewMemberSacraments(member.toJson()),
                  onEdit: () => _openMemberDialog(initial: member, index: i),
                  onRemove: () => _removeMember(i),
                ),
              );
            }),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _members.length >= 20 ? null : () => _openMemberDialog(),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
            label: const Text('Add member'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
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

  List<Map<String, dynamic>> _normalizeSacraments(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  List<Map<String, dynamic>> _normalizeRequests(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
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

  String? _phoneValidator(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return null;
    final ok = RegExp(r'^[0-9+()\-\s]{7,}$').hasMatch(value);
    if (!ok) return 'Please enter a valid contact number';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final async = ref.watch(myProfileProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: async.when(
        data: (m) {
          if (!_initialized) {
            _initialized = true;
            _nameCtrl.text = (m['displayName'] ?? '').toString();
            _phoneCtrl.text = (m['phone'] ?? '').toString();
            _emailCtrl.text = (m['email'] ?? '').toString();
            _gender = m['gender']?.toString();
            _dateOfBirth = m['dateOfBirth'] != null
                ? DateTime.tryParse(m['dateOfBirth'].toString())
                : null;
            _civilStatus = m['civilStatus']?.toString();
            _householdNameCtrl.text = (m['householdName'] ?? '').toString();
            _addressCtrl.text = (m['address'] ?? '').toString();
            _barangayCtrl.text = (m['barangay'] ?? '').toString();
            _householdContactCtrl.text =
                (m['householdContact'] ?? '').toString();
            _consent = (m['privacy_consent'] == true);
            _loadLinkedHousehold().then((_) {
              if (mounted) setState(() {});
            });
            _sacraments = _normalizeSacraments(m['sacraments']);
            _requests = _normalizeRequests(m['requests']);
          }

          final displayName = _nameCtrl.text.trim().isNotEmpty
              ? _nameCtrl.text.trim()
              : 'Parishioner';
          final email = _emailCtrl.text.trim().isNotEmpty
              ? _emailCtrl.text.trim()
              : (m['email'] ?? '').toString();

          return Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      setState(() => _initialized = false);
                      ref.invalidate(myProfileProvider);
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                      children: [
                        _ProfileHeroHeader(
                          name: displayName,
                          email: email,
                          memberCount: _members.length,
                          householdName: _householdNameCtrl.text.trim(),
                          onRefresh: () {
                            setState(() => _initialized = false);
                            ref.invalidate(myProfileProvider);
                          },
                        ),
                        const SizedBox(height: 20),
                        _ProfileSectionCard(
                          icon: Icons.person_rounded,
                          iconColor: cs.primary,
                          title: 'Personal information',
                          subtitle: 'Head of family details',
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _nameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Full name *',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                textInputAction: TextInputAction.next,
                                validator: (v) {
                                  final value = (v ?? '').trim();
                                  if (value.isEmpty) {
                                    return 'Full name is required';
                                  }
                                  if (value.length < 2) {
                                    return 'Please enter a valid name';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: _gender,
                                      decoration: const InputDecoration(
                                        labelText: 'Gender',
                                        prefixIcon: Icon(Icons.wc_outlined),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'Male',
                                          child: Text('Male'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'Female',
                                          child: Text('Female'),
                                        ),
                                      ],
                                      onChanged: (v) =>
                                          setState(() => _gender = v),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: _civilStatus,
                                      decoration: const InputDecoration(
                                        labelText: 'Civil status',
                                        prefixIcon:
                                            Icon(Icons.favorite_border),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'Single',
                                          child: Text('Single'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'Married',
                                          child: Text('Married'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'Widowed',
                                          child: Text('Widowed'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'Separated',
                                          child: Text('Separated'),
                                        ),
                                      ],
                                      onChanged: (v) =>
                                          setState(() => _civilStatus = v),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _DatePickerField(
                                label: 'Date of birth',
                                value: _dateOfBirth,
                                onPick: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _dateOfBirth ?? DateTime(1990),
                                    firstDate: DateTime(1900),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setState(() => _dateOfBirth = picked);
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _phoneCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Contact number',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                ),
                                keyboardType: TextInputType.phone,
                                validator: _phoneValidator,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _emailCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                keyboardType: TextInputType.emailAddress,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _ProfileSectionCard(
                          icon: Icons.home_work_rounded,
                          iconColor: Colors.orange.shade700,
                          title: 'Household information',
                          subtitle: 'Address and parish registration',
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _householdNameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Household name',
                                  prefixIcon: Icon(Icons.family_restroom),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _addressCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Address',
                                  prefixIcon: Icon(Icons.location_on_outlined),
                                ),
                                maxLines: 2,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _barangayCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Barangay',
                                        prefixIcon:
                                            Icon(Icons.map_outlined),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _householdContactCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Household contact',
                                        prefixIcon: Icon(Icons.call_outlined),
                                      ),
                                      keyboardType: TextInputType.phone,
                                      validator: _phoneValidator,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildMembersCard(theme, cs),
                        const SizedBox(height: 16),
                        _ProfileSectionCard(
                          icon: Icons.privacy_tip_outlined,
                          iconColor: Colors.blueGrey,
                          title: 'Privacy',
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _consent,
                            onChanged: (v) => setState(() => _consent = v),
                            title: const Text(
                              'Data processing consent',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Allow the parish to store and process my data for parish services.',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _ProfileSaveBar(saving: _saving, onSave: _save),
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
                Icon(Icons.error_outline, size: 56, color: cs.error),
                const SizedBox(height: 12),
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
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    setState(() => _initialized = false);
                    ref.invalidate(myProfileProvider);
                  },
                  icon: const Icon(Icons.refresh_rounded),
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

// ── Profile UI components ─────────────────────────────────────────────────────

class _ProfileUi {
  static const _avatarColors = [
    Color(0xFF6C63FF),
    Color(0xFF26A69A),
    Color(0xFFFF7043),
    Color(0xFF7E57C2),
    Color(0xFF42A5F5),
    Color(0xFFEC407A),
  ];

  static Color avatarColor(String name) =>
      _avatarColors[name.hashCode.abs() % _avatarColors.length];
}

class _ProfileHeroHeader extends StatelessWidget {
  const _ProfileHeroHeader({
    required this.name,
    required this.email,
    required this.memberCount,
    required this.householdName,
    required this.onRefresh,
  });

  final String name;
  final String email;
  final int memberCount;
  final String householdName;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.92),
            const Color(0xFF8B83FF),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
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
                        'My Profile',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                      tooltip: 'Refresh',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                Text(
                  name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _HeroChip(
                      icon: Icons.people_rounded,
                      label: '$memberCount members',
                    ),
                    if (householdName.isNotEmpty)
                      _HeroChip(
                        icon: Icons.home_rounded,
                        label: householdName,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSectionCard extends StatelessWidget {
  const _ProfileSectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final text = value != null ? DateFormat.yMMMd().format(value!) : 'Select date';

    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          suffixIcon: const Icon(Icons.chevron_right_rounded),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: value != null ? null : Theme.of(context).hintColor,
          ),
        ),
      ),
    );
  }
}

class _ProfileEmptyHint extends StatelessWidget {
  const _ProfileEmptyHint({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(icon, size: 40, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.name,
    required this.subtitle,
    required this.avatarColor,
    required this.onSacraments,
    required this.onEdit,
    required this.onRemove,
  });

  final String name;
  final String subtitle;
  final Color avatarColor;
  final VoidCallback onSacraments;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: avatarColor.withValues(alpha: 0.15),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: avatarColor,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sacraments',
            onPressed: onSacraments,
            icon: Icon(Icons.church_outlined, color: Colors.purple.shade400, size: 20),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: onEdit,
            icon: Icon(Icons.edit_outlined, color: cs.primary, size: 20),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: Icon(Icons.delete_outline, color: cs.error, size: 20),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _ProfileSaveBar extends StatelessWidget {
  const _ProfileSaveBar({required this.saving, required this.onSave});
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: FilledButton(
          onPressed: saving ? null : onSave,
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save profile'),
        ),
      ),
    );
  }
}
