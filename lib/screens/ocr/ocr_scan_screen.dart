import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../services/ocr_service.dart';

class OcrScanScreen extends StatefulWidget {
  const OcrScanScreen({super.key});

  @override
  State<OcrScanScreen> createState() => _OcrScanScreenState();
}

class _OcrScanScreenState extends State<OcrScanScreen> {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  bool _processing = false;

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
        ResolutionPreset.medium,
        enableAudio: false,
      );
      setState(() {
        _controller = ctrl;
        _initializeFuture = ctrl.initialize();
      });
    } catch (_) {
      // If camera init fails, just stay empty; caller should handle null result.
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
      final text = await OcrService.instance.recognizeTextFromFile(
        File(file.path),
      );
      if (!mounted) return;
      // Push to simple editor so user can tweak, then return final text
      final edited = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => _OcrEditScreen(initialText: text)),
      );
      if (!mounted) return;
      if (edited != null) {
        Navigator.of(context).pop(edited);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to capture or recognize text')),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan text')),
      body: _controller == null || _initializeFuture == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<void>(
              future: _initializeFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Stack(
                  children: [
                    CameraPreview(_controller!),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: FloatingActionButton.extended(
                          onPressed: _processing ? null : _captureAndRecognize,
                          icon: const Icon(Icons.camera_alt),
                          label: Text(_processing ? 'Processing…' : 'Capture'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _OcrEditScreen extends StatefulWidget {
  final String initialText;
  const _OcrEditScreen({required this.initialText});

  @override
  State<_OcrEditScreen> createState() => _OcrEditScreenState();
}

class _OcrEditScreenState extends State<_OcrEditScreen> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit recognized text'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
            child: const Text(
              'USE',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TextField(
          controller: _ctrl,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          maxLines: null,
        ),
      ),
    );
  }
}
