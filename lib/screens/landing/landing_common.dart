import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LandingCommon {
  // Premium Modern Color Palette
  static const primary = Color(0xFF4F46E5); // Rich Indigo
  static const primaryLight = Color(0xFF818CF8);
  static const bg = Color(0xFFF8FAFC); // Very soft slate
  static const surface = Colors.white;
  static const purple = Color(0xFF5C57FF);

  // Responsive breakpoints
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;
  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 600 &&
      MediaQuery.of(context).size.width < 1024;
  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1024;

  // Elegant Typography
  static TextStyle titleStyle({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w800,
    Color color = const Color(0xFF1E293B),
  }) {
    return GoogleFonts.playfairDisplay(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: 1.2,
      letterSpacing: -0.5,
    );
  }

  static TextStyle bodyStyle({
    double? fontSize,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? const Color(0xFF475569),
      height: 1.6,
      letterSpacing: 0.2,
    );
  }

  static Widget fluidBackground({required Widget child}) {
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: bg)),
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: const _FluidPainter(color: primaryLight),
                size: Size.infinite,
              ),
            ),
          ),
          // Blur layer for glassmorphic effect over the blobs
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(color: Colors.transparent),
            ),
          ),
          child,
        ],
      ),
    );
  }

  static Widget diagonalBackground({required Widget child}) {
    return CustomPaint(
      painter: _DiagonalPainter(),
      child: child,
    );
  }

  static Widget sectionShell({
    required String title,
    required String subtitle,
    required Widget left,
    required Widget right,
  }) {
    return Builder(
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final isCompact = size.width < 1000;
        final isMobile = size.width < 600;

        // Responsive padding
        final horizontalPadding = isMobile ? 24.0 : 48.0;
        final topPadding = isMobile ? 100.0 : 120.0;
        final titleSize = isMobile ? 32.0 : 42.0;
        final subtitleSize = isMobile ? 14.0 : 16.0;

        return diagonalBackground(
          child: Container(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              topPadding,
              horizontalPadding,
              48,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: titleStyle(fontSize: titleSize),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      style: bodyStyle(fontSize: subtitleSize),
                    ),
                    const SizedBox(height: 32),
                    Expanded(
                      child: isCompact
                          ? SingleChildScrollView(
                              child: Column(
                                children: [
                                  AspectRatio(
                                    aspectRatio: isMobile ? 4 / 3 : 16 / 10,
                                    child: left,
                                  ),
                                  const SizedBox(height: 32),
                                  right,
                                ],
                              ),
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 6, child: left),
                                const SizedBox(width: 48),
                                Expanded(
                                  flex: 5, 
                                  child: SingleChildScrollView(
                                    child: right,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget contentCard({required Widget child, EdgeInsets? padding}) {
    return Builder(
      builder: (context) {
        final isMobile = MediaQuery.of(context).size.width < 600;
        final cardPadding = padding ?? EdgeInsets.all(isMobile ? 24 : 32);

        return Container(
          padding: cardPadding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(isMobile ? 20 : 24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }

  static Widget churchImageCard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = MediaQuery.of(context).size.width < 600;
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final maxCache = isMobile ? 1200 : 2400;
        final cacheW = (maxW * dpr).round().clamp(1, maxCache);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isMobile ? 24 : 32),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.2),
                blurRadius: 40,
                offset: Offset(0, isMobile ? 12 : 24),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(isMobile ? 24 : 32),
            child: Image.asset(
              'assets/images/hero_parish.png',
              fit: BoxFit.cover,
              cacheWidth: cacheW,
              gaplessPlayback: true,
            ),
          ),
        );
      },
    );
  }
}

class _FluidPainter extends CustomPainter {
  final Color color;
  const _FluidPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()..color = color.withValues(alpha: 0.15);
    final paint2 = Paint()..color = const Color(0xFFC7D2FE).withValues(alpha: 0.2);

    // Draw some organic blobs to be blurred by the BackdropFilter
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.2), size.width * 0.3, paint1);
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.8), size.width * 0.4, paint2);
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.1), size.width * 0.25, paint1);
  }

  @override
  bool shouldRepaint(covariant _FluidPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DiagonalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw the light gray background
    final bgPaint = Paint()..color = const Color(0xFFEAEAEA); // Light gray
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 2. Draw the purple diagonal on the bottom left
    final purplePaint = Paint()..color = LandingCommon.purple;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, purplePaint);
  }

  @override
  bool shouldRepaint(covariant _DiagonalPainter oldDelegate) => false;
}
