import 'package:flutter/material.dart';

/// Shared Holy Rosary Parish mass schedule (landing + user portal).
class ParishMassSchedule extends StatelessWidget {
  const ParishMassSchedule({super.key, this.accentColor});

  final Color? accentColor;

  Color _accent(BuildContext context) =>
      accentColor ?? Theme.of(context).colorScheme.primary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MassScheduleCard(
          day: 'Monday – Friday',
          times: const [
            'MORNING – 6:00 AM',
            'AFTERNOON – 5:15 PM',
          ],
          icon: Icons.calendar_today_outlined,
          accentColor: _accent(context),
        ),
        const SizedBox(height: 10),
        MassScheduleNote(
          text: 'Note: No mass every Tuesday afternoon.',
          accentColor: _accent(context),
        ),
        const SizedBox(height: 16),
        MassScheduleCard(
          day: 'Saturday',
          times: const [
            'MORNING – 6:00 AM',
            'AFTERNOON – 5:30 PM',
          ],
          icon: Icons.weekend_outlined,
          accentColor: _accent(context),
        ),
        const SizedBox(height: 16),
        MassScheduleCard(
          day: 'Sunday',
          times: const [
            '1ST MASS – 5:00 AM',
            '2ND MASS – 6:30 AM',
            '3RD MASS – 8:00 AM',
            '4TH MASS – 3:30 PM',
            '5TH MASS – 5:00 PM',
          ],
          icon: Icons.wb_sunny_outlined,
          isHighlighted: true,
          accentColor: _accent(context),
        ),
      ],
    );
  }
}

class MassScheduleNote extends StatelessWidget {
  const MassScheduleNote({
    super.key,
    required this.text,
    required this.accentColor,
  });

  final String text;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: accentColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MassScheduleCard extends StatelessWidget {
  const MassScheduleCard({
    super.key,
    required this.day,
    required this.times,
    required this.icon,
    required this.accentColor,
    this.isHighlighted = false,
  });

  final String day;
  final List<String> times;
  final IconData icon;
  final Color accentColor;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeColor = isHighlighted
        ? Colors.white.withValues(alpha: 0.9)
        : colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isHighlighted ? accentColor : colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: isHighlighted
            ? null
            : Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: isHighlighted
                ? accentColor.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? Colors.white.withValues(alpha: 0.2)
                  : accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isHighlighted ? Colors.white : accentColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isHighlighted ? Colors.white : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                for (final time in times) ...[
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: timeColor,
                    ),
                  ),
                  if (time != times.last) const SizedBox(height: 4),
                ],
              ],
            ),
          ),
          if (isHighlighted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${times.length} Masses',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
