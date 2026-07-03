import 'package:flutter/material.dart';

/// Gives record entry forms the same boxed input style as the
/// certificate verification screen (outline border, rounded corners).
class RecordFormTheme extends StatelessWidget {
  final Widget child;

  const RecordFormTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
      child: child,
    );
  }
}
