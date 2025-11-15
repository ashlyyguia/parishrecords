import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../models/record.dart';
import '../../providers/records_provider.dart';

class EnhancedBaptismFormScreen extends ConsumerStatefulWidget {
  const EnhancedBaptismFormScreen({super.key});

  @override
  ConsumerState<EnhancedBaptismFormScreen> createState() => _EnhancedBaptismFormScreenState();
}

class _EnhancedBaptismFormScreenState extends ConsumerState<EnhancedBaptismFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Registry fields
  final _registryNoCtrl = TextEditingController();
  final _bookNoCtrl = TextEditingController();
  final _pageNoCtrl = TextEditingController();
  final _lineNoCtrl = TextEditingController();
  
  // Child Information
  final _nameCtrl = TextEditingController();
  DateTime? _dob;
  final _placeOfBirthCtrl = TextEditingController();
  String _gender = 'Male';
  final _addressCtrl = TextEditingController();
  String _legitimacy = 'Legitimate';

  // Parents
  final _fatherCtrl = TextEditingController();
  final _motherCtrl = TextEditingController();
  final _parentsMarriageCtrl = TextEditingController();

  // Godparents
  final _godfather1Ctrl = TextEditingController();
  final _godmother1Ctrl = TextEditingController();
  final _godfather2Ctrl = TextEditingController();
  final _godmother2Ctrl = TextEditingController();

  // Baptism details
  DateTime? _baptismDate;
  final _baptismTimeCtrl = TextEditingController();
  final _baptismPlaceCtrl = TextEditingController();
  final _ministerCtrl = TextEditingController();

  // Metadata
  final _remarksCtrl = TextEditingController();
  bool _certificateIssued = false;
  final _staffNameCtrl = TextEditingController();

  // Attachment
  final ImagePicker _picker = ImagePicker();
  String? _attachmentPath;

  @override
  void initState() {
    super.initState();
    // Auto-generate registry number
    final now = DateTime.now();
    _registryNoCtrl.text = '${now.year}-${now.millisecondsSinceEpoch.toString().substring(8)}-B';
    
    // Auto-populate staff name (you can get this from auth context)
    _staffNameCtrl.text = 'Current Staff'; // Replace with actual staff name
  }

  @override
  void dispose() {
    _registryNoCtrl.dispose();
    _bookNoCtrl.dispose();
    _pageNoCtrl.dispose();
    _lineNoCtrl.dispose();
    _nameCtrl.dispose();
    _placeOfBirthCtrl.dispose();
    _addressCtrl.dispose();
    _fatherCtrl.dispose();
    _motherCtrl.dispose();
    _parentsMarriageCtrl.dispose();
    _godfather1Ctrl.dispose();
    _godmother1Ctrl.dispose();
    _godfather2Ctrl.dispose();
    _godmother2Ctrl.dispose();
    _baptismTimeCtrl.dispose();
    _baptismPlaceCtrl.dispose();
    _ministerCtrl.dispose();
    _remarksCtrl.dispose();
    _staffNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext ctx, void Function(DateTime) set, {DateTime? initial}) async {
    final picked = await showDatePicker(
      context: ctx,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(1800),
      lastDate: DateTime(2100),
    );
    if (picked != null) set(picked);
  }

  Future<void> _pickAttachment() async {
    try {
      final XFile? file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (file != null) setState(() => _attachmentPath = file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Attachment error: ${e.toString()}')));
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please complete required fields')));
      return;
    }
    
    final name = _nameCtrl.text.trim();
    final baptDate = _baptismDate ?? DateTime.now();
    final dfIso = DateFormat("yyyy-MM-dd");

    final details = <String, dynamic>{
      'registry': {
        'registryNo': _registryNoCtrl.text.trim(),
        'bookNo': _bookNoCtrl.text.trim(),
        'pageNo': _pageNoCtrl.text.trim(),
        'lineNo': _lineNoCtrl.text.trim(),
      },
      'child': {
        'fullName': name,
        'dateOfBirth': _dob == null ? null : dfIso.format(_dob!),
        'placeOfBirth': _placeOfBirthCtrl.text.trim(),
        'gender': _gender,
        'address': _addressCtrl.text.trim(),
        'legitimacy': _legitimacy,
      },
      'parents': {
        'father': _fatherCtrl.text.trim(),
        'mother': _motherCtrl.text.trim(),
        'marriageInfo': _parentsMarriageCtrl.text.trim(),
      },
      'godparents': {
        'godfather1': _godfather1Ctrl.text.trim(),
        'godmother1': _godmother1Ctrl.text.trim(),
        'godfather2': _godfather2Ctrl.text.trim(),
        'godmother2': _godmother2Ctrl.text.trim(),
      },
      'baptism': {
        'date': dfIso.format(baptDate),
        'time': _baptismTimeCtrl.text.trim(),
        'place': _baptismPlaceCtrl.text.trim(),
        'minister': _ministerCtrl.text.trim(),
      },
      'metadata': {
        'remarks': _remarksCtrl.text.trim(),
        'certificateIssued': _certificateIssued,
        'staffName': _staffNameCtrl.text.trim(),
        'dateEncoded': DateTime.now().toIso8601String(),
      },
      'attachments': _attachmentPath == null ? [] : [
        {
          'type': 'image',
          'path': _attachmentPath,
        }
      ],
    };

    try {
      await ref.read(recordsProvider.notifier).addRecord(
            RecordType.baptism,
            name,
            baptDate,
            imagePath: _attachmentPath,
            notes: json.encode(details),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Baptism record saved successfully')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: ${e.toString()}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMMd();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Baptism Record Entry'),
        actions: [
          TextButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Save')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Registry Information
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Registry Information', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _registryNoCtrl,
                        decoration: const InputDecoration(labelText: 'Registry No'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _bookNoCtrl,
                              decoration: const InputDecoration(labelText: 'Book No'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _pageNoCtrl,
                              decoration: const InputDecoration(labelText: 'Page No'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _lineNoCtrl,
                              decoration: const InputDecoration(labelText: 'Line No'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Child Information
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Child Information', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: "Child's Full Name"),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Date of Birth: ${_dob == null ? 'Not set' : df.format(_dob!)}'),
                          ),
                          TextButton(
                            onPressed: () => _pickDate(context, (d) => setState(() => _dob = d), initial: _dob),
                            child: const Text('Pick Date'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _placeOfBirthCtrl,
                        decoration: const InputDecoration(labelText: 'Place of Birth'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _gender,
                        items: const [
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(value: 'Female', child: Text('Female')),
                        ],
                        onChanged: (v) => setState(() => _gender = v ?? 'Male'),
                        decoration: const InputDecoration(labelText: 'Gender'),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _addressCtrl,
                        decoration: const InputDecoration(labelText: 'Address'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _legitimacy,
                        items: const [
                          DropdownMenuItem(value: 'Legitimate', child: Text('Legitimate')),
                          DropdownMenuItem(value: 'Illegitimate', child: Text('Illegitimate')),
                        ],
                        onChanged: (v) => setState(() => _legitimacy = v ?? 'Legitimate'),
                        decoration: const InputDecoration(labelText: 'Legitimacy'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Parents Information
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Parents Information', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _fatherCtrl,
                        decoration: const InputDecoration(labelText: "Father's Name"),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _motherCtrl,
                        decoration: const InputDecoration(labelText: "Mother's Name"),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _parentsMarriageCtrl,
                        decoration: const InputDecoration(labelText: 'Parents Marriage Info (Place & Date)'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Godparents
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Godparents', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _godfather1Ctrl,
                        decoration: const InputDecoration(labelText: 'Godfather #1'),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _godmother1Ctrl,
                        decoration: const InputDecoration(labelText: 'Godmother #1'),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _godfather2Ctrl,
                        decoration: const InputDecoration(labelText: 'Godfather #2 (Optional)'),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _godmother2Ctrl,
                        decoration: const InputDecoration(labelText: 'Godmother #2 (Optional)'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Baptism Details
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Baptism Details', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Date of Baptism: ${_baptismDate == null ? 'Not set' : df.format(_baptismDate!)}'),
                          ),
                          TextButton(
                            onPressed: () => _pickDate(context, (d) => setState(() => _baptismDate = d), initial: _baptismDate),
                            child: const Text('Pick Date'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _baptismTimeCtrl,
                        decoration: const InputDecoration(labelText: 'Time of Baptism'),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _baptismPlaceCtrl,
                        decoration: const InputDecoration(labelText: 'Place of Baptism'),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _ministerCtrl,
                        decoration: const InputDecoration(labelText: 'Minister'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Metadata
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Additional Information', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _remarksCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Remarks'),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        title: const Text('Certificate Issued?'),
                        value: _certificateIssued,
                        onChanged: (v) => setState(() => _certificateIssued = v ?? false),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _staffNameCtrl,
                        decoration: const InputDecoration(labelText: 'Prepared By / Staff Name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Attachment
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Scanned Certificate (Optional)', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(_attachmentPath == null ? 'No file selected' : _attachmentPath!),
                          ),
                          OutlinedButton.icon(
                            onPressed: _pickAttachment,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Attach'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Action buttons
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save Record'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Certificate will be available after admin approval')));
                  },
                  icon: const Icon(Icons.pending_outlined),
                  label: const Text('Pending Approval'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
