import 'package:flutter/material.dart';
import 'landing_common.dart';

class MassTimeSection extends StatelessWidget {
  const MassTimeSection({super.key});

  @override
  Widget build(BuildContext context) {
    return LandingCommon.sectionShell(
      title: 'Mass Schedule',
      subtitle: 'Join us for Holy Mass and plan your visit with our weekly liturgy schedule.',
      left: LandingCommon.churchImageCard(),
      right: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ScheduleCard(
            day: 'Sunday',
            times: const ['6:00 AM', '8:00 AM', '5:00 PM'],
            icon: Icons.wb_sunny_outlined,
            isHighlighted: true,
          ),
          const SizedBox(height: 16),
          _ScheduleCard(
            day: 'Monday – Friday',
            times: const ['6:00 AM'],
            icon: Icons.calendar_today_outlined,
          ),
          const SizedBox(height: 16),
          _ScheduleCard(
            day: 'Saturday',
            times: const ['6:00 AM'],
            icon: Icons.weekend_outlined,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: LandingCommon.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: LandingCommon.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: LandingCommon.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Confession available 30 minutes before each Mass.',
                    style: LandingCommon.bodyStyle(
                      fontSize: 13,
                      color: LandingCommon.primary,
                    ),
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

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.day,
    required this.times,
    required this.icon,
    this.isHighlighted = false,
  });

  final String day;
  final List<String> times;
  final IconData icon;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isHighlighted ? LandingCommon.primary : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isHighlighted
                ? LandingCommon.primary.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? Colors.white.withValues(alpha: 0.2)
                  : LandingCommon.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isHighlighted ? Colors.white : LandingCommon.primary,
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
                  style: LandingCommon.bodyStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isHighlighted ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  times.join('  •  '),
                  style: LandingCommon.bodyStyle(
                    fontSize: 13,
                    color: isHighlighted
                        ? Colors.white.withValues(alpha: 0.85)
                        : Colors.grey.shade600,
                  ),
                ),
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
                style: LandingCommon.bodyStyle(
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
