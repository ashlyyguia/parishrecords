import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/ocr_service.dart';
import '../../widgets/app_loading.dart';

/// Enhanced OCR Scanner with support for both printed and handwritten text
class EnhancedOcrScannerScreen extends StatefulWidget {
  const EnhancedOcrScannerScreen({super.key});

  @override
  State<EnhancedOcrScannerScreen> createState() =>
      _EnhancedOcrScannerScreenState();
}

class _EnhancedOcrScannerScreenState extends State<EnhancedOcrScannerScreen> {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  bool _processing = false;
  OcrMode _selectedMode = OcrMode.auto;
  String? _selectedLanguage;
  File? _capturedImage;

  final List<Map<String, String>> _languages = [
    {'code': null.toString(), 'name': 'Auto-detect'},
    {'code': 'en', 'name': 'English'},
    {'code': 'es', 'name': 'Spanish'},
    {'code': 'fr', 'name': 'French'},
    {'code': 'de', 'name': 'German'},
    {'code': 'it', 'name': 'Italian'},
    {'code': 'pt', 'name': 'Portuguese'},
    {'code': 'zh', 'name': 'Chinese'},
    {'code': 'ja', 'name': 'Japanese'},
    {'code': 'ko', 'name': 'Korean'},
    {'code': 'hi', 'name': 'Hindi'},
  ];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      setState(() {
        _controller = ctrl;
        _initializeFuture = ctrl.initialize();
      });
    } catch (_) {
      // Camera init failed - user can still use gallery
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndRecognize() async {
    if (_controller == null || _initializeFuture == null) return;
    if (_processing) return;

    setState(() => _processing = true);
    try {
      await _initializeFuture;
      final file = await _controller!.takePicture();
      setState(() {
        _capturedImage = File(file.path);
        _processing = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to capture: $e')));
      setState(() => _processing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_processing) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );

    if (picked == null) return;

    setState(() => _capturedImage = File(picked.path));
  }

  void _retakePhoto() {
    setState(() => _capturedImage = null);
  }

  Future<void> _proceedWithOcr() async {
    final file = _capturedImage;
    if (file == null) return;

    if (_processing) return;
    setState(() => _processing = true);
    try {
      await _processImage(file);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _processImage(File file) async {
    final result = await OcrService.instance.recognizeText(
      file,
      mode: _selectedMode,
      languageHint: _selectedLanguage,
    );

    if (!mounted) return;

    if (result.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No text recognized. Try changing the mode or using a clearer image.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Navigate to edit screen with results
    final edited = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _OcrResultEditScreen(result: result, imageFile: file),
      ),
    );

    if (!mounted) return;
    if (edited != null) {
      Navigator.of(context).pop(edited);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_capturedImage != null ? 'Review Photo' : 'Scan Text'),
        actions: [
          if (_capturedImage == null)
            IconButton(
              onPressed: _pickFromGallery,
              icon: const Icon(Icons.photo_library),
              tooltip: 'Pick from gallery',
            ),
        ],
      ),
      body: Column(
        children: [
          // Mode Selection Bar
          if (_capturedImage == null) _buildModeSelector(),
          // Camera / Preview
          Expanded(
            child: _capturedImage == null ? _buildCameraPreview() : _buildImagePreview(),
          ),
          // Bottom controls
          _capturedImage == null ? _buildBottomControls() : _buildReviewControls(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_controller == null || _initializeFuture == null) {
      return const AppLoading(message: 'Starting camera...');
    }

    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppLoading(message: 'Starting camera...');
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(_controller!),
            Center(
              child: Container(
                width: 280,
                height: 180,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    _selectedMode == OcrMode.handwritten
                        ? 'Align handwritten text here'
                        : _selectedMode == OcrMode.printed
                            ? 'Align printed text here'
                            : 'Align text here',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildImagePreview() {
    final file = _capturedImage;
    if (file == null) return const SizedBox.shrink();

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(file, fit: BoxFit.contain),
        if (_processing)
          Container(
            color: Colors.black.withValues(alpha: 0.7),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                  SizedBox(height: 16),
                  Text(
                    'Recognizing text...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReviewControls() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _processing ? null : _retakePhoto,
                icon: const Icon(Icons.edit),
                label: const Text('Edit'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _processing ? null : _proceedWithOcr,
                icon: const Icon(Icons.check),
                label: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          // Mode selection
          Row(
            children: [
              Expanded(
                child: _buildModeChip(OcrMode.auto, 'Auto', Icons.auto_awesome),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeChip(
                  OcrMode.printed,
                  'Printed',
                  Icons.description,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeChip(
                  OcrMode.handwritten,
                  'Handwritten',
                  Icons.edit,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Language dropdown
          DropdownButtonFormField<String?>(
            value: _selectedLanguage,
            decoration: const InputDecoration(
              labelText: 'Language',
              prefixIcon: Icon(Icons.language),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Auto-detect')),
              ..._languages.where((l) => l['code'] != 'null').map((lang) {
                return DropdownMenuItem(
                  value: lang['code'],
                  child: Text(lang['name']!),
                );
              }),
            ],
            onChanged: (value) {
              setState(() => _selectedLanguage = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip(OcrMode mode, String label, IconData icon) {
    final isSelected = _selectedMode == mode;
    final color = isSelected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return GestureDetector(
      onTap: () => setState(() => _selectedMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FloatingActionButton.large(
              onPressed: _processing ? null : _captureAndRecognize,
              backgroundColor: _processing
                  ? Colors.grey
                  : Theme.of(context).colorScheme.primary,
              child: _processing
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.camera_alt, size: 32),
            ),
          ],
        ),
      ),
    );
  }
}

/// Enhanced OCR Result Edit Screen with confidence indicators
class _OcrResultEditScreen extends StatefulWidget {
  final OcrResult result;
  final File imageFile;

  const _OcrResultEditScreen({required this.result, required this.imageFile});

  @override
  State<_OcrResultEditScreen> createState() => _OcrResultEditScreenState();
}

class _OcrResultEditScreenState extends State<_OcrResultEditScreen> {
  late final TextEditingController _textController;
  bool _showBlocks = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.result.text);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Recognized Text'),
        actions: [
          TextButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(_textController.text.trim()),
            icon: const Icon(Icons.check),
            label: const Text(
              'USE TEXT',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Info bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(
                  widget.result.mode == OcrMode.handwritten
                      ? Icons.edit
                      : widget.result.mode == OcrMode.printed
                      ? Icons.description
                      : Icons.auto_awesome,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode: ${widget.result.mode.name.toUpperCase()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Confidence: ${(widget.result.confidence * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: _getConfidenceColor(widget.result.confidence),
                        ),
                      ),
                    ],
                  ),
                ),
                // Toggle blocks view
                TextButton.icon(
                  onPressed: () => setState(() => _showBlocks = !_showBlocks),
                  icon: Icon(_showBlocks ? Icons.text_fields : Icons.view_list),
                  label: Text(_showBlocks ? 'Text View' : 'Blocks'),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _showBlocks ? _buildBlocksView() : _buildTextEditView(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextEditView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit the recognized text if needed:',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Recognized text will appear here...',
                alignLabelWithHint: true,
              ),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlocksView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.result.blocks.length,
      itemBuilder: (context, index) {
        final block = widget.result.blocks[index];
        // Calculate block confidence
        double blockConfidence = 0;
        int elementCount = 0;
        for (final line in block.lines) {
          for (final element in line.elements) {
            if (element.confidence != null && element.confidence! > 0) {
              blockConfidence += element.confidence!;
              elementCount++;
            }
          }
        }
        final avgConfidence = elementCount > 0
            ? blockConfidence / elementCount
            : 0.0;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Block ${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (avgConfidence > 0)
                      Text(
                        '${(avgConfidence * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: _getConfidenceColor(avgConfidence),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  block.text,
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.9) return Colors.green;
    if (confidence >= 0.7) return Colors.orange;
    return Colors.red;
  }
}
