import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/record.dart';
import '../../services/certificate_ocr_extractor.dart';
import '../../services/ocr_image_pick.dart';
import '../../services/ocr_service.dart';
import 'certificate_verify_screen.dart';

/// Scan or upload a sacramental certificate, run OCR, show the detected
/// text regions over the image (ML Kit style), then redirect to the
/// required-fields verification screen.
class CertificateScanScreen extends StatefulWidget {
  final RecordType? initialType;

  const CertificateScanScreen({super.key, this.initialType});

  @override
  State<CertificateScanScreen> createState() => _CertificateScanScreenState();
}

class _CertificateScanScreenState extends State<CertificateScanScreen> {
  late RecordType _type = widget.initialType ?? RecordType.baptism;

  Uint8List? _imageBytes;
  Size? _imageSize;
  List<Rect> _blockRects = [];
  List<Rect> _lineRects = [];
  String _ocrText = '';
  bool _busy = false;
  String? _error;

  static const _typeMeta = {
    RecordType.baptism: (
      label: 'Baptismal',
      icon: Icons.water_drop_outlined,
      color: Colors.blue,
    ),
    RecordType.confirmation: (
      label: 'Confirmation',
      icon: Icons.verified_outlined,
      color: Colors.purple,
    ),
    RecordType.marriage: (
      label: 'Marriage',
      icon: Icons.favorite_outline,
      color: Colors.pink,
    ),
    RecordType.funeral: (
      label: 'Funeral',
      icon: Icons.church_outlined,
      color: Colors.blueGrey,
    ),
  };

  Future<void> _pick({required bool camera}) async {
    setState(() => _error = null);

    final files = camera
        ? [?await OcrImagePick.pickCameraPhoto()]
        : await OcrImagePick.pickImages(allowMultiple: false);
    if (files.isEmpty || !mounted) return;

    setState(() {
      _busy = true;
      _imageBytes = null;
      _blockRects = [];
      _lineRects = [];
      _ocrText = '';
    });

    try {
      final bytes = await files.first.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final imageSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();

      final result = await OcrService.instance.recognizeBytes(bytes);

      final blocks = <Rect>[];
      final lines = <Rect>[];
      for (final block in result.blocks) {
        blocks.add(block.boundingBox);
        for (final line in block.lines) {
          lines.add(line.boundingBox);
        }
      }

      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageSize = imageSize;
        _blockRects = blocks;
        _lineRects = lines;
        _ocrText = result.text;
        _busy = false;
      });

      if (result.text.trim().isEmpty) {
        setState(() {
          _error =
              'No text was recognized. Try a clearer, well-lit photo of the certificate.';
        });
        return;
      }

      // Let the user see the detected regions briefly, then redirect
      // to the required-fields verification screen.
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      await _openVerify();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Scan failed: $e';
      });
    }
  }

  Future<void> _openVerify() async {
    final extraction = CertificateOcrExtractor.extract(_ocrText, _type);
    final verified = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => CertificateVerifyScreen(
          extraction: extraction,
          imageBytes: _imageBytes,
        ),
      ),
    );
    if (verified == null || !mounted) return;

    // Hand the verified data back to whoever opened the scanner.
    if (context.canPop()) {
      context.pop({'type': _type.value, 'fields': verified});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_typeMeta[_type]!.label} record verified '
            '(${verified.length} fields).',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final meta = _typeMeta[_type]!;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Scan Certificate'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Record type',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _typeMeta.entries)
                ChoiceChip(
                  avatar: Icon(
                    entry.value.icon,
                    size: 18,
                    color: _type == entry.key
                        ? Colors.white
                        : entry.value.color,
                  ),
                  label: Text(entry.value.label),
                  selected: _type == entry.key,
                  selectedColor: entry.value.color,
                  labelStyle: TextStyle(
                    color: _type == entry.key
                        ? Colors.white
                        : colorScheme.onSurface,
                  ),
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _type = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (ocrSupportsCamera) ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _pick(camera: true),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Scan'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(camera: false),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Upload image'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ocrUsesMlKit
                ? 'Detected text regions are highlighted after scanning.'
                : 'Text-region highlighting needs the mobile app (ML Kit); '
                    'text is still extracted here.',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 32),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Reading ${meta.label.toLowerCase()} certificate…',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
          if (_imageBytes != null && _imageSize != null) ...[
            const SizedBox(height: 20),
            _SectionLabel(
              icon: Icons.document_scanner_outlined,
              text:
                  'Detected regions — ${_lineRects.length} lines in ${_blockRects.length} blocks',
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _OcrOverlayImage(
                bytes: _imageBytes!,
                imageSize: _imageSize!,
                blockRects: _blockRects,
                lineRects: _lineRects,
              ),
            ),
            if (_ocrText.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _SectionLabel(
                icon: Icons.notes_outlined,
                text: 'Recognized text',
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _ocrText,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _openVerify,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Verify required fields'),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SectionLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }
}

/// The scanned image with ML Kit text-region boxes painted on top —
/// green boxes for lines, blue for blocks (like the ML Kit demo output).
class _OcrOverlayImage extends StatelessWidget {
  final Uint8List bytes;
  final Size imageSize;
  final List<Rect> blockRects;
  final List<Rect> lineRects;

  const _OcrOverlayImage({
    required this.bytes,
    required this.imageSize,
    required this.blockRects,
    required this.lineRects,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final displayWidth = constraints.maxWidth;
        final displayHeight =
            displayWidth * imageSize.height / imageSize.width;
        return SizedBox(
          width: displayWidth,
          height: displayHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(bytes, fit: BoxFit.fill),
              CustomPaint(
                painter: _OcrBoxesPainter(
                  imageSize: imageSize,
                  blockRects: blockRects,
                  lineRects: lineRects,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OcrBoxesPainter extends CustomPainter {
  final Size imageSize;
  final List<Rect> blockRects;
  final List<Rect> lineRects;

  _OcrBoxesPainter({
    required this.imageSize,
    required this.blockRects,
    required this.lineRects,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / imageSize.width;
    final sy = size.height / imageSize.height;

    final blockPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.blueAccent;
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.greenAccent.shade400;

    for (final r in blockRects) {
      canvas.drawRect(
        Rect.fromLTRB(r.left * sx, r.top * sy, r.right * sx, r.bottom * sy),
        blockPaint,
      );
    }
    for (final r in lineRects) {
      canvas.drawRect(
        Rect.fromLTRB(r.left * sx, r.top * sy, r.right * sx, r.bottom * sy),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_OcrBoxesPainter oldDelegate) =>
      oldDelegate.blockRects != blockRects ||
      oldDelegate.lineRects != lineRects ||
      oldDelegate.imageSize != imageSize;
}
