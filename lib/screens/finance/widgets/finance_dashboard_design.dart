import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../widgets/page_header.dart';

/// Visual system for the Finance dashboard.
///
/// Brand hues are unified to the Sky Azure palette ([AppColors]); only the
/// semantic amber/rose accents keep their own meaning.
class FinanceDashboardDesign {
  FinanceDashboardDesign._();

  static const background = Color(0xFFF4F7FB);
  static const heroGradient = [
    AppColors.primaryDark,
    AppColors.primary,
    AppColors.accent,
  ];
  static const accent = AppColors.primary;
  static const accentSoft = AppColors.tint;
  static const indigo = AppColors.primaryDark;
  static const indigoSoft = AppColors.tintStrong;
  static const amber = Color(0xFFD97706);
  static const amberSoft = Color(0xFFFEF3C7);
  static const rose = Color(0xFFE11D48);
  static const roseSoft = Color(0xFFFFE4E6);
}

class FinanceDashboardHero extends StatelessWidget {
  const FinanceDashboardHero({
    super.key,
    required this.greeting,
    required this.periodDays,
    required this.onPeriodChanged,
  });

  final String greeting;
  final int periodDays;
  final ValueChanged<int> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    return PageHeader(
      icon: Icons.insights_rounded,
      title: 'Finance Dashboard',
      subtitle: greeting,
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 4),
      actions: [
        for (final days in const [7, 30, 90])
          _PeriodChip(
            label: '${days}d',
            selected: periodDays == days,
            onTap: () => onPeriodChanged(days),
          ),
      ],
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.tint,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.primary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class FinanceStatCard extends StatelessWidget {
  const FinanceStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    required this.softTint,
    this.subtitle,
  });

  final String label;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color tint;
  final Color softTint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: softTint.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.08),
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
              color: softTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: tint, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FinancePanel extends StatelessWidget {
  const FinancePanel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.icon,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: FinanceDashboardDesign.accent),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class FinanceQuickAction extends StatelessWidget {
  const FinanceQuickAction({
    super.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.softColor,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color softColor;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: softColor.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: softColor),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.58,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (badgeCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: FinanceDashboardDesign.rose,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badgeCount > 9 ? '9+' : '$badgeCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  color: color.withValues(alpha: 0.75),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FinanceBreakdownRow extends StatelessWidget {
  const FinanceBreakdownRow({
    super.key,
    required this.label,
    required this.amountLabel,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String amountLabel;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (fraction.clamp(0, 1) * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                amountLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$pct%',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction.clamp(0, 1),
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.12),
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class FinanceActivityRow extends StatelessWidget {
  const FinanceActivityRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amountLabel,
    required this.icon,
    required this.color,
    required this.softColor,
  });

  final String title;
  final String subtitle;
  final String amountLabel;
  final IconData icon;
  final Color color;
  final Color softColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: softColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amountLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
