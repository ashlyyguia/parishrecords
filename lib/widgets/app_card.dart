import 'package:flutter/material.dart';

import '../app/app_colors.dart';

/// Uniform surface card: white fill, radius 14, hairline border, no shadow.
///
/// This is the app's canonical "flat bordered" card. Depth comes from the
/// border, not shadows, so cards stay crisp and dense-friendly. Use [onTap]
/// to make the whole card tappable (with an ink ripple).
///
/// For places that only need a [BoxDecoration] (e.g. an existing Container you
/// don't want to restructure), use [AppCard.decoration].
///
/// ```dart
/// AppCard(
///   onTap: () => openDetail(),
///   child: ListTile(title: Text('Household #12')),
/// )
/// ```
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.radius = 14,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double radius;

  /// Fill color. Defaults to white surface.
  final Color? color;

  /// Border color. Defaults to the app hairline border.
  final Color? borderColor;

  /// Canonical flat-bordered decoration for standalone Containers.
  static BoxDecoration decoration({
    double radius = 14,
    Color? color,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? AppColors.border),
    );
  }

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);

    if (onTap == null) {
      return Container(
        margin: margin,
        padding: padding,
        decoration: decoration(
          radius: radius,
          color: color,
          borderColor: borderColor,
        ),
        child: child,
      );
    }

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: color ?? AppColors.surface,
        borderRadius: br,
        child: InkWell(
          onTap: onTap,
          borderRadius: br,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: br,
              border: Border.all(color: borderColor ?? AppColors.border),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
