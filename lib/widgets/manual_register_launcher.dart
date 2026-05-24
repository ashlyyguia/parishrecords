import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Opens manual parish register entry after staff picks the sacrament type.
class ManualRegisterLauncher {
  ManualRegisterLauncher._();

  static const _options = [
    _SacramentOption(
      type: 'baptism',
      label: 'Baptism Register',
      subtitle: 'Volume / series rows for baptisms',
      icon: Icons.water_drop_outlined,
      color: Color(0xFF3B82F6),
      route: '/staff/records/manual-baptism',
    ),
    _SacramentOption(
      type: 'marriage',
      label: 'Marriage Register',
      subtitle: 'Volume / series rows for marriages',
      icon: Icons.favorite_outline,
      color: Color(0xFFEC4899),
      route: '/staff/records/manual-marriage',
    ),
  ];

  /// Shows sacrament picker, then navigates to the matching manual register form.
  static Future<void> open(
    BuildContext context, {
    Object? extra,
  }) async {
    final theme = Theme.of(context);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Manual Register',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose the sacrament register you want to enter.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                for (final opt in _options) ...[
                  _SacramentTile(option: opt),
                  if (opt != _options.last) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !context.mounted) return;

    final route = _options
        .firstWhere((o) => o.type == selected, orElse: () => _options.first)
        .route;
    context.push(route, extra: extra);
  }
}

class _SacramentOption {
  final String type;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;

  const _SacramentOption({
    required this.type,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.route,
  });
}

class _SacramentTile extends StatelessWidget {
  final _SacramentOption option;

  const _SacramentTile({required this.option});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: option.color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pop(context, option.type),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: option.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(option.icon, color: option.color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
