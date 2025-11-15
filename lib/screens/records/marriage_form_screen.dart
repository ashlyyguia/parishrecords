import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../models/record.dart';
import '../../providers/records_provider.dart';

class MarriageFormScreen extends ConsumerStatefulWidget {
  const MarriageFormScreen({super.key});

  @override
  ConsumerState<MarriageFormScreen> createState() => _MarriageFormScreenState();
}

class _MarriageFormScreenState extends ConsumerState<MarriageFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Marriage details
  DateTime? _marriageDate;
  final _marriagePlaceCtrl = TextEditingController();
  final _officiantCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();

  // Groom
  final _groomNameCtrl = TextEditingController();
  final _groomDobOrAgeCtrl = TextEditingController();
  final _groomCivilStatusCtrl = TextEditingController();
  final _groomReligionCtrl = TextEditingController();
  final _groomAddressCtrl = TextEditingController();
  final _groomFatherCtrl = TextEditingController();
  final _groomMotherCtrl = TextEditingController();

  // Bride
  final _brideNameCtrl = TextEditingController();
  final _brideDobOrAgeCtrl = TextEditingController();
  final _brideCivilStatusCtrl = TextEditingController();
  final _brideReligionCtrl = TextEditingController();
  final _brideAddressCtrl = TextEditingController();
  final _brideFatherCtrl = TextEditingController();
  final _brideMotherCtrl = TextEditingController();

  // Witnesses
  final _witness1Ctrl = TextEditingController();
  final _witness2Ctrl = TextEditingController();

  // Remarks
  final _remarksCtrl = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  String? _attachmentPath;

  @override
  void dispose() {
    _marriagePlaceCtrl.dispose();
    _officiantCtrl.dispose();
    _licenseCtrl.dispose();
    _groomNameCtrl.dispose();
    _groomDobOrAgeCtrl.dispose();
    _groomCivilStatusCtrl.dispose();
    _groomReligionCtrl.dispose();
    _groomAddressCtrl.dispose();
    _groomFatherCtrl.dispose();
    _groomMotherCtrl.dispose();
    _brideNameCtrl.dispose();
    _brideDobOrAgeCtrl.dispose();
    _brideCivilStatusCtrl.dispose();
    _brideReligionCtrl.dispose();
    _brideAddressCtrl.dispose();
    _brideFatherCtrl.dispose();
    _brideMotherCtrl.dispose();
    _witness1Ctrl.dispose();
    _witness2Ctrl.dispose();
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
    final name = '${_groomNameCtrl.text.trim()} & ${_brideNameCtrl.text.trim()}';
    final d = _marriageDate ?? DateTime.now();
    final dfIso = DateFormat('yyyy-MM-dd');

    final details = {
      'marriage': {
        'date': dfIso.format(d),
        'place': _marriagePlaceCtrl.text.trim(),
        'officiant': _officiantCtrl.text.trim(),
        'licenseNumber': _licenseCtrl.text.trim(),
      },
      'groom': {
        'fullName': _groomNameCtrl.text.trim(),
        'ageOrDob': _groomDobOrAgeCtrl.text.trim(),
        'civilStatus': _groomCivilStatusCtrl.text.trim(),
        'religion': _groomReligionCtrl.text.trim(),
        'address': _groomAddressCtrl.text.trim(),
        'father': _groomFatherCtrl.text.trim(),
        'mother': _groomMotherCtrl.text.trim(),
      },
      'bride': {
        'fullName': _brideNameCtrl.text.trim(),
        'ageOrDob': _brideDobOrAgeCtrl.text.trim(),
        'civilStatus': _brideCivilStatusCtrl.text.trim(),
        'religion': _brideReligionCtrl.text.trim(),
        'address': _brideAddressCtrl.text.trim(),
        'father': _brideFatherCtrl.text.trim(),
        'mother': _brideMotherCtrl.text.trim(),
      },
      'witnesses': {
        'witness1': _witness1Ctrl.text.trim(),
        'witness2': _witness2Ctrl.text.trim(),
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
            RecordType.marriage,
            name,
            d,
            imagePath: _attachmentPath,
            notes: json.encode(details),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marriage record saved')));
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
        title: const Text('Marriage Record Entry'),
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
              const Text('Marriage Details'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('Date of marriage: ${_marriageDate == null ? 'Not set' : df.format(_marriageDate!)}')),
                TextButton(onPressed: () => _pickDate(context, (d) => setState(() => _marriageDate = d), initial: _marriageDate ?? DateTime.now()), child: const Text('Pick date')),
              ]),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: 'Place of marriage'), controller: _marriagePlaceCtrl),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: 'Officiating priest'), controller: _officiantCtrl),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: 'Marriage license number'), controller: _licenseCtrl),

              const SizedBox(height: 16),
              const Text('Groom Information'),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: "Groom's full name"), controller: _groomNameCtrl, validator: (v) => (v==null||v.trim().isEmpty)?'Required':null),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: 'Age or date of birth'), controller: _groomDobOrAgeCtrl),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: 'Civil status before marriage'), controller: _groomCivilStatusCtrl),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: 'Religion'), controller: _groomReligionCtrl),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: 'Address'), controller: _groomAddressCtrl),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: "Father's full name"), controller: _groomFatherCtrl),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: "Mother's full name"), controller: _groomMotherCtrl),

              const SizedBox(height: 16),
              const Text('Bride Information'),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: "Bride's full name"), controller: _brideNameCtrl, validator: (v) => (v==null||v.trim().isEmpty)?'Required':null),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: 'Age or date of birth'), controller: _brideDobOrAgeCtrl),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: 'Civil status before marriage'), controller: _brideCivilStatusCtrl),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: 'Religion'), controller: _brideReligionCtrl),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: 'Address'), controller: _brideAddressCtrl),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: "Father's full name"), controller: _brideFatherCtrl),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: "Mother's full name"), controller: _brideMotherCtrl),

              const SizedBox(height: 16),
              const Text('Witnesses'),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: 'Witness #1'), controller: _witness1Ctrl),
              const SizedBox(height: 8),
              TextFormField(decoration: const InputDecoration(labelText: 'Witness #2'), controller: _witness2Ctrl),

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
