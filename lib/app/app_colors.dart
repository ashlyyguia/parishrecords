import 'package:flutter/material.dart';

/// Central color palette for the Parish Operational Management System.
///
/// The app brand is a serene **Sky Azure** light-blue system. Every screen
/// should source its brand/accent colors from here so the theme stays uniform.
/// Semantic status colors (success / warning / error) are intentionally kept
/// distinct so users still read meaning at a glance.
///
/// Do not hardcode brand hexes in widgets — add a token here and reference it.
class AppColors {
  AppColors._();

  // ── Brand · Sky Azure ────────────────────────────────────────────────
  /// Primary brand color. Buttons, active states, links, key accents.
  static const Color primary = Color(0xFF2E90E5);

  /// Darker brand shade for pressed states, gradients, on-tint text.
  static const Color primaryDark = Color(0xFF1F6FBF);

  /// Lighter brand shade for gradients and subtle highlights.
  static const Color primaryLight = Color(0xFF6BB8F0);

  /// Bright sky accent for playful highlights and gradient stops.
  static const Color accent = Color(0xFF38BDF8);

  /// Soft brand-tinted surface (chip fills, selected rows, hero washes).
  static const Color tint = Color(0xFFEAF4FD);

  /// Stronger brand tint for borders on tinted surfaces / avatar backgrounds.
  static const Color tintStrong = Color(0xFFCFE6FA);

  /// Supporting blue-gray for secondary text/icons and muted accents.
  static const Color secondary = Color(0xFF5B7A99);

  /// Gradient pair helper for hero/brand surfaces.
  static const List<Color> brandGradient = <Color>[primary, accent];

  // ── Neutrals ─────────────────────────────────────────────────────────
  static const Color surface = Colors.white;

  /// Primary text on light surfaces.
  static const Color ink = Color(0xFF1F2430);

  /// Slightly blue-tinted app background (scaffold).
  static const Color scaffold = Color(0xFFF4F8FC);

  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate300 = Color(0xFFCBD5E1);

  /// Hairline borders and dividers.
  static const Color border = Color(0xFFE6E8EF);
  static const Color divider = Color(0xFFE6E8EF);

  /// Input / muted field fill.
  static const Color field = Color(0xFFF2F4F8);

  // ── Semantic status (kept intentionally distinct) ────────────────────
  static const Color success = Color(0xFF10B981);
  static const Color successDark = Color(0xFF059669);
  static const Color successBg = Color(0xFFD1FAE5);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningDark = Color(0xFFD97706);
  static const Color warningBg = Color(0xFFFEF3C7);

  static const Color error = Color(0xFFEF4444);
  static const Color errorDark = Color(0xFFDC2626);
  static const Color errorBg = Color(0xFFFEE2E2);

  /// Informational accents share the brand blue.
  static const Color info = primary;
  static const Color infoBg = tint;
}
