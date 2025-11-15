import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../models/record.dart';
import '../../providers/records_provider.dart';

class DeathFormScreen extends ConsumerStatefulWidget {
  const DeathFormScreen({super.key});

  @override
  ConsumerState<DeathFormScreen> createState() => _DeathFormScreenState();
}

class _DeathFormScreenState extends ConsumerState<DeathFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Deceased
  final _nameCtrl = TextEditingController();
  String _gender = 'Male';
  final _ageCtrl = TextEditingController();
  DateTime? _dob; // optional
  DateTime? _dod;
  final _placeOfDeathCtrl = TextEditingController();
  final _causeOfDeathCtrl = TextEditingController();
  final _civilStatusCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // Family
  final _fatherCtrl = TextEditingController();
  final _motherCtrl = TextEditingController();
  final _spouseCtrl = TextEditingController();

  // Burial
  DateTime? _burialDate;
  final _burialPlaceCtrl = TextEditingController();
  final _officiantCtrl = TextEditingController();

  // Remarks
  final _remarksCtrl = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  String? _attachmentPath;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _placeOfDeathCtrl.dispose();
    _causeOfDeathCtrl.dispose();
    _civilStatusCtrl.dispose();
    _addressCtrl.dispose();
    _fatherCtrl.dispose();
    _motherCtrl.dispose();
    _spouseCtrl.dispose();
    _burialPlaceCtrl.dispose();
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
    final d = _dod ?? DateTime.now();
    final dfIso = DateFormat('yyyy-MM-dd');

    final details = {
      'deceased': {
        'fullName': name,
        'gender': _gender,
        'age': _ageCtrl.text.trim(),
        'dateOfBirth': _dob == null ? null : dfIso.format(_dob!),
        'dateOfDeath': dfIso.format(d),
        'placeOfDeath': _placeOfDeathCtrl.text.trim(),
        'causeOfDeath': _causeOfDeathCtrl.text.trim(),
        'civilStatus': _civilStatusCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
      },
      'family': {
        'father': _fatherCtrl.text.trim(),
        'mother': _motherCtrl.text.trim(),
        'spouse': _spouseCtrl.text.trim(),
      },
      'burial': {
        'date': _burialDate == null ? null : dfIso.format(_burialDate!),
        'place': _burialPlaceCtrl.text.trim(),
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
            RecordType.funeral,
            name,
            d,
            imagePath: _attachmentPath,
            notes: json.encode(details),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Death/Burial record saved')));
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
        title: const Text('Death / Burial Record Entry'),
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
              const Text('Deceased Information'),
              const SizedBox(height: 8),
              TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Full name of deceased'), validator: (v)=> (v==null||v.trim().isEmpty)?'Required':null),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                items: const [DropdownMenuItem(value: 'Male', child: Text('Male')), DropdownMenuItem(value: 'Female', child: Text('Female'))],
                onChanged: (v) => setState(() => _gender = v ?? 'Male'),
                decoration: const InputDecoration(labelText: 'Gender'),
              ),
              const SizedBox(height: 8),
              TextFormField(controller: _ageCtrl, decoration: const InputDecoration(labelText: 'Age'), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('Date of birth: ${_dob == null ? 'Unknown' : df.format(_dob!)}')),
                TextButton(onPressed: () => _pickDate(context, (d)=>setState(()=>_dob=d), initial: _dob ?? DateTime.now()), child: const Text('Pick date')),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('Date of death: ${_dod == null ? 'Not set' : df.format(_dod!)}')),
                TextButton(onPressed: () => _pickDate(context, (d)=>setState(()=>_dod=d), initial: _dod ?? DateTime.now()), child: const Text('Pick date')),
              ]),
              const SizedBox(height: 8),
              TextFormField(controller: _placeOfDeathCtrl, decoration: const InputDecoration(labelText: 'Place of death')),
              const SizedBox(height: 8),
              TextFormField(controller: _causeOfDeathCtrl, decoration: const InputDecoration(labelText: 'Cause of death')),
              const SizedBox(height: 8),
              TextFormField(controller: _civilStatusCtrl, decoration: const InputDecoration(labelText: 'Civil status')),
              const SizedBox(height: 8),
              TextFormField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Address / residence')),

              const SizedBox(height: 16),
              const Text('Family Information'),
              const SizedBox(height: 8),
              TextFormField(controller: _fatherCtrl, decoration: const InputDecoration(labelText: "Father's name (optional)")),
              const SizedBox(height: 8),
              TextFormField(controller: _motherCtrl, decoration: const InputDecoration(labelText: "Mother's name (optional)")),
              const SizedBox(height: 8),
              TextFormField(controller: _spouseCtrl, decoration: const InputDecoration(labelText: "Spouse's name (if married)")),

              const SizedBox(height: 16),
              const Text('Burial Details'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('Date of burial: ${_burialDate == null ? 'Not set' : df.format(_burialDate!)}')),
                TextButton(onPressed: () => _pickDate(context, (d)=>setState(()=>_burialDate=d), initial: _burialDate ?? DateTime.now()), child: const Text('Pick date')),
              ]),
              const SizedBox(height: 8),
              TextFormField(controller: _burialPlaceCtrl, decoration: const InputDecoration(labelText: 'Place of burial')),
              const SizedBox(height: 8),
              TextFormField(controller: _officiantCtrl, decoration: const InputDecoration(labelText: 'Officiating priest')),

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
