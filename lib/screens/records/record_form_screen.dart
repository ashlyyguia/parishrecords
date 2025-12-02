import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../models/record.dart';
import '../../providers/records_provider.dart';

class RecordFormScreen extends ConsumerStatefulWidget {
  final ParishRecord? existing;
  const RecordFormScreen({super.key, this.existing});

  @override
  ConsumerState<RecordFormScreen> createState() => _RecordFormScreenState();
}

class _RecordFormScreenState extends ConsumerState<RecordFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late RecordType _type;
  late DateTime _date;
  String? _imagePath;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _type = widget.existing?.type ?? RecordType.baptism;
    _date = widget.existing?.date ?? DateTime.now();
    _imagePath = widget.existing?.imagePath;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1800),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickImage(ImageSource source) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image picking is not supported on web in this build.'),
        ),
      );
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() => _imagePath = image.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: ${e.toString()}')),
        );
      }
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take a Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all required fields')),
        );
      }
      return;
    }

    try {
      if (widget.existing == null) {
        await ref
            .read(recordsProvider.notifier)
            .addRecord(
              _type,
              _nameCtrl.text.trim(),
              _date,
              imagePath: _imagePath,
            );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Record added successfully')),
          );
          context.go('/records');
        }
      } else {
        await ref
            .read(recordsProvider.notifier)
            .updateRecord(
              widget.existing!.id,
              type: _type,
              name: _nameCtrl.text.trim(),
              date: _date,
              imagePath: _imagePath,
            );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Record updated successfully')),
          );
          context.go('/records');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save record: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final df = DateFormat.yMMMMd();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(isEdit ? 'Edit Record' : 'Add New Record'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_getNameLabel()),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  hintText: _getNameHint(),
                  prefixIcon: Icon(_getNameIcon()),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              const Text('Record Type'),
              const SizedBox(height: 6),
              DropdownButtonFormField<RecordType>(
                initialValue: _type,
                items: [
                  for (final t in RecordType.values)
                    DropdownMenuItem(
                      value: t,
                      child: Text(
                        '${t.name[0].toUpperCase()}${t.name.substring(1)}',
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
                decoration: const InputDecoration(
                  hintText: 'Select a record type',
                ),
              ),
              const SizedBox(height: 16),
              Text(_getDateLabel()),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 20),
                      const SizedBox(width: 10),
                      Text(df.format(_date)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Record Image'),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _showImageSourceActionSheet,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFE6E8EF),
                      style: BorderStyle.solid,
                    ),
                    color: Colors.grey[50],
                  ),
                  child: _imagePath != null && _imagePath!.isNotEmpty
                      ? Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: kIsWeb
                                  ? Image.network(
                                      _imagePath!,
                                      height: 200,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                    )
                                  : Image.file(
                                      File(_imagePath!),
                                      height: 200,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                    ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FilledButton.icon(
                                  onPressed: _showImageSourceActionSheet,
                                  icon: const Icon(Icons.edit, size: 16),
                                  label: const Text('Change Image'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Theme.of(
                                      context,
                                    ).primaryColor,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      setState(() => _imagePath = null),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    'Remove',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    side: const BorderSide(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            const Icon(
                              Icons.upload_outlined,
                              size: 32,
                              color: Color(0xFF7C8DB5),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Upload or capture an image for this record.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _showImageSourceActionSheet,
                              icon: const Icon(Icons.upload, size: 16),
                              label: const Text('Select Image'),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save Record'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getNameLabel() {
    switch (_type) {
      case RecordType.baptism:
        return 'Person Name';
      case RecordType.marriage:
        return 'Couple Names';
      case RecordType.confirmation:
        return 'Person Name';
      case RecordType.funeral:
        return 'Deceased Name';
    }
  }

  String _getNameHint() {
    switch (_type) {
      case RecordType.baptism:
        return 'Enter the baptized person\'s name';
      case RecordType.marriage:
        return 'Enter groom and bride names';
      case RecordType.confirmation:
        return 'Enter the confirmed person\'s name';
      case RecordType.funeral:
        return 'Enter the deceased person\'s name';
    }
  }

  IconData _getNameIcon() {
    switch (_type) {
      case RecordType.baptism:
        return Icons.child_care;
      case RecordType.marriage:
        return Icons.favorite;
      case RecordType.confirmation:
        return Icons.person;
      case RecordType.funeral:
        return Icons.church;
    }
  }

  String _getDateLabel() {
    switch (_type) {
      case RecordType.baptism:
        return 'Baptism Date';
      case RecordType.marriage:
        return 'Marriage Date';
      case RecordType.confirmation:
        return 'Confirmation Date';
      case RecordType.funeral:
        return 'Funeral Date';
    }
  }
}
