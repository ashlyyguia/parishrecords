import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Loading view for register OCR (baptismal / marriage), styled like the
/// Scan Certificate overlay: the photo on a dark backdrop with a green scan
/// line sweeping down it, plus a status line.
///
/// A register scan takes 10–30 s (grid detection, two OCR passes, row
/// assignment), so the status steps through what the server is doing and
/// shows the elapsed time, instead of one static message.
class OcrScanningView extends StatefulWidget {
  const OcrScanningView({
    super.key,
    required this.bytes,
    this.title = 'Reading the register…',
    this.stages = defaultStages,
  });

  final Uint8List? bytes;
  final String title;

  /// Shown in order, a few seconds each; the last one stays until done.
  final List<String> stages;

  static const defaultStages = [
    'Finding the ruled lines of the register…',
    'Straightening both pages…',
    'Reading the handwriting on the left page…',
    'Reading the handwriting on the right page…',
    'Placing each word in its row and column…',
    'Almost done — checking the rows…',
  ];

  @override
  State<OcrScanningView> createState() => _OcrScanningViewState();
}

class _OcrScanningViewState extends State<OcrScanningView> {
  static const _secondsPerStage = 4;
  int _seconds = 0;
  Timer? _ticker;
  Size? _imageSize;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    _resolveSize();
  }

  void _resolveSize() {
    final bytes = widget.bytes;
    if (bytes == null) return;
    _stream = MemoryImage(bytes).resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() => _imageSize = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          ));
    }, onError: (_, _) {});
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  int get _step => (_seconds ~/ _secondsPerStage).clamp(0, widget.stages.length - 1);

  String get _stage => widget.stages[_step];

  @override
  Widget build(BuildContext context) {
    final step = _step;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Expanded(child: Center(child: _photo())),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const _PulsingSparkle(),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: Text(
              _stage,
              key: ValueKey(_stage),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.greenAccent.shade200,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Step dots: filled up to the current stage.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.stages.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == step ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i <= step
                        ? Colors.greenAccent.shade400
                        : Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${_seconds}s · usually 10–30 seconds',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _photo() {
    final bytes = widget.bytes;
    final size = _imageSize;
    if (bytes == null || size == null || size.height == 0) {
      return const SizedBox(
        width: 56,
        height: 56,
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: size.width / size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Downscaled decode: register photos are 12+ MP.
            Image.memory(bytes, fit: BoxFit.fill, cacheWidth: 1400),
            Container(color: Colors.black.withValues(alpha: 0.15)),
            const ScanSweepOverlay(),
          ],
        ),
      ),
    );
  }
}

/// Repeating green sweep travelling down an image (same look as the Scan
/// Certificate overlay).
class ScanSweepOverlay extends StatefulWidget {
  const ScanSweepOverlay({super.key});

  @override
  State<ScanSweepOverlay> createState() => _ScanSweepOverlayState();
}

class _ScanSweepOverlayState extends State<ScanSweepOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
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
      builder: (context, _) =>
          CustomPaint(painter: _ScanSweepPainter(progress: _controller.value)),
    );
  }
}

class _ScanSweepPainter extends CustomPainter {
  _ScanSweepPainter({required this.progress});

  final double progress;

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

    _paintSparkles(canvas, size, y, bandHeight);
  }

  // Fixed pseudo-random layout (same every frame, so sparkles twinkle in
  // place relative to the line instead of jittering).
  static final List<_Spark> _sparks = () {
    final r = math.Random(7);
    return List.generate(
      22,
      (_) => _Spark(
        x: r.nextDouble(),
        lag: r.nextDouble(), // 0 = on the line, 1 = top of the glow band
        phase: r.nextDouble(),
        speed: 2 + r.nextDouble() * 3,
        size: 3 + r.nextDouble() * 5,
        gold: r.nextDouble() < 0.3,
      ),
    );
  }();

  void _paintSparkles(Canvas canvas, Size size, double lineY, double band) {
    for (final s in _sparks) {
      // Twinkle: 0 -> 1 -> 0 a few times per sweep, each spark offset.
      final t = (progress * s.speed + s.phase) % 1.0;
      final twinkle = math.sin(t * math.pi);
      if (twinkle <= 0.05) continue;
      final cy = lineY - s.lag * band * 1.3;
      if (cy < 0 || cy > size.height) continue;
      final center = Offset(s.x * size.width, cy);
      final r = s.size * (0.4 + 0.6 * twinkle);
      final color = (s.gold ? const Color(0xFFFFF59D) : Colors.white)
          .withValues(alpha: 0.9 * twinkle * (1 - s.lag * 0.5));
      // Soft glow
      canvas.drawCircle(
        center,
        r * 1.6,
        Paint()
          ..color = Colors.greenAccent.withValues(alpha: 0.25 * twinkle)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawPath(_star(center, r), Paint()..color = color);
    }
  }

  /// Four-point sparkle star.
  static Path _star(Offset c, double r) {
    final inner = r * 0.28;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + inner, c.dy - inner, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + inner, c.dy + inner, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - inner, c.dy + inner, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - inner, c.dy - inner, c.dx, c.dy - r)
      ..close();
  }

  @override
  bool shouldRepaint(_ScanSweepPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _Spark {
  const _Spark({
    required this.x,
    required this.lag,
    required this.phase,
    required this.speed,
    required this.size,
    required this.gold,
  });
  final double x, lag, phase, speed, size;
  final bool gold;
}

/// Small sparkle icon beside the title that gently pulses and rotates.
class _PulsingSparkle extends StatefulWidget {
  const _PulsingSparkle();

  @override
  State<_PulsingSparkle> createState() => _PulsingSparkleState();
}

class _PulsingSparkleState extends State<_PulsingSparkle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = Curves.easeInOut.transform(_c.value);
        return Transform.rotate(
          angle: v * 0.35,
          child: Transform.scale(
            scale: 0.85 + 0.3 * v,
            child: Icon(
              Icons.auto_awesome,
              size: 18,
              color: Color.lerp(
                Colors.greenAccent.shade200,
                const Color(0xFFFFF59D),
                v,
              ),
            ),
          ),
        );
      },
    );
  }
}
