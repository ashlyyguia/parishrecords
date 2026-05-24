import 'package:flutter/material.dart';

/// App theme using bundled/system fonts only (no network font fetch).
ThemeData buildAppTheme() {
  const seed = Color(0xFF6C63FF);
  const onSurface = Color(0xFF1F2430);
  const scaffoldBg = Color(0xFFF6F7FB);

  final base = ThemeData(
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(
      primary: seed,
      secondary: const Color(0xFF7C8DB5),
      surface: Colors.white,
      onSurface: onSurface,
    ),
    scaffoldBackgroundColor: scaffoldBg,
    cardColor: Colors.white,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE6E8EF)),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF2F4F8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: const BorderSide(color: Color(0xFFE6E8EF)),
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE6E8EF),
      thickness: 1,
    ),
  );
}
