import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// From / To date pickers used on record list screens.
class RecordDateRangeFilters extends StatelessWidget {
  const RecordDateRangeFilters({
    super.key,
    required this.from,
    required this.to,
    required this.onFromChanged,
    required this.onToChanged,
    this.onClear,
    this.fromLabel = 'From',
    this.toLabel = 'To',
    this.layout = RecordDateFilterLayout.wrap,
  });

  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTime?> onFromChanged;
  final ValueChanged<DateTime?> onToChanged;
  final VoidCallback? onClear;
  final String fromLabel;
  final String toLabel;
  final RecordDateFilterLayout layout;

  Future<void> _pickDate(
    BuildContext context, {
    required DateTime? current,
    required ValueChanged<DateTime?> onChanged,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMd();

    final fromBtn = _DateFilterButton(
      label: from == null ? fromLabel : '${fromLabel}: ${df.format(from!)}',
      onTap: () => _pickDate(context, current: from, onChanged: onFromChanged),
    );
    final toBtn = _DateFilterButton(
      label: to == null ? toLabel : '${toLabel}: ${df.format(to!)}',
      onTap: () => _pickDate(context, current: to, onChanged: onToChanged),
    );

    final clearBtn = (from != null || to != null) && onClear != null
        ? IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.clear),
            tooltip: 'Clear dates',
          )
        : null;

    if (layout == RecordDateFilterLayout.row) {
      return Row(
        children: [
          Expanded(child: fromBtn),
          const SizedBox(width: 8),
          Expanded(child: toBtn),
          if (clearBtn != null) clearBtn,
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        fromBtn,
        toBtn,
        if (clearBtn != null) clearBtn,
      ],
    );
  }
}

enum RecordDateFilterLayout { wrap, row }

class _DateFilterButton extends StatelessWidget {
  const _DateFilterButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
