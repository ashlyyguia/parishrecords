// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../../widgets/app_card.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_search_bar.dart';
import '../../widgets/page_header.dart';

/// Modern Admin Design System Components
class AdminDesignSystem {
  // Card Styles — flat bordered to match the app-wide [AppCard].
  static BoxDecoration cardDecoration(BuildContext context) {
    return AppCard.decoration();
  }

  static BoxDecoration gradientCardDecoration(
    BuildContext context,
    List<Color> colors,
  ) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: colors.first.withOpacity(0.3),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  // Page Background
  static BoxDecoration pageBackground(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colorScheme.surface,
          colorScheme.surfaceContainerHighest.withOpacity(0.3),
          colorScheme.surface,
        ],
      ),
    );
  }

  // Header Style — delegates to the app-wide uniform [PageHeader].
  static Widget pageHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    List<Widget>? actions,
  }) {
    return PageHeader(
      icon: icon,
      title: title,
      subtitle: subtitle,
      actions: actions ?? const [],
    );
  }

  // Modern Search Bar — delegates to the app-wide uniform [AppSearchBar].
  static Widget searchBar(
    BuildContext context, {
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
    VoidCallback? onClear,
  }) {
    return AppSearchBar(
      controller: controller,
      hintText: hint,
      onChanged: onChanged,
      onClear: onClear,
    );
  }

  // Modern Action Button — styled to sit on the light [PageHeader].
  static Widget actionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
    bool isPrimary = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = color ?? colorScheme.primary;
    final isCompact = MediaQuery.sizeOf(context).width < 720;
    final padding = EdgeInsets.symmetric(
      horizontal: isCompact ? 12 : 20,
      vertical: isCompact ? 10 : 12,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    if (isPrimary) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: isCompact ? 16 : 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: Colors.white,
          padding: padding,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: shape,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: isCompact ? 16 : 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: accentColor,
        side: BorderSide(color: accentColor.withOpacity(0.5)),
        padding: padding,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: shape,
      ),
    );
  }

  // Stat Card
  static Widget statCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? trend,
    bool isPositive = true,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isPositive
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPositive ? Icons.trending_up : Icons.trending_down,
                        color: isPositive ? Colors.green : Colors.red,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        trend,
                        style: TextStyle(
                          color: isPositive ? Colors.green : Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  // Modern Data Table
  static Widget modernDataTable({
    required BuildContext context,
    required List<String> columns,
    required List<List<Widget>> rows,
    required List<VoidCallback> onRowTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: cardDecoration(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              colorScheme.surfaceContainerHighest.withOpacity(0.5),
            ),
            dataRowMinHeight: 60,
            headingTextStyle: TextStyle(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
            columns: columns
                .map((col) => DataColumn(label: Text(col)))
                .toList(),
            rows: List.generate(
              rows.length,
              (index) => DataRow(
                onSelectChanged: (_) => onRowTap[index](),
                cells: rows[index].map((cell) => DataCell(cell)).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Status Badge
  static Widget statusBadge(BuildContext context, String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Section Title
  static Widget sectionTitle(
    BuildContext context,
    String title, {
    String? action,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('$action clicked')));
            },
            child: Text(action),
          ),
      ],
    );
  }

  // Empty State — delegates to the app-wide uniform [AppEmptyState].
  static Widget emptyState(
    BuildContext context, {
    required String message,
    required IconData icon,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return AppEmptyState(
      icon: icon,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

extension AdminContext on BuildContext {
  bool get isWide => MediaQuery.of(this).size.width >= 1000;
  bool get isMedium => MediaQuery.of(this).size.width >= 600;
  double get contentMaxWidth => isWide ? 1200 : double.infinity;
}
