import 'package:flutter/material.dart';

import '../app/app_colors.dart';

/// Uniform "nothing here yet" placeholder for empty lists and results.
///
/// A centered, brand-tinted icon badge with a title, a supporting message, and
/// an optional call-to-action button. Use [compact] inside small cards.
///
/// ```dart
/// AppEmptyState(
///   icon: Icons.home_work_outlined,
///   title: 'No households yet',
///   message: 'Add your first household to get started.',
///   actionLabel: 'Add Household',
///   onAction: () => context.push('/user/households/new'),
/// )
/// ```
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon = Icons.add_rounded,
    this.compact = false,
  });

  /// Glyph shown inside the tinted circular badge.
  final IconData icon;

  /// Optional bold heading above the [message].
  final String? title;

  /// Supporting line explaining the empty state.
  final String message;

  /// Optional call-to-action button label. Requires [onAction].
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Icon for the call-to-action button. Defaults to a plus.
  final IconData actionIcon;

  /// Tighter spacing/sizing for use inside small cards.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeSize = compact ? 64.0 : 88.0;
    final iconSize = compact ? 30.0 : 42.0;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 24 : 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: badgeSize,
              height: badgeSize,
              decoration: const BoxDecoration(
                color: AppColors.tint,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: iconSize, color: AppColors.primary),
            ),
            SizedBox(height: compact ? 16 : 20),
            if (title != null && title!.isNotEmpty) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.slate500,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: compact ? 16 : 24),
              FilledButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon, size: 18),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
