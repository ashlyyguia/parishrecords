import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../services/ocr_service.dart';
import '../../models/scanned_document.dart';

class EnhancedOcrCaptureScreen extends StatefulWidget {
  const EnhancedOcrCaptureScreen({super.key});

  @override
  State<EnhancedOcrCaptureScreen> createState() =>
      _EnhancedOcrCaptureScreenState();
}

class _EnhancedOcrCaptureScreenState extends State<EnhancedOcrCaptureScreen> {
  final _picker = ImagePicker();
  final _ocr = OcrService.instance;
  final _uuid = const Uuid();

  String _text = '';
  bool _loading = false;
  String? _imagePath;
  String? _status;
  bool _historical = false;
  ScannedDocument? _currentDocument;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _pickAndRecognize(ImageSource source) async {
    setState(() {
      _loading = true;
      _status = 'Picking image...';
    });

    try {
      final xfile = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2000,
        maxHeight: 2000,
      );

      if (xfile == null) {
        setState(() => _loading = false);
        return;
      }

      _imagePath = xfile.path;
      setState(() => _status = 'Image selected');

      if (kIsWeb) {
        setState(() {
          _status = 'OCR is not supported on web';
          _text = '';
          _loading = false;
        });
        return;
      }

      setState(() => _status = 'Running OCR...');

      try {
        final extractedText = await _ocr.extractTextFromImage(
          _imagePath!,
          historical: _historical,
        );

        // Parse extracted fields
        final extractedFields = _parseExtractedText(extractedText);

        // Create scanned document (no local storage)
        final document = ScannedDocument(
          id: _uuid.v4(),
          imagePath: _imagePath!,
          extractedText: extractedText,
          scannedAt: DateTime.now(),
          extractedFields: extractedFields,
          isHistorical: _historical,
        );

        setState(() {
          _text = extractedText;
          _status = 'OCR completed';
          _currentDocument = document;
          _loading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _status = 'OCR failed. Try another photo.';
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('OCR failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Error: ${e.toString()}';
        _loading = false;
      });
    }
  }

  Map<String, String> _parseExtractedText(String text) {
    final Map<String, String> data = {};
    final lines = text.split('\n');

    for (String line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Parse common certificate fields
      if (line.toLowerCase().contains('name')) {
        final nameMatch = RegExp(
          r'name[:\s]+(.+)',
          caseSensitive: false,
        ).firstMatch(line);
        if (nameMatch != null) {
          data['name'] = nameMatch.group(1)?.trim() ?? '';
        }
      } else if (line.toLowerCase().contains('date')) {
        final dateMatch = RegExp(
          r'date[:\s]+(.+)',
          caseSensitive: false,
        ).firstMatch(line);
        if (dateMatch != null) {
          data['date'] = dateMatch.group(1)?.trim() ?? '';
        }
      } else if (line.toLowerCase().contains('place')) {
        final placeMatch = RegExp(
          r'place[:\s]+(.+)',
          caseSensitive: false,
        ).firstMatch(line);
        if (placeMatch != null) {
          data['place'] = placeMatch.group(1)?.trim() ?? '';
        }
      } else if (line.toLowerCase().contains('parish')) {
        final parishMatch = RegExp(
          r'parish[:\s]+(.+)',
          caseSensitive: false,
        ).firstMatch(line);
        if (parishMatch != null) {
          data['parish'] = parishMatch.group(1)?.trim() ?? '';
        }
      }
    }

    return data;
  }

  Future<void> _openEditScreen() async {
    if (_currentDocument == null) return;

    await context.push(
      '/ocr/edit/${_currentDocument!.id}',
      extra: _currentDocument,
    );

    // Document is passed by reference, no need to refresh from storage
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Enhanced OCR Scanner')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Action Buttons
            Wrap(
              spacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _pickAndRecognize(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _pickAndRecognize(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Historical Mode Toggle
            Row(
              children: [
                Switch(
                  value: _historical,
                  onChanged: _loading
                      ? null
                      : (v) => setState(() => _historical = v),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Historical mode (better for old, faded documents)',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Status
            if (_status != null) ...[
              Row(
                children: [
                  if (_loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (_loading) const SizedBox(width: 8),
                  Expanded(
                    child: Text(_status!, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Image Preview
            if (!kIsWeb && _imagePath != null) ...[
              Card(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: Image.file(
                        File(_imagePath!),
                        fit: BoxFit.contain,
                        height: 200,
                        width: double.infinity,
                      ),
                    ),
                    if (_currentDocument != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Document saved',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Extracted Text
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Extracted Text',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_currentDocument != null)
                            IconButton(
                              icon: const Icon(Icons.edit),
                              tooltip: 'Edit & Save as Record',
                              onPressed: _openEditScreen,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : _text.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.document_scanner_outlined,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No text recognized yet',
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Take a photo or select from gallery',
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : SelectableText(
                                _text,
                                style: theme.textTheme.bodyLarge,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Action Buttons
            if (_currentDocument != null && !_loading) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _text = '';
                          _imagePath = null;
                          _currentDocument = null;
                          _status = null;
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Scan New'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openEditScreen,
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Edit & Save'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
