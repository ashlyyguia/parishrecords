// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../models/household.dart';
import '../../../providers/household_provider.dart';

/// User Add Household Screen - allows users to register a new household
class UserAddHouseholdScreen extends ConsumerStatefulWidget {
  const UserAddHouseholdScreen({super.key});

  @override
  ConsumerState<UserAddHouseholdScreen> createState() =>
      _UserAddHouseholdScreenState();
}

class _UserAddHouseholdScreenState
    extends ConsumerState<UserAddHouseholdScreen> {
  final _formKey = GlobalKey<FormState>();
  final _familyNameCtrl = TextEditingController();
  final _headOfFamilyNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  String? _selectedBarangay;
  bool _isSaving = false;

  final List<String> _barangays = [
    'Poblacion',
    'San Isidro',
    'San Jose',
    'San Juan',
    'San Pedro',
    'San Roque',
    'Santa Cruz',
    'Santa Maria',
  ];

  @override
  void dispose() {
    _familyNameCtrl.dispose();
    _headOfFamilyNameCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveHousehold() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBarangay == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a barangay')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      // headOfFamilyId is a member document ID — it gets assigned after the
      // first member is added and set as head. We store the typed name in
      // metadata so staff can see it while the household is new.
      final headName = _headOfFamilyNameCtrl.text.trim();
      final household = Household(
        id: '',
        householdId: '',
        familyName: _familyNameCtrl.text.trim(),
        headOfFamilyId: '', // assigned later when members are added
        address: _addressCtrl.text.trim(),
        barangay: _selectedBarangay!,
        city: _cityCtrl.text.trim(),
        contactNumber: _contactCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        registeredAt: DateTime.now(),
        metadata: headName.isNotEmpty ? {'headOfFamilyName': headName} : {},
      );

      await ref.read(householdRepositoryProvider).createHousehold(household);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Household registered successfully!')),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              floating: true,
              title: const Text('Add Household'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Card(
                    elevation: 0,
                    color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.add_home_outlined,
                            color: colorScheme.primary,
                            size: 32,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Register New Household',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Enter your household information below',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Household Information',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _familyNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Family Name *',
                              hintText: 'e.g., Dela Cruz Family',
                              prefixIcon: Icon(Icons.home_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Family name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _headOfFamilyNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Head of Family Name *',
                              hintText: 'e.g., Juan Dela Cruz',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                              helperText:
                                  'Full name of the household head',
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Head of family is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _addressCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Address *',
                              hintText: 'Street, Block, Lot, etc.',
                              prefixIcon: Icon(Icons.location_on_outlined),
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 2,
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Address is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _selectedBarangay,
                            decoration: const InputDecoration(
                              labelText: 'Barangay *',
                              prefixIcon: Icon(Icons.map_outlined),
                              border: OutlineInputBorder(),
                            ),
                            hint: const Text('Select Barangay'),
                            items: _barangays
                                .map(
                                  (barangay) => DropdownMenuItem(
                                    value: barangay,
                                    child: Text(barangay),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setState(() => _selectedBarangay = val),
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Please select a barangay';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _cityCtrl,
                            decoration: const InputDecoration(
                              labelText: 'City / Municipality *',
                              hintText: 'e.g., Calamba',
                              prefixIcon: Icon(Icons.location_city_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'City / Municipality is required';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Contact Information',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _contactCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Contact Number',
                              hintText: 'e.g., 09123456789',
                              prefixIcon: Icon(Icons.phone_outlined),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _emailCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Email Address',
                              hintText: 'e.g., family@email.com',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (val) {
                              if (val != null && val.isNotEmpty) {
                                final emailRegex = RegExp(
                                  r'^[^@]+@[^@]+\\.[^@]+',
                                );
                                if (!emailRegex.hasMatch(val)) {
                                  return 'Please enter a valid email';
                                }
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : () => context.pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _saveHousehold,
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
                  label: Text(_isSaving ? 'Saving...' : 'Save Household'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
