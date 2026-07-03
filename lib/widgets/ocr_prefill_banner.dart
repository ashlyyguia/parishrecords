import 'package:flutter/material.dart';

/// Shown at the top of record entry forms opened from the certificate
/// scanner: explains where the values came from and what happens on save.
class OcrPrefillBanner extends StatelessWidget {
  /// True when the record will be saved as temporary (staff scans) and
  /// still needs admin approval.
  final bool willBeTemporary;

  const OcrPrefillBanner({super.key, required this.willBeTemporary});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.document_scanner_outlined, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pre-filled from scanned certificate',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  willBeTemporary
                      ? 'Review every field before saving. The record is '
                          'saved as Temporary and becomes official after an '
                          'admin approves it.'
                      : 'Review every field before saving the record.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
