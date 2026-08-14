import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/parish_mass_schedule.dart';
import 'landing_kit.dart';

class MassTimeSection extends StatelessWidget {
  const MassTimeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final compact = LandingKit.isCompact(context);

    final scheduleCard = AppCard(
      padding: EdgeInsets.all(compact ? 18 : 24),
      child: ParishMassSchedule(accentColor: AppColors.primary),
    );

    final aside = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LandingImageFrame(aspectRatio: 4 / 3),
        const SizedBox(height: 18),
        const _VisitNote(),
      ],
    );

    return LandingPage(
      children: [
        const LandingHero(
          eyebrow: 'SCHEDULE OF MASS',
          title: 'Weekly Mass\nSchedule',
          subtitle:
              'Join us in prayer. Holy Rosary Parish celebrates the Eucharist '
              'daily, with five Masses every Sunday.',
          glyph: Icons.schedule_rounded,
        ),
        SizedBox(height: compact ? 28 : 44),
        if (compact) ...[
          aside,
          const SizedBox(height: 20),
          scheduleCard,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: aside),
              const SizedBox(width: 40),
              Expanded(flex: 6, child: scheduleCard),
            ],
          ),
      ],
    );
  }
}

class _VisitNote extends StatelessWidget {
  const _VisitNote();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.tint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.tintStrong),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Before you visit', style: LandingKit.heading(15)),
                const SizedBox(height: 4),
                Text(
                  'Confessions are available 30 minutes before each Mass. '
                  'Schedules may adjust on holy days — check the announcements '
                  'page for updates.',
                  style: LandingKit.body(13, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
