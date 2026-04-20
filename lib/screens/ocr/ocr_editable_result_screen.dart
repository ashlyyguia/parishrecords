import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/scanned_document.dart';
import '../../services/records_repository.dart';
import '../../models/record.dart';

class OcrEditableResultScreen extends StatefulWidget {
  final ScannedDocument document;
  final String? recordId;

  const OcrEditableResultScreen({
    super.key,
    required this.document,
    this.recordId,
  });

  @override
  State<OcrEditableResultScreen> createState() =>
      _OcrEditableResultScreenState();
}

class _OcrEditableResultScreenState extends State<OcrEditableResultScreen> {
  late TextEditingController _textController;
  late TextEditingController _nameController;
  late TextEditingController _dateController;
  late TextEditingController _placeController;
  late TextEditingController _parishController;
  late TextEditingController _notesController;

  bool _isSaving = false;
  RecordType _selectedType = RecordType.baptism;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    final doc = widget.document;
    _textController = TextEditingController(text: doc.displayText);
    _nameController = TextEditingController(
      text: doc.extractedFields['name'] ?? '',
    );
    _dateController = TextEditingController(
      text: doc.extractedFields['date'] ?? '',
    );
    _placeController = TextEditingController(
      text: doc.extractedFields['place'] ?? '',
    );
    _parishController = TextEditingController(
      text: doc.extractedFields['parish'] ?? '',
    );
    _notesController = TextEditingController(text: doc.displayText);

    // Try to parse date
    if (_dateController.text.isNotEmpty) {
      try {
        _selectedDate = DateTime.parse(_dateController.text);
      } catch (e) {
        // Invalid date format
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _nameController.dispose();
    _dateController.dispose();
    _placeController.dispose();
    _parishController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveDocument() async {
    // Document editing is done in memory only, no local storage
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document updated (in memory)')),
      );
    }
  }

  Future<void> _saveAsRecord() async {
    setState(() => _isSaving = true);
    try {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Please enter a name')));
        }
        setState(() => _isSaving = false);
        return;
      }

      final date = _selectedDate ?? DateTime.now();
      final repo = RecordsRepository();

      await repo.add(
        _selectedType,
        name,
        date,
        parish: _parishController.text.trim().isEmpty
            ? null
            : _parishController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        imagePath: widget.document.imagePath,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Record created successfully')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating record: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = picked.toLocal().toString().split(' ')[0];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Scanned Document'),
        actions: [
          if (!_isSaving)
            TextButton.icon(
              onPressed: _saveDocument,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Document Image Preview
            if (widget.document.imagePath.isNotEmpty)
              Card(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: Image.file(
                        File(widget.document.imagePath),
                        fit: BoxFit.contain,
                        height: 200,
                        width: double.infinity,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Icon(Icons.access_time, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            'Scanned: ${_formatDate(widget.document.scannedAt)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Full Text Editor
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.edit_note, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Extracted Text (Editable)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _textController,
                      maxLines: 10,
                      decoration: InputDecoration(
                        hintText: 'Edit extracted text here...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Parsed Fields Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, color: colorScheme.secondary),
                        const SizedBox(width: 8),
                        Text(
                          'Parsed Fields',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Record Type
                    DropdownButtonFormField<RecordType>(
                      initialValue: _selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Record Type',
                        border: OutlineInputBorder(),
                      ),
                      items: RecordType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type.value.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedType = value);
                        }
                      },
                    ),

                    const SizedBox(height: 12),

                    // Name Field
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Date Field
                    TextField(
                      controller: _dateController,
                      decoration: InputDecoration(
                        labelText: 'Date',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.calendar_today),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.date_range),
                          onPressed: _pickDate,
                        ),
                      ),
                      readOnly: true,
                      onTap: _pickDate,
                    ),

                    const SizedBox(height: 12),

                    // Place Field
                    TextField(
                      controller: _placeController,
                      decoration: const InputDecoration(
                        labelText: 'Place',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Parish Field
                    TextField(
                      controller: _parishController,
                      decoration: const InputDecoration(
                        labelText: 'Parish',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.church),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Notes Field
                    TextField(
                      controller: _notesController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.note),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : () => context.pop(),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveAsRecord,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Save as Record'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
