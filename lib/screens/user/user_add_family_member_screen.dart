// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../models/household.dart';
import '../../../providers/household_provider.dart';

/// User Add Family Member Screen - adds a new member to the household
class UserAddFamilyMemberScreen extends ConsumerStatefulWidget {
  final String householdId;

  const UserAddFamilyMemberScreen({super.key, required this.householdId});

  @override
  ConsumerState<UserAddFamilyMemberScreen> createState() =>
      _UserAddFamilyMemberScreenState();
}

class _UserAddFamilyMemberScreenState
    extends ConsumerState<UserAddFamilyMemberScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _suffixCtrl = TextEditingController();
  final _birthPlaceCtrl = TextEditingController();
  final _occupationCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  String? _selectedRole;
  String? _selectedGender;
  String? _selectedCivilStatus;
  DateTime? _birthDate;
  bool _isSaving = false;
  int _currentStep = 0;

  final List<String> _roles = [
    'Father',
    'Mother',
    'Son',
    'Daughter',
    'Grandfather',
    'Grandmother',
    'Other',
  ];

  final List<String> _genders = ['Male', 'Female'];

  final List<String> _civilStatuses = [
    'Single',
    'Married',
    'Widowed',
    'Separated',
    'Divorced',
  ];

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

  Future<void> _saveMember() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a role in family')),
      );
      return;
    }
    if (_selectedGender == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a gender')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final fullName = HouseholdMember.generateFullName(
        _firstNameCtrl.text.trim(),
        _middleNameCtrl.text.trim(),
        _lastNameCtrl.text.trim(),
        _suffixCtrl.text.trim(),
      );

      final member = HouseholdMember(
        id: '',
        householdId: widget.householdId,
        firstName: _firstNameCtrl.text.trim(),
        middleName: _middleNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        suffix: _suffixCtrl.text.trim(),
        fullName: fullName,
        role: _selectedRole!,
        gender: _selectedGender!,
        civilStatus: _selectedCivilStatus ?? 'Single',
        birthDate: _birthDate,
        birthPlace: _birthPlaceCtrl.text.trim(),
        occupation: _occupationCtrl.text.trim(),
        contactNumber: _contactCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        dateAdded: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await ref.read(householdRepositoryProvider).addMember(member);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Family member added successfully')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _selectBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _birthDate ?? DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Add Family Member'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Stepper(
          type: StepperType.horizontal,
          currentStep: _currentStep,
          onStepContinue: () {
            if (_currentStep < 2) {
              setState(() => _currentStep++);
            } else {
              _saveMember();
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              context.pop();
            }
          },
          controlsBuilder: (context, details) {
            return Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Row(
                children: [
                  if (_currentStep < 2)
                    Expanded(
                      child: FilledButton(
                        onPressed: details.onStepContinue,
                        child: const Text('Continue'),
                      ),
                    )
                  else
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _saveMember,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_isSaving ? 'Saving...' : 'Save Member'),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: details.onStepCancel,
                      child: Text(_currentStep == 0 ? 'Cancel' : 'Back'),
                    ),
                  ),
                ],
              ),
            );
          },
          steps: [
            Step(
              title: const Text('Info'),
              subtitle: const Text('Basic'),
              isActive: _currentStep >= 0,
              state: _currentStep > 0 ? StepState.complete : StepState.indexed,
              content: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildPersonalInfoStep(theme, colorScheme),
                ),
              ),
            ),
            Step(
              title: const Text('Details'),
              subtitle: const Text('More'),
              isActive: _currentStep >= 1,
              state: _currentStep > 1 ? StepState.complete : StepState.indexed,
              content: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildDetailsStep(theme, colorScheme),
                ),
              ),
            ),
            Step(
              title: const Text('Link'),
              subtitle: const Text('Records'),
              isActive: _currentStep >= 2,
              content: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildSacramentLinkingStep(theme, colorScheme),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalInfoStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Role in Family
        DropdownButtonFormField<String>(
          value: _selectedRole,
          decoration: const InputDecoration(
            labelText: 'Role in Family *',
            prefixIcon: Icon(Icons.family_restroom_outlined),
            border: OutlineInputBorder(),
          ),
          hint: const Text('Select Role'),
          items: _roles
              .map((role) => DropdownMenuItem(value: role, child: Text(role)))
              .toList(),
          onChanged: (val) => setState(() => _selectedRole = val),
          validator: (val) => val == null ? 'Please select a role' : null,
        ),
        const SizedBox(height: 16),

        // First Name
        TextFormField(
          controller: _firstNameCtrl,
          decoration: const InputDecoration(
            labelText: 'First Name *',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'First name is required';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Middle Name
        TextFormField(
          controller: _middleNameCtrl,
          decoration: const InputDecoration(
            labelText: 'Middle Name',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Last Name
        TextFormField(
          controller: _lastNameCtrl,
          decoration: const InputDecoration(
            labelText: 'Last Name *',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Last name is required';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Suffix
        TextFormField(
          controller: _suffixCtrl,
          decoration: const InputDecoration(
            labelText: 'Suffix (Jr., Sr., III, etc.)',
            prefixIcon: Icon(Icons.short_text),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Gender
        DropdownButtonFormField<String>(
          value: _selectedGender,
          decoration: const InputDecoration(
            labelText: 'Gender *',
            prefixIcon: Icon(Icons.wc_outlined),
            border: OutlineInputBorder(),
          ),
          hint: const Text('Select Gender'),
          items: _genders
              .map(
                (gender) =>
                    DropdownMenuItem(value: gender, child: Text(gender)),
              )
              .toList(),
          onChanged: (val) => setState(() => _selectedGender = val),
          validator: (val) => val == null ? 'Please select a gender' : null,
        ),
      ],
    );
  }

  Widget _buildDetailsStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Birth Date
        InkWell(
          onTap: _selectBirthDate,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Birth Date',
              prefixIcon: Icon(Icons.cake_outlined),
              border: OutlineInputBorder(),
            ),
            child: Text(
              _birthDate != null
                  ? '${_birthDate!.month}/${_birthDate!.day}/${_birthDate!.year}'
                  : 'Select Date',
              style: TextStyle(
                color: _birthDate != null
                    ? theme.textTheme.bodyLarge?.color
                    : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Birth Place
        TextFormField(
          controller: _birthPlaceCtrl,
          decoration: const InputDecoration(
            labelText: 'Birth Place',
            prefixIcon: Icon(Icons.location_on_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Civil Status
        DropdownButtonFormField<String>(
          value: _selectedCivilStatus,
          decoration: const InputDecoration(
            labelText: 'Civil Status',
            prefixIcon: Icon(Icons.favorite_border),
            border: OutlineInputBorder(),
          ),
          hint: const Text('Select Status'),
          items: _civilStatuses
              .map(
                (status) =>
                    DropdownMenuItem(value: status, child: Text(status)),
              )
              .toList(),
          onChanged: (val) => setState(() => _selectedCivilStatus = val),
        ),
        const SizedBox(height: 16),

        // Occupation
        TextFormField(
          controller: _occupationCtrl,
          decoration: const InputDecoration(
            labelText: 'Occupation',
            prefixIcon: Icon(Icons.work_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Contact Number
        TextFormField(
          controller: _contactCtrl,
          decoration: const InputDecoration(
            labelText: 'Contact Number',
            prefixIcon: Icon(Icons.phone_outlined),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),

        // Email
        TextFormField(
          controller: _emailCtrl,
          decoration: const InputDecoration(
            labelText: 'Email Address',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
          validator: (val) {
            if (val != null && val.isNotEmpty) {
              final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
              if (!emailRegex.hasMatch(val)) {
                return 'Please enter a valid email';
              }
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildSacramentLinkingStep(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 0,
          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You can link sacrament records after saving the member. Use the OCR feature to scan certificates.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Option 1: Search Existing
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.search, color: colorScheme.primary),
          ),
          title: const Text('Search Existing Record'),
          subtitle: const Text('Find a sacrament record in the system'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // Navigate to search screen
          },
        ),
        const SizedBox(height: 12),

        // Option 2: Scan via OCR
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.document_scanner_outlined,
              color: Colors.purple,
            ),
          ),
          title: const Text('Scan via OCR'),
          subtitle: const Text(
            'Scan a sacramental certificate using your camera',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              context.push('/user/households/${widget.householdId}/ocr-link'),
        ),

        const SizedBox(height: 24),

        Center(
          child: TextButton(
            onPressed: _saveMember,
            child: const Text('Skip for now'),
          ),
        ),
      ],
    );
  }
}
