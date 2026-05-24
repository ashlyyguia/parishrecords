import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/ocr_image_pick.dart';
import '../../../services/ocr_service.dart';
import '../../../services/register_ocr_image_preprocess.dart';
import '../../../widgets/register_scan_launcher.dart';

/// Prepare register photos (rotate, contrast) before OCR on the upload flow.
class StaffOcrPreprocessPage extends StatefulWidget {
  const StaffOcrPreprocessPage({super.key});

  @override
  State<StaffOcrPreprocessPage> createState() => _StaffOcrPreprocessPageState();
}

class _StaffOcrPreprocessPageState extends State<StaffOcrPreprocessPage> {
  Uint8List? _originalBytes;
  Uint8List? _previewBytes;
  String? _fileName;
  bool _busy = false;
  double _contrast = 1.35;
  double _brightness = 0.08;
  bool _highContrast = false;
  bool _sharpen = false;

  Future<void> _pickImage() async {
    try {
      final files = await OcrImagePick.pickRegisterPages(
        context,
        allowMultiple: false,
        includeCamera: ocrSupportsCamera,
      );
      if (files.isEmpty || !mounted) return;
      final bytes = await files.first.readAsBytes();
      setState(() {
        _originalBytes = bytes;
        _fileName = files.first.name;
        _previewBytes = bytes;
        _contrast = 1.35;
        _brightness = 0.08;
        _highContrast = false;
        _sharpen = false;
      });
      await _applyEnhance();
    } catch (e) {
      if (!mounted) return;
      _snack('Could not load image: $e', isError: true);
    }
  }

  Future<void> _applyEnhance() async {
    if (_originalBytes == null) return;
    setState(() => _busy = true);
    try {
      final out = await RegisterOcrImagePreprocess.enhanceWithOptions(
        _originalBytes!,
        contrast: _contrast,
        brightness: _brightness,
        highContrast: _highContrast,
        sharpen: _sharpen,
      );
      if (mounted) setState(() => _previewBytes = out);
    } catch (e) {
      if (mounted) _snack('Enhance failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rotate() async {
    if (_previewBytes == null) return;
    setState(() => _busy = true);
    try {
      final rotated = await RegisterOcrImagePreprocess.rotateBytes(
        _previewBytes!,
      );
      setState(() {
        _previewBytes = rotated;
        _originalBytes = rotated;
      });
      await _applyEnhance();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    if (_originalBytes == null) return;
    setState(() {
      _previewBytes = _originalBytes;
      _contrast = 1.35;
      _brightness = 0.08;
      _highContrast = false;
      _sharpen = false;
    });
    _applyEnhance();
  }

  Future<void> _continueToScan() async {
    if (_previewBytes == null) {
      _snack('Pick a register image first.', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final path = await RegisterOcrImagePreprocess.pathForEnhancedBytes(
        _previewBytes!,
      );
      if (!mounted) return;
      final xFile = XFile(path, name: _fileName ?? 'preprocessed.jpg');
      final result = await RegisterScanLauncher.scanXFilesAutofill(
        context: context,
        files: [xFile],
        recordType: 'baptism',
        openReviewIfEmpty: true,
      );
      if (!mounted) return;
      if (result != null) {
        context.go('/staff/ocr/upload', extra: {'scanResult': result});
      } else {
        context.go('/staff/ocr/upload');
      }
    } catch (e) {
      if (mounted) _snack('Scan failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasImage = _previewBytes != null;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Image Preprocessing'),
        actions: [
          if (hasImage)
            TextButton(
              onPressed: _busy ? null : _reset,
              child: const Text('Reset'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Rotate, crop visually, and enhance faded register pages '
                      'before OCR runs.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!hasImage)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pickImage,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Choose register image'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      )
                    else ...[
                      AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: kIsWeb
                                  ? Image.memory(
                                      _previewBytes!,
                                      fit: BoxFit.contain,
                                    )
                                  : Image.memory(
                                      _previewBytes!,
                                      fit: BoxFit.contain,
                                    ),
                            ),
                            if (_busy)
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_fileName != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _fileName!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _rotate,
                            icon: const Icon(Icons.rotate_right),
                            label: const Text('Rotate 90°'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _pickImage,
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Replace image'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('High contrast (faded ink)'),
                        value: _highContrast,
                        onChanged: _busy
                            ? null
                            : (v) {
                                setState(() => _highContrast = v);
                                _applyEnhance();
                              },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Sharpen text'),
                        value: _sharpen,
                        onChanged: _busy
                            ? null
                            : (v) {
                                setState(() => _sharpen = v);
                                _applyEnhance();
                              },
                      ),
                      Text(
                        'Contrast',
                        style: theme.textTheme.labelLarge,
                      ),
                      Slider(
                        value: _contrast,
                        min: 1.0,
                        max: 2.0,
                        divisions: 20,
                        label: _contrast.toStringAsFixed(2),
                        onChanged: _busy || _highContrast
                            ? null
                            : (v) => setState(() => _contrast = v),
                        onChangeEnd: (_) => _applyEnhance(),
                      ),
                      Text(
                        'Brightness',
                        style: theme.textTheme.labelLarge,
                      ),
                      Slider(
                        value: _brightness,
                        min: -0.2,
                        max: 0.3,
                        divisions: 25,
                        label: _brightness.toStringAsFixed(2),
                        onChanged: _busy || _highContrast
                            ? null
                            : (v) => setState(() => _brightness = v),
                        onChangeEnd: (_) => _applyEnhance(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _busy || !hasImage ? null : _continueToScan,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Run OCR & open register table'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => context.go('/staff/ocr/upload'),
                    child: const Text('Skip — go to upload'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
