import 'package:flutter/material.dart';

import '../app/app_colors.dart';

/// Parish office details shown wherever people are told how to give.
/// Kept in one place so the landing page and the app always agree.
class ParishGivingInfo {
  ParishGivingInfo._();

  static const parishName = 'Holy Rosary Parish';
  static const location = 'Holy Rosary Parish, Oroquieta City, Misamis Occidental';
  static const officeDays = 'Monday – Saturday';
  static const officeHours = '8:00 AM – 5:00 PM';
  static const email = 'parishoffice@holyrosary.ph';
  static const purposes = ['Tithes', 'Projects', 'Outreach', 'General'];
}

/// Step-by-step instructions for giving in person at the parish office.
/// The system takes no online payments; donations are received in cash and
/// recorded by the Finance office.
class GiveInPersonGuide extends StatelessWidget {
  const GiveInPersonGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = <(IconData, String, String)>[
      (
        Icons.storefront_rounded,
        'Visit the parish office',
        'Come to the office during office hours (details below).',
      ),
      (
        Icons.category_rounded,
        'Tell us the purpose',
        'Let the staff know what your gift is for: '
            '${ParishGivingInfo.purposes.join(', ')}.',
      ),
      (
        Icons.payments_rounded,
        'Give in cash',
        'Hand your donation to the parish staff. Any amount is welcome.',
      ),
      (
        Icons.receipt_long_rounded,
        'Receive your receipt',
        'The Finance office records your gift and gives you a receipt.',
      ),
    ];

    return Column(
      key: const ValueKey('give-in-person-guide'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How to give',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Donations are received in person at the parish office. '
          'We do not accept online payments.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.slate600,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < steps.length; i++)
          _StepRow(
            number: i + 1,
            icon: steps[i].$1,
            title: steps[i].$2,
            text: steps[i].$3,
            isLast: i == steps.length - 1,
          ),
        const SizedBox(height: 8),
        _OfficeCard(),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.tint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.tintStrong),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.church_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You may also give through the collection during Holy Mass.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.ink,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.icon,
    required this.title,
    required this.text,
    required this.isLast,
  });

  final int number;
  final IconData icon;
  final String title;
  final String text;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.tintStrong,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 8 : 18, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.slate600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget line(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$label\n',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.slate500,
                        ),
                      ),
                      TextSpan(
                        text: value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line(Icons.place_rounded, 'Parish office', ParishGivingInfo.location),
          line(
            Icons.schedule_rounded,
            'Office hours',
            '${ParishGivingInfo.officeDays}, ${ParishGivingInfo.officeHours}',
          ),
          line(Icons.mail_outline_rounded, 'Questions', ParishGivingInfo.email),
        ],
      ),
    );
  }
}
