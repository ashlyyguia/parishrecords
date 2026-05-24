import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/donation_display.dart' as donation_display;

/// Visual identity for each admin finance module.
enum FinanceModuleKind {
  donations,
  certificateFees,
}

class FinanceModuleStyle {
  final FinanceModuleKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final Color accent;
  final Color accentSoft;
  final Color onAccent;
  final String emptyTitle;
  final String emptyHint;

  const FinanceModuleStyle({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.emptyTitle,
    required this.emptyHint,
  });

  static FinanceModuleStyle of(FinanceModuleKind kind) {
    switch (kind) {
      case FinanceModuleKind.donations:
        return const FinanceModuleStyle(
          kind: FinanceModuleKind.donations,
          title: 'Donations',
          subtitle: 'Cash and online donations (same records as Finance ledger)',
          icon: Icons.volunteer_activism_rounded,
          gradient: [Color(0xFF0D9488), Color(0xFF14B8A6), Color(0xFF5EEAD4)],
          accent: Color(0xFF0D9488),
          accentSoft: Color(0xFFCCFBF1),
          onAccent: Colors.white,
          emptyTitle: 'No donations yet',
          emptyHint: 'Record a gift to see it listed here.',
        );
      case FinanceModuleKind.certificateFees:
        return const FinanceModuleStyle(
          kind: FinanceModuleKind.certificateFees,
          title: 'Certificate Fees',
          subtitle: 'Sacramental document payments',
          icon: Icons.verified_outlined,
          gradient: [Color(0xFF3730A3), Color(0xFF4F46E5), Color(0xFF818CF8)],
          accent: Color(0xFF4F46E5),
          accentSoft: Color(0xFFE0E7FF),
          onAccent: Colors.white,
          emptyTitle: 'No certificate fees',
          emptyHint: 'Record a payment when a certificate is issued.',
        );
    }
  }
}

/// Full-page shell: gradient hero + scrollable body on soft tinted background.
class FinanceModulePage extends StatelessWidget {
  final FinanceModuleKind module;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingAction;

  const FinanceModulePage({
    super.key,
    required this.module,
    required this.body,
    this.actions = const [],
    this.floatingAction,
  });

  @override
  Widget build(BuildContext context) {
    final style = FinanceModuleStyle.of(module);

    return Scaffold(
      backgroundColor: style.accentSoft.withValues(alpha: 0.35),
      floatingActionButton: floatingAction,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: FinanceHeroHeader(style: style, actions: actions)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverToBoxAdapter(child: body),
          ),
        ],
      ),
    );
  }
}

class FinanceHeroHeader extends StatelessWidget {
  final FinanceModuleStyle style;
  final List<Widget> actions;

  const FinanceHeroHeader({
    super.key,
    required this.style,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: style.gradient,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: style.accent.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Icon(
              style.icon,
              size: 140,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Icon(style.icon, color: style.onAccent, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            style.title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: style.onAccent,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            style.subtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: style.onAccent.withValues(alpha: 0.88),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Toolbar chips: filter date, PDF, primary CTA — styled per module.
class FinanceToolbar extends StatelessWidget {
  final FinanceModuleStyle style;
  final DateTime? filterDate;
  final VoidCallback? onPickDate;
  final VoidCallback? onClearDate;
  final VoidCallback? onExportPdf;
  final bool pdfBusy;
  final String pdfLabel;
  final VoidCallback? onPrimary;
  final String primaryLabel;
  final IconData primaryIcon;

  const FinanceToolbar({
    super.key,
    required this.style,
    this.filterDate,
    this.onPickDate,
    this.onClearDate,
    this.onExportPdf,
    this.pdfBusy = false,
    this.pdfLabel = 'Export PDF',
    this.onPrimary,
    this.primaryLabel = 'Add',
    this.primaryIcon = Icons.add_rounded,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip({
      required VoidCallback? onTap,
      required Widget child,
      bool filled = false,
    }) {
      return Material(
        color: filled
            ? Colors.white
            : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: DefaultTextStyle(
              style: TextStyle(
                color: filled ? style.accent : style.onAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              child: IconTheme(
                data: IconThemeData(
                  color: filled ? style.accent : style.onAccent,
                  size: 18,
                ),
                child: child,
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (onPickDate != null) ...[
          chip(
            onTap: onPickDate,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_month_rounded),
                const SizedBox(width: 6),
                Text(
                  filterDate == null
                      ? 'All dates'
                      : DateFormat('MMM d, yyyy').format(filterDate!),
                ),
              ],
            ),
          ),
          if (filterDate != null && onClearDate != null)
            chip(
              onTap: onClearDate,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close_rounded),
                  SizedBox(width: 4),
                  Text('Clear'),
                ],
              ),
            ),
        ],
        if (onExportPdf != null)
          chip(
            onTap: pdfBusy ? null : onExportPdf,
            filled: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pdfBusy)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: style.accent,
                    ),
                  )
                else
                  const Icon(Icons.picture_as_pdf_rounded),
                const SizedBox(width: 6),
                Text(pdfLabel),
              ],
            ),
          ),
        if (onPrimary != null)
          chip(
            onTap: onPrimary,
            filled: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(primaryIcon),
                const SizedBox(width: 6),
                Text(primaryLabel),
              ],
            ),
          ),
      ],
    );
  }
}

class FinanceSummaryStrip extends StatelessWidget {
  final FinanceModuleStyle style;
  final String totalLabel;
  final String totalValue;
  final List<FinanceSummaryItem> items;

  const FinanceSummaryStrip({
    super.key,
    required this.style,
    required this.totalLabel,
    required this.totalValue,
    this.items = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: style.accent.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: style.accent.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: style.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(style.icon, color: style.accent, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      totalLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      totalValue,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: style.accent,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final crossCount = w > 700 ? 4 : (w > 420 ? 2 : 1);
              return GridView.count(
                crossAxisCount: crossCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: w > 420 ? 2.4 : 3.2,
                children: items
                    .map(
                      (item) => _MiniStatCard(
                        label: item.label,
                        value: item.value,
                        color: item.color ?? style.accent,
                        icon: item.icon,
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ],
    );
  }
}

class FinanceSummaryItem {
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;
  const FinanceSummaryItem({
    required this.label,
    required this.value,
    this.color,
    this.icon,
  });
}

class _MiniStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData? icon;

  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color,
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

class FinanceRecordCard extends StatelessWidget {
  final FinanceModuleStyle style;
  final String title;
  final String subtitle;
  final String amount;
  final IconData? leadingIcon;
  final Color? leadingColor;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Widget? trailingBadge;

  const FinanceRecordCard({
    super.key,
    required this.style,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.leadingIcon,
    this.leadingColor,
    this.onEdit,
    this.onDelete,
    this.trailingBadge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = leadingIcon ?? style.icon;
    final color = leadingColor ?? style.accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.15),
                    color.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 22),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (trailingBadge != null) ...[
                    const SizedBox(height: 6),
                    trailingBadge!,
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.edit_rounded, size: 20, color: color),
                      tooltip: 'Edit',
                      onPressed: onEdit,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: Color(0xFFDC2626),
                      ),
                      tooltip: 'Delete',
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FinanceCategoryBadge extends StatelessWidget {
  final String label;
  final Color color;

  const FinanceCategoryBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class FinanceEmptyState extends StatelessWidget {
  final FinanceModuleStyle style;

  const FinanceEmptyState({super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: style.accent.withValues(alpha: 0.1),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: style.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(style.icon, size: 40, color: style.accent),
          ),
          const SizedBox(height: 16),
          Text(
            style.emptyTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            style.emptyHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class FinanceSectionTitle extends StatelessWidget {
  final String title;
  final FinanceModuleStyle style;
  final Widget? trailing;

  const FinanceSectionTitle({
    super.key,
    required this.title,
    required this.style,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: style.accent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Themed bottom sheet for record forms.
Future<T?> showFinanceFormSheet<T>({
  required BuildContext context,
  required FinanceModuleStyle style,
  required String title,
  required Widget child,
  required List<Widget> actions,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: style.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(style.icon, color: style.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: child,
                ),
              ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  child: Row(
                    children: actions
                        .map(
                          (w) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: w,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                )
              else
                const SizedBox(height: 12),
            ],
          ),
        ),
      );
    },
  );
}

Color donationCategoryColor(String cat) {
  switch (cat.toLowerCase()) {
    case 'tithes':
      return const Color(0xFF2563EB);
    case 'projects':
      return const Color(0xFFEA580C);
    case 'outreach':
      return const Color(0xFFDB2777);
    default:
      return const Color(0xFF0D9488);
  }
}

IconData donationCategoryIcon(String cat) {
  switch (cat.toLowerCase()) {
    case 'tithes':
      return Icons.church_rounded;
    case 'projects':
      return Icons.construction_rounded;
    case 'outreach':
      return Icons.favorite_rounded;
    default:
      return Icons.card_giftcard_rounded;
  }
}

String formatPaymentMethod(String method) =>
    donation_display.formatPaymentMethod(method);

