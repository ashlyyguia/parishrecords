import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRScanScreen extends StatefulWidget {
  final String recordId;
  const OCRScanScreen({super.key, required this.recordId});

  @override
  State<OCRScanScreen> createState() => _OCRScanScreenState();
}

class _OCRScanScreenState extends State<OCRScanScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer();
  String? _imagePath;
  String _extractedText = '';
  bool _isProcessing = false;
  Map<String, String> _extractedData = {};

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _scanDocument() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() {
          _imagePath = image.path;
          _isProcessing = true;
        });

        await _processImage(image.path);
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _processImage(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      
      setState(() {
        _extractedText = recognizedText.text;
        _extractedData = _parseExtractedText(recognizedText.text);
        _isProcessing = false;
      });
      
    } catch (e) {
      setState(() {
        _extractedText = 'Error processing image: ${e.toString()}';
        _isProcessing = false;
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
        final nameMatch = RegExp(r'name[:\s]+(.+)', caseSensitive: false).firstMatch(line);
        if (nameMatch != null) {
          data['name'] = nameMatch.group(1)?.trim() ?? '';
        }
      } else if (line.toLowerCase().contains('date')) {
        final dateMatch = RegExp(r'date[:\s]+(.+)', caseSensitive: false).firstMatch(line);
        if (dateMatch != null) {
          data['date'] = dateMatch.group(1)?.trim() ?? '';
        }
      } else if (line.toLowerCase().contains('place')) {
        final placeMatch = RegExp(r'place[:\s]+(.+)', caseSensitive: false).firstMatch(line);
        if (placeMatch != null) {
          data['place'] = placeMatch.group(1)?.trim() ?? '';
        }
      } else if (line.toLowerCase().contains('parish')) {
        final parishMatch = RegExp(r'parish[:\s]+(.+)', caseSensitive: false).firstMatch(line);
        if (parishMatch != null) {
          data['parish'] = parishMatch.group(1)?.trim() ?? '';
        }
      }
    }
    
    return data;
  }

  Future<void> _scanFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() {
          _imagePath = image.path;
          _isProcessing = true;
        });

        await _processImage(image.path);
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Certificate (OCR)'),
        actions: [
          if (_extractedText.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                // Save extracted data
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('OCR data saved to record')),
                );
                Navigator.pop(context, _extractedText);
              },
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
            // Instructions
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text('OCR Scanning Instructions', 
                             style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('• Ensure good lighting when scanning'),
                    const Text('• Hold camera steady and focus on text'),
                    const Text('• Scan clear, high-quality documents'),
                    const Text('• Review extracted text before saving'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Scan buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _scanDocument,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Scan with Camera'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _scanFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('From Gallery'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Processing indicator
            if (_isProcessing)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('Processing image with OCR...'),
                    ],
                  ),
                ),
              ),

            // Scanned image preview
            if (_imagePath != null && !_isProcessing)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Scanned Image', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image, size: 48, color: Colors.grey),
                              Text('Image Preview'),
                              Text('(Placeholder for actual image)', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Extracted text
            if (_extractedText.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Extracted Text', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Text(_extractedText),
                      ),
                      
                      // Parsed data fields
                      if (_extractedData.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('Parsed Fields', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _extractedData.entries.map((entry) => 
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('${entry.key.toUpperCase()}: ${entry.value}',
                                  style: const TextStyle(fontWeight: FontWeight.w500)),
                              )
                            ).toList(),
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _extractedText = '';
                                  _imagePath = null;
                                });
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Scan Again'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('OCR data saved to record')),
                                );
                                Navigator.pop(context, _extractedText);
                              },
                              icon: const Icon(Icons.save),
                              label: const Text('Save Data'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Technical note
            Card(
              color: Colors.orange.withValues(alpha: 0.05),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.construction, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text('Development Note', 
                             style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('This is a placeholder implementation for OCR functionality.'),
                    const Text('Production implementation would integrate:'),
                    const Text('• Google ML Kit Text Recognition'),
                    const Text('• Tesseract OCR Engine'),
                    const Text('• Azure Cognitive Services'),
                    const Text('• AWS Textract'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
