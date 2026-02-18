import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'router.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C63FF),
            brightness: Brightness.light,
          ).copyWith(
            primary: const Color(0xFF6C63FF),
            secondary: const Color(0xFF7C8DB5),
            surface: Colors.white,
            onSurface: const Color(0xFF1F2430),
          ),
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      cardColor: Colors.white,
      textTheme: GoogleFonts.poppinsTextTheme().copyWith(
        headlineLarge: GoogleFonts.merriweather(fontWeight: FontWeight.w700),
        headlineMedium: GoogleFonts.merriweather(fontWeight: FontWeight.w700),
        headlineSmall: GoogleFonts.merriweather(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2430),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF1F2430),
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

    // Dark theme removed per request

    final router = createRouter();

    return MaterialApp.router(
      title: 'Parish Record',
      theme: theme,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
