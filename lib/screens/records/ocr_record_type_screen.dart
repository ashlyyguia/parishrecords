import 'package:flutter/material.dart';

class OcrRecordTypeScreen extends StatelessWidget {
  const OcrRecordTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(title: const Text('Scan New Record'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(
              'Choose a record type to scan with OCR',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _OcrTypeButton(
              label: 'Baptism (OCR)',
              description: 'Scan a baptism register page',
              color: Colors.blue,
              icon: Icons.water_drop_outlined,
              onTap: () => Navigator.of(context).pop('baptism'),
            ),
            const SizedBox(height: 12),
            _OcrTypeButton(
              label: 'Marriage (OCR)',
              description: 'Scan a marriage register page',
              color: Colors.pink,
              icon: Icons.favorite_outline,
              onTap: () => Navigator.of(context).pop('marriage'),
            ),
            const SizedBox(height: 12),
            _OcrTypeButton(
              label: 'Confirmation (OCR)',
              description: 'Scan a confirmation register page',
              color: Colors.purple,
              icon: Icons.verified_outlined,
              onTap: () => Navigator.of(context).pop('confirmation'),
            ),
            const SizedBox(height: 12),
            _OcrTypeButton(
              label: 'Death (OCR)',
              description: 'Scan a death / funeral register page',
              color: Colors.grey,
              icon: Icons.person_outline,
              onTap: () => Navigator.of(context).pop('death'),
            ),
            const Spacer(),
            Text(
              'You can always edit the details after scanning.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _OcrTypeButton extends StatelessWidget {
  final String label;
  final String description;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _OcrTypeButton({
    required this.label,
    required this.description,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: colorScheme.surface,
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
