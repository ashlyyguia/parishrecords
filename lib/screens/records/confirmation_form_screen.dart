import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../models/record.dart';
import '../../providers/records_provider.dart';

class ConfirmationFormScreen extends ConsumerStatefulWidget {
  const ConfirmationFormScreen({super.key});

  @override
  ConsumerState<ConfirmationFormScreen> createState() => _ConfirmationFormScreenState();
}

class _ConfirmationFormScreenState extends ConsumerState<ConfirmationFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Confirmand
  final _nameCtrl = TextEditingController();
  DateTime? _dob;
  final _placeOfBirthCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // Parents
  final _fatherCtrl = TextEditingController();
  final _motherCtrl = TextEditingController();

  // Sponsor
  final _sponsorNameCtrl = TextEditingController();
  final _sponsorRelationCtrl = TextEditingController();

  // Confirmation details
  DateTime? _confirmDate;
  final _confirmPlaceCtrl = TextEditingController();
  final _officiantCtrl = TextEditingController();

  // Remarks
  final _remarksCtrl = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  String? _attachmentPath;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _placeOfBirthCtrl.dispose();
    _addressCtrl.dispose();
    _fatherCtrl.dispose();
    _motherCtrl.dispose();
    _sponsorNameCtrl.dispose();
    _sponsorRelationCtrl.dispose();
    _confirmPlaceCtrl.dispose();
    _officiantCtrl.dispose();
    _remarksCtrl.dispose();
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
    final d = _confirmDate ?? DateTime.now();
    final dfIso = DateFormat('yyyy-MM-dd');

    final details = {
      'confirmand': {
        'fullName': name,
        'dateOfBirth': _dob == null ? null : dfIso.format(_dob!),
        'placeOfBirth': _placeOfBirthCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
      },
      'parents': {
        'father': _fatherCtrl.text.trim(),
        'mother': _motherCtrl.text.trim(),
      },
      'sponsor': {
        'fullName': _sponsorNameCtrl.text.trim(),
        'relationship': _sponsorRelationCtrl.text.trim(),
      },
      'confirmation': {
        'date': dfIso.format(d),
        'place': _confirmPlaceCtrl.text.trim(),
        'officiant': _officiantCtrl.text.trim(),
      },
      'remarks': _remarksCtrl.text.trim(),
      'attachments': _attachmentPath == null ? [] : [
        {
          'type': 'image',
          'path': _attachmentPath,
        }
      ],
      'meta': {
        'createdAt': DateTime.now().toIso8601String(),
      }
    };

    try {
      await ref.read(recordsProvider.notifier).addRecord(
            RecordType.confirmation,
            name,
            d,
            imagePath: _attachmentPath,
            notes: json.encode(details),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Confirmation record saved')));
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
        title: const Text('Confirmation Record Entry'),
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
              const Text('Confirmand Information'),
              const SizedBox(height: 8),
              TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Confirmand's full name"), validator: (v)=> (v==null||v.trim().isEmpty)?'Required':null),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('Date of birth: ${_dob == null ? 'Not set' : df.format(_dob!)}')),
                TextButton(onPressed: () => _pickDate(context, (d)=>setState(()=>_dob=d), initial: _dob ?? DateTime.now()), child: const Text('Pick date')),
              ]),
              const SizedBox(height: 8),
              TextFormField(controller: _placeOfBirthCtrl, decoration: const InputDecoration(labelText: 'Place of birth')),
              const SizedBox(height: 8),
              TextFormField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Address / residence')),

              const SizedBox(height: 16),
              const Text('Parents\' Information'),
              const SizedBox(height: 8),
              TextFormField(controller: _fatherCtrl, decoration: const InputDecoration(labelText: "Father's full name")),
              const SizedBox(height: 8),
              TextFormField(controller: _motherCtrl, decoration: const InputDecoration(labelText: "Mother's full name")),

              const SizedBox(height: 16),
              const Text('Sponsor Information'),
              const SizedBox(height: 8),
              TextFormField(controller: _sponsorNameCtrl, decoration: const InputDecoration(labelText: "Sponsor's full name")),
              const SizedBox(height: 8),
              TextFormField(controller: _sponsorRelationCtrl, decoration: const InputDecoration(labelText: 'Relationship')),

              const SizedBox(height: 16),
              const Text('Confirmation Details'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('Date of confirmation: ${_confirmDate == null ? 'Not set' : df.format(_confirmDate!)}')),
                TextButton(onPressed: () => _pickDate(context, (d)=>setState(()=>_confirmDate=d), initial: _confirmDate ?? DateTime.now()), child: const Text('Pick date')),
              ]),
              const SizedBox(height: 8),
              TextFormField(controller: _confirmPlaceCtrl, decoration: const InputDecoration(labelText: 'Place of confirmation')),
              const SizedBox(height: 8),
              TextFormField(controller: _officiantCtrl, decoration: const InputDecoration(labelText: 'Officiating bishop/priest')),

              const SizedBox(height: 16),
              const Text('Remarks'),
              const SizedBox(height: 8),
              TextFormField(controller: _remarksCtrl, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Notes / remarks')),

              const SizedBox(height: 16),
              const Text('Scanned Certificate (optional)'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text(_attachmentPath == null ? 'No file selected' : _attachmentPath!)),
                OutlinedButton.icon(onPressed: _pickAttachment, icon: const Icon(Icons.attach_file), label: const Text('Attach')),
              ]),

              const SizedBox(height: 24),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('Save'))),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: (){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Certificate will be available after admin approval')));}, icon: const Icon(Icons.pending_outlined), label: const Text('Pending Approval'))),
            ],
          ),
        ),
      ),
    );
  }
}
