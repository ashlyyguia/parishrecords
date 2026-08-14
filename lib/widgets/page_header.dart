import 'package:flutter/material.dart';

import '../app/app_colors.dart';

/// Uniform page header used at the top of every page's content area.
///
/// A soft sky-blue tinted card with a solid brand icon badge, a title,
/// an optional subtitle, and optional trailing [actions]. On narrow widths
/// the actions wrap below the title so nothing overflows.
///
/// Usage:
/// ```dart
/// PageHeader(
///   icon: Icons.home_work_rounded,
///   title: 'Household Management',
///   subtitle: '12 households in view',
///   actions: [FilledButton.icon(...)],
/// )
/// ```
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.margin,
  });

  /// Leading glyph shown inside the solid brand badge.
  final IconData icon;

  /// Main page title.
  final String title;

  /// Optional supporting line under the title (counts, hints, dates…).
  final String? subtitle;

  /// Optional trailing controls (buttons, menus). Wrap below on mobile.
  final List<Widget> actions;

  /// Optional outer margin. Defaults to none so pages control spacing.
  final EdgeInsetsGeometry? margin;

  /// Standard horizontal breakpoint used across the app for header layout.
  static const double _mobileBreakpoint = 640;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _mobileBreakpoint;
        final pad = isMobile ? 16.0 : 20.0;

        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: isMobile ? 20 : 22,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                height: 1.15,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.slate500,
                  height: 1.3,
                ),
              ),
            ],
          ],
        );

        final badge = Container(
          padding: EdgeInsets.all(isMobile ? 10 : 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.brandGradient,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: isMobile ? 22 : 26),
        );

        final Widget content;
        if (isMobile) {
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  badge,
                  const SizedBox(width: 14),
                  Expanded(child: titleBlock),
                ],
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          );
        } else {
          content = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              badge,
              const SizedBox(width: 16),
              Expanded(child: titleBlock),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ],
            ],
          );
        }

        return Container(
          margin: margin,
          width: double.infinity,
          padding: EdgeInsets.all(pad),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.tint, AppColors.surface],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.tintStrong),
          ),
          child: content,
        );
      },
    );
  }
}
