import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/record.dart';
import '../../services/certificate_ocr_extractor.dart';
import '../../services/ocr_image_pick.dart';
import '../../services/ocr_service.dart';
import '../../services/scan_image_store.dart';
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

      // Show the certificate right away with the analyzing animation
      // while text recognition runs.
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageSize = imageSize;
      });

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

    // Keep the scanned certificate on this device (not Firebase Storage);
    // the local path travels with the record into Firestore.
    String? imagePath;
    if (_imageBytes != null) {
      imagePath = await ScanImageStore.save(
        _imageBytes!,
        recordType: _type.value,
      );
    }
    if (!mounted) return;

    // Continue into the full entry form, pre-filled with the verified
    // fields — its Save button writes the record to Firestore.
    final location = GoRouterState.of(context).uri.path;
    final fromAdmin = location.startsWith('/admin');
    final shell = fromAdmin ? '/admin' : '/staff';
    final formPath = switch (_type) {
      RecordType.baptism => '$shell/records/new/baptism',
      RecordType.marriage => '$shell/records/new/marriage',
      RecordType.confirmation => '$shell/records/new/confirmation',
      RecordType.funeral => '$shell/records/new/death',
    };
    context.push(formPath, extra: {
      'ocrPrefill': verified,
      'ocrImagePath': imagePath,
      'ocrRawText': _ocrText,
      'fromStaff': !fromAdmin,
      'fromAdmin': fromAdmin,
    });
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
          if (_busy && _imageBytes == null) ...[
            const SizedBox(height: 32),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_imageBytes != null && _imageSize != null) ...[
            const SizedBox(height: 20),
            _SectionLabel(
              icon: Icons.document_scanner_outlined,
              text: _busy
                  ? 'Analyzing ${meta.label.toLowerCase()} certificate…'
                  : 'Detected regions — ${_lineRects.length} lines in ${_blockRects.length} blocks',
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _OcrOverlayImage(
                bytes: _imageBytes!,
                imageSize: _imageSize!,
                blockRects: _blockRects,
                lineRects: _lineRects,
                analyzing: _busy,
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
/// While [analyzing], a scanning sweep animates over the certificate;
/// when results arrive the boxes animate in progressively.
class _OcrOverlayImage extends StatelessWidget {
  final Uint8List bytes;
  final Size imageSize;
  final List<Rect> blockRects;
  final List<Rect> lineRects;
  final bool analyzing;

  const _OcrOverlayImage({
    required this.bytes,
    required this.imageSize,
    required this.blockRects,
    required this.lineRects,
    required this.analyzing,
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
              if (analyzing)
                const _ScanSweepOverlay()
              else
                TweenAnimationBuilder<double>(
                  key: ValueKey('boxes-${lineRects.length}'),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOut,
                  builder: (context, progress, _) => CustomPaint(
                    painter: _OcrBoxesPainter(
                      imageSize: imageSize,
                      blockRects: blockRects,
                      lineRects: lineRects,
                      progress: progress,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Repeating green sweep that travels down the certificate while OCR runs.
class _ScanSweepOverlay extends StatefulWidget {
  const _ScanSweepOverlay();

  @override
  State<_ScanSweepOverlay> createState() => _ScanSweepOverlayState();
}

class _ScanSweepOverlayState extends State<_ScanSweepOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _ScanSweepPainter(progress: _controller.value),
      ),
    );
  }
}

class _ScanSweepPainter extends CustomPainter {
  final double progress;

  _ScanSweepPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    final bandHeight = size.height * 0.18;
    final band = Rect.fromLTWH(0, y - bandHeight, size.width, bandHeight);

    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.greenAccent.withValues(alpha: 0),
            Colors.greenAccent.withValues(alpha: 0.30),
          ],
        ).createShader(band),
    );

    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = Colors.greenAccent.shade400
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_ScanSweepPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _OcrBoxesPainter extends CustomPainter {
  final Size imageSize;
  final List<Rect> blockRects;
  final List<Rect> lineRects;

  /// 0→1: line boxes appear one after another, block boxes fade in.
  final double progress;

  _OcrBoxesPainter({
    required this.imageSize,
    required this.blockRects,
    required this.lineRects,
    this.progress = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / imageSize.width;
    final sy = size.height / imageSize.height;

    final blockPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.blueAccent.withValues(alpha: progress);
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

    final visibleLines = (lineRects.length * progress).ceil();
    for (var i = 0; i < visibleLines && i < lineRects.length; i++) {
      final r = lineRects[i];
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
      oldDelegate.imageSize != imageSize ||
      oldDelegate.progress != progress;
}
