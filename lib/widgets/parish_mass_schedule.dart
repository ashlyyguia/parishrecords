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
        // Sunday schedule with detailed layout
        Text(
          'Sunday',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _accent(context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _accent(context).withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.wb_sunny_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sunday Masses',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '5 masses available',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Grid of mass times
              Column(
                children: [
                  _SundayMassItem(
                    order: '1st',
                    time: '5:00 AM',
                    timeOfDay: 'Morning',
                    description: 'Early Dawn Mass',
                  ),
                  const SizedBox(height: 10),
                  _SundayMassItem(
                    order: '2nd',
                    time: '6:30 AM',
                    timeOfDay: 'Morning',
                    description: 'Early Morning Mass',
                  ),
                  const SizedBox(height: 10),
                  _SundayMassItem(
                    order: '3rd',
                    time: '8:00 AM',
                    timeOfDay: 'Morning',
                    description: 'Main Sunday Mass',
                    isHighlight: true,
                  ),
                  const SizedBox(height: 10),
                  _SundayMassItem(
                    order: '4th',
                    time: '3:30 PM',
                    timeOfDay: 'Afternoon',
                    description: 'Afternoon Mass',
                  ),
                  const SizedBox(height: 10),
                  _SundayMassItem(
                    order: '5th',
                    time: '5:00 PM',
                    timeOfDay: 'Evening',
                    description: 'Evening Mass',
                  ),
                ],
              ),
            ],
          ),
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

class _SundayMassItem extends StatelessWidget {
  const _SundayMassItem({
    required this.order,
    required this.time,
    required this.timeOfDay,
    required this.description,
    this.isHighlight = false,
  });

  final String order;
  final String time;
  final String timeOfDay;
  final String description;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isHighlight
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlight
              ? Colors.white.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          // Order badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              order,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Time and description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          // Time period badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              timeOfDay,
              style: const TextStyle(
                fontSize: 10,
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
