import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/record.dart';
import '../../services/certificate_ocr_extractor.dart';

/// Shows the required fields for the scanned record type, pre-filled from
/// OCR, so the user can confirm the required info was really captured.
/// Missing required fields are flagged and must be filled before confirming.
class CertificateVerifyScreen extends StatefulWidget {
  final CertificateExtraction extraction;
  final Uint8List? imageBytes;

  const CertificateVerifyScreen({
    super.key,
    required this.extraction,
    this.imageBytes,
  });

  @override
  State<CertificateVerifyScreen> createState() =>
      _CertificateVerifyScreenState();
}

class _CertificateVerifyScreenState extends State<CertificateVerifyScreen> {
  final _formKey = GlobalKey<FormState>();
  late final List<CertField> _fields =
      certificateFieldsFor(widget.extraction.type);
  late final Map<String, TextEditingController> _controllers = {
    for (final f in _fields)
      f.key: TextEditingController(
        text: widget.extraction.values[f.key] ?? '',
      ),
  };
  late final Set<String> _detected = {
    for (final f in _fields)
      if ((widget.extraction.values[f.key] ?? '').trim().isNotEmpty) f.key,
  };
  bool _showRawText = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get _typeLabel {
    switch (widget.extraction.type) {
      case RecordType.baptism:
        return 'Baptismal';
      case RecordType.confirmation:
        return 'Confirmation';
      case RecordType.marriage:
        return 'Marriage';
      case RecordType.funeral:
        return 'Funeral';
    }
  }

  void _confirm() {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in the missing required fields.'),
        ),
      );
      return;
    }
    final result = <String, String>{
      for (final f in _fields)
        if (_controllers[f.key]!.text.trim().isNotEmpty)
          f.key: _controllers[f.key]!.text.trim(),
    };
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final requiredFields = _fields.where((f) => f.required).toList();
    final optionalFields = _fields.where((f) => !f.required).toList();
    final detectedRequired =
        requiredFields.where((f) => _detected.contains(f.key)).length;
    final allDetected = detectedRequired == requiredFields.length;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text('Verify $_typeLabel Record'),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: allDetected
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (allDetected ? Colors.green : Colors.orange)
                      .withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    allDetected
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                    color: allDetected
                        ? Colors.green.shade700
                        : Colors.orange.shade800,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      allDetected
                          ? 'All ${requiredFields.length} required fields were '
                              'detected. Review them before confirming.'
                          : '$detectedRequired of ${requiredFields.length} '
                              'required fields detected. Fill in the missing '
                              'ones highlighted below.',
                      style: TextStyle(
                        fontSize: 13,
                        color: allDetected
                            ? Colors.green.shade800
                            : Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Required information',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            for (final f in requiredFields) _buildField(f),
            if (optionalFields.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Register reference (optional)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              for (final f in optionalFields) _buildField(f),
            ],
            if (widget.imageBytes != null) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'Scanned image',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(widget.imageBytes!),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Raw recognized text',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              initiallyExpanded: _showRawText,
              onExpansionChanged: (v) => setState(() => _showRawText = v),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.extraction.rawText,
                    style: const TextStyle(fontSize: 12.5, height: 1.5),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Confirm verified record'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildField(CertField f) {
    final detected = _detected.contains(f.key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: _controllers[f.key],
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: f.label,
          hintText: f.hint,
          helperText: f.required && !detected
              ? 'Not detected by OCR — enter manually'
              : null,
          helperStyle: TextStyle(color: Colors.orange.shade800),
          suffixIcon: detected
              ? Icon(Icons.check_circle, color: Colors.green.shade600)
              : (f.required
                  ? Icon(Icons.error_outline, color: Colors.orange.shade700)
                  : null),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        validator: f.required
            ? (v) =>
                (v == null || v.trim().isEmpty) ? '${f.label} is required' : null
            : null,
      ),
    );
  }
}
