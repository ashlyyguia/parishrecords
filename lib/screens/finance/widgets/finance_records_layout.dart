import 'package:flutter/material.dart';

import '../../admin/widgets/finance_module_design.dart';
import '../../../widgets/record_date_range_filters.dart';

/// Shared finance ledger shell: header, from/to filters, actions, body.
class FinanceRecordsLayout extends StatelessWidget {
  const FinanceRecordsLayout({
    super.key,
    required this.style,
    required this.title,
    required this.subtitle,
    required this.from,
    required this.to,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onClearDates,
    required this.onRefresh,
    required this.body,
    this.extraFilters,
    this.exportButton,
    this.summaryChips = const [],
    this.recordCount,
  });

  final FinanceModuleStyle style;
  final String title;
  final String subtitle;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTime?> onFromChanged;
  final ValueChanged<DateTime?> onToChanged;
  final VoidCallback onClearDates;
  final VoidCallback onRefresh;
  final Widget body;
  final Widget? extraFilters;
  final Widget? exportButton;
  final List<Widget> summaryChips;
  final int? recordCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeaderBar(style: style, title: title, subtitle: subtitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _FilterCard(
                style: style,
                from: from,
                to: to,
                onFromChanged: onFromChanged,
                onToChanged: onToChanged,
                onClearDates: onClearDates,
                extraFilters: extraFilters,
                onRefresh: onRefresh,
                exportButton: exportButton,
              ),
            ),
            if (summaryChips.isNotEmpty || recordCount != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: summaryChips,
                      ),
                    ),
                    if (recordCount != null)
                      Text(
                        '$recordCount record${recordCount == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.style,
    required this.title,
    required this.subtitle,
  });

  final FinanceModuleStyle style;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: style.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(style.icon, color: style.onAccent, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: style.onAccent,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: style.onAccent.withValues(alpha: 0.9),
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

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.style,
    required this.from,
    required this.to,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onClearDates,
    required this.extraFilters,
    required this.onRefresh,
    required this.exportButton,
  });

  final FinanceModuleStyle style;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTime?> onFromChanged;
  final ValueChanged<DateTime?> onToChanged;
  final VoidCallback onClearDates;
  final Widget? extraFilters;
  final VoidCallback onRefresh;
  final Widget? exportButton;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: style.accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: style.accent.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_list_rounded, size: 20, color: style.accent),
              const SizedBox(width: 8),
              Text(
                'Filters',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final dateFilters = RecordDateRangeFilters(
                from: from,
                to: to,
                onFromChanged: onFromChanged,
                onToChanged: onToChanged,
                onClear: onClearDates,
                fromLabel: 'From date',
                toLabel: 'To date',
                layout: wide
                    ? RecordDateFilterLayout.row
                    : RecordDateFilterLayout.wrap,
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 3, child: dateFilters),
                    if (extraFilters != null) ...[
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: extraFilters!),
                    ],
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: onRefresh,
                      icon: Icon(Icons.refresh_rounded, color: style.accent),
                    ),
                    if (exportButton != null) exportButton!,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  dateFilters,
                  if (extraFilters != null) ...[
                    const SizedBox(height: 10),
                    extraFilters!,
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Refresh',
                        onPressed: onRefresh,
                        icon: Icon(Icons.refresh_rounded, color: style.accent),
                      ),
                      if (exportButton != null) Expanded(child: exportButton!),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Summary pill for finance record pages.
class FinanceSummaryChip extends StatelessWidget {
  const FinanceSummaryChip({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width records table card.
class FinanceRecordsTableCard extends StatelessWidget {
  const FinanceRecordsTableCard({
    super.key,
    required this.style,
    required this.child,
  });

  final FinanceModuleStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: style.accent.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }
}
