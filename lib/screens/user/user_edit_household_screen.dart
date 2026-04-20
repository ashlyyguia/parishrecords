// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../models/household.dart';
import '../../../providers/household_provider.dart';

/// User Edit Household Screen - allows updating existing household information
class UserEditHouseholdScreen extends ConsumerStatefulWidget {
  final String householdId;

  const UserEditHouseholdScreen({super.key, required this.householdId});

  @override
  ConsumerState<UserEditHouseholdScreen> createState() =>
      _UserEditHouseholdScreenState();
}

class _UserEditHouseholdScreenState
    extends ConsumerState<UserEditHouseholdScreen> {
  final _formKey = GlobalKey<FormState>();
  final _familyNameCtrl = TextEditingController();
  final _headOfFamilyNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  String? _selectedBarangay;
  bool _isActive = true;
  bool _isLoading = true;
  bool _isSaving = false;
  Household? _household;

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
  void initState() {
    super.initState();
    _loadHousehold();
  }

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

  Future<void> _loadHousehold() async {
    try {
      final household = await ref
          .read(householdRepositoryProvider)
          .getHousehold(widget.householdId);
      if (mounted && household != null) {
        setState(() {
          _household = household;
          _familyNameCtrl.text = household.familyName;
          // Load head-of-family name from metadata (stored at registration)
          _headOfFamilyNameCtrl.text =
              (household.metadata['headOfFamilyName'] as String?) ?? '';
          _addressCtrl.text = household.address;
          _cityCtrl.text = household.city;
          _contactCtrl.text = household.contactNumber;
          _emailCtrl.text = household.email;
          _selectedBarangay = household.barangay;
          _isActive = !household.isArchived;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading household: $e')));
      }
    }
  }

  Future<void> _updateHousehold() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBarangay == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a barangay')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final headName = _headOfFamilyNameCtrl.text.trim();
      // Merge updated name into metadata, preserve other metadata keys
      final updatedMetadata = Map<String, dynamic>.from(_household!.metadata);
      if (headName.isNotEmpty) {
        updatedMetadata['headOfFamilyName'] = headName;
      } else {
        updatedMetadata.remove('headOfFamilyName');
      }

      final updatedHousehold = _household!.copyWith(
        familyName: _familyNameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        barangay: _selectedBarangay!,
        city: _cityCtrl.text.trim(),
        contactNumber: _contactCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        isArchived: !_isActive,
        updatedAt: DateTime.now(),
        metadata: updatedMetadata,
      );

      await ref
          .read(householdRepositoryProvider)
          .updateHousehold(updatedHousehold);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Household updated successfully')),
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

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: const Text('Edit Household'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              floating: true,
              title: const Text('Edit Household'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () => _showDeleteDialog(),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Status Card
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
                            Icons.edit_outlined,
                            color: colorScheme.primary,
                            size: 32,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Edit Household',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Update your household information',
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
                  const SizedBox(height: 12),
                  // Status Toggle Card
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
                      child: SwitchListTile(
                        title: const Text('Household Status'),
                        subtitle: Text(_isActive ? 'Active' : 'Inactive'),
                        value: _isActive,
                        onChanged: (val) => setState(() => _isActive = val),
                        secondary: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _isActive
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _isActive
                                ? Icons.check_circle_outlined
                                : Icons.cancel_outlined,
                            color: _isActive ? Colors.green : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Household Info Card
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
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                              helperText: 'Full name of the household head',
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
                  // Contact Info Card
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
                  onPressed: _isSaving ? null : _updateHousehold,
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
                  label: Text(_isSaving ? 'Updating...' : 'Update Household'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Household'),
        content: const Text(
          'Are you sure you want to delete this household? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref
                    .read(householdRepositoryProvider)
                    .deleteHousehold(widget.householdId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Household deleted successfully'),
                    ),
                  );
                  context.pop();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error deleting: $e')));
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
