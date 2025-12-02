import 'package:flutter/widgets.dart';

/// Simple responsive helpers to scale sizes based on screen width.
///
/// Usage:
/// - context.rf(16) for font sizes
/// - context.padAll(16) for padding that scales with device width
extension ResponsiveContext on BuildContext {
  static const double _baseWidth = 375.0; // reference small-phone width

  /// Scale factor clamped to a reasonable range so UI doesn't explode on tablets.
  double get responsiveScale {
    final width = MediaQuery.of(this).size.width;
    final raw = width / _baseWidth;
    if (raw < 0.85) return 0.85;
    if (raw > 1.25) return 1.25;
    return raw;
  }

  /// Responsive factor for any numeric size (font, spacing, etc.).
  double rf(double size) => size * responsiveScale;

  /// Responsive EdgeInsets.all()
  EdgeInsets padAll(double value) => EdgeInsets.all(rf(value));

  /// Responsive EdgeInsets.symmetric()
  EdgeInsets padSymmetric({double horizontal = 0, double vertical = 0}) =>
      EdgeInsets.symmetric(horizontal: rf(horizontal), vertical: rf(vertical));
}
