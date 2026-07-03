import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Opens manual parish register entry after staff picks the sacrament type.
class ManualRegisterLauncher {
  ManualRegisterLauncher._();

  static const _scanChoice = '_scan_certificate';

  static List<_SacramentOption> _optionsFor(String recordsBasePath) => [
    _SacramentOption(
      type: 'baptism',
      label: 'Baptism Register',
      subtitle: 'Volume / series rows for baptisms',
      icon: Icons.water_drop_outlined,
      color: const Color(0xFF3B82F6),
      route: '$recordsBasePath/manual-baptism',
    ),
    _SacramentOption(
      type: 'marriage',
      label: 'Marriage Register',
      subtitle: 'Volume / series rows for marriages',
      icon: Icons.favorite_outline,
      color: const Color(0xFFEC4899),
      route: '$recordsBasePath/manual-marriage',
    ),
    _SacramentOption(
      type: 'confirmation',
      label: 'Confirmation Record',
      subtitle: 'Full confirmation entry form',
      icon: Icons.verified_outlined,
      color: const Color(0xFF8B5CF6),
      route: '$recordsBasePath/new/confirmation',
    ),
    _SacramentOption(
      type: 'funeral',
      label: 'Funeral Record',
      subtitle: 'Full death / funeral entry form',
      icon: Icons.church_outlined,
      color: const Color(0xFF64748B),
      route: '$recordsBasePath/new/death',
    ),
  ];

  /// Shows sacrament picker, then navigates to the matching manual register form.
  static Future<void> open(
    BuildContext context, {
    Object? extra,
    String recordsBasePath = '/staff/records',
  }) async {
    final options = _optionsFor(recordsBasePath);
    final theme = Theme.of(context);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
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
                for (final opt in options) ...[
                  _SacramentTile(option: opt),
                  if (opt != options.last) const SizedBox(height: 8),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, _scanChoice),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scan / upload certificate instead'),
                ),
                const SizedBox(height: 4),
                Text(
                  'OCR reads the certificate and pre-fills the required '
                  'fields for any record type.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !context.mounted) return;

    if (selected == _scanChoice) {
      final scanPath = recordsBasePath.startsWith('/admin')
          ? '/admin/certificate-scan'
          : '/staff/certificate-scan';
      context.push(scanPath);
      return;
    }

    final route = options
        .firstWhere((o) => o.type == selected, orElse: () => options.first)
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
