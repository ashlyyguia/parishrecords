import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/ocr_service.dart';

class OcrCaptureScreen extends StatefulWidget {
  const OcrCaptureScreen({super.key});

  @override
  State<OcrCaptureScreen> createState() => _OcrCaptureScreenState();
}

class _OcrCaptureScreenState extends State<OcrCaptureScreen> {
  final _picker = ImagePicker();
  final _ocr = OcrService();
  String _text = '';
  bool _loading = false;
  String? _imagePath;
  String? _status;
  bool _historical = false;

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
      if (xfile == null) return;
      _imagePath = xfile.path;
      setState(() => _status = 'Image selected');

      // Web is not supported for OCR in this app
      if (kIsWeb) {
        setState(() {
          _status = 'OCR is not supported on web';
          _text = '';
        });
        return;
      }

      // Cropping disabled to improve stability on some devices

      setState(() => _status = 'Running OCR...');
      try {
        final t = await _ocr.extractTextFromImage(_imagePath!, historical: _historical);
        setState(() {
          _text = t;
          _status = 'Done';
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _status = 'OCR failed. Try another photo.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OCR failed. Try another photo or crop tighter.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR Capture')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _loading ? null : () => _pickAndRecognize(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : () => _pickAndRecognize(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
                // Rotate disabled
              ],
            ),
            const SizedBox(height: 16),
          Row(
            children: [
              Switch(
                value: _historical,
                onChanged: _loading ? null : (v) => setState(() => _historical = v),
              ),
              const SizedBox(width: 6),
              const Expanded(child: Text('Historical mode (better for old, faded documents)')),
            ],
          ),
          const SizedBox(height: 8),
            if (_status != null) ...[
              Row(children: [
                if (_loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                if (_loading) const SizedBox(width: 8),
                Expanded(child: Text(_status!, style: Theme.of(context).textTheme.bodySmall)),
              ]),
              const SizedBox(height: 8),
            ],
            if (!kIsWeb && _imagePath != null) ...[
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.file(File(_imagePath!), fit: BoxFit.contain),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _text.isEmpty
                      ? const Center(child: Text('No text recognized yet'))
                      : SelectableText(_text),
            ),
          ],
        ),
      ),
    );
  }
}
