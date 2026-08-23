import 'package:flutter/material.dart';

import '../models/baptismal_register_row.dart';
import '../services/baptismal_row_validation.dart';

/// Editable review table for OCR-extracted baptismal register rows.
///
/// One card per register line so it stays usable on a phone; a wide data grid
/// would force horizontal scrolling through nine columns.
///
/// OCR on handwriting is never trusted outright — every cell here is
/// editable, and three colours flag three different reasons a human should
/// look before saving:
///  * red (`errorContainer`) — a blocking validation issue; save is blocked.
///  * blue — the value was inherited (fill-down from the row above, e.g. a
///    repeated minister or baptism date) rather than actually read for this
///    row.
///  * amber — OCR read it, but with low confidence.
/// Editing a field marks it [OcrField.edited], which turns the flag off —
/// once a human has looked at a value it should stop nagging.
class BaptismalOcrReviewTable extends StatelessWidget {
  const BaptismalOcrReviewTable({
    super.key,
    required this.rows,
    required this.issues,
    required this.onChanged,
    required this.onSelectedChanged,
    this.highlightedRow,
    this.onRowTap,
  });

  final List<BaptismalRegisterRow> rows;
  final List<RowIssue> issues;
  final void Function(int rowIndex, String field, String value) onChanged;
  final void Function(int rowIndex, bool selected) onSelectedChanged;
  final int? highlightedRow;
  final void Function(int rowIndex)? onRowTap;

  /// Finds the issue to show for one cell.
  ///
  /// A field can theoretically collect more than one issue (e.g. a blocking
  /// "required" issue and a non-blocking duplicate warning added by a caller
  /// that doesn't short-circuit). A blocking issue always wins so the cell
  /// never shows a soft warning when saving is actually impossible.
  RowIssue? _issueFor(int rowIndex, String field) {
    RowIssue? found;
    for (final issue in issues) {
      if (issue.rowIndex != rowIndex || issue.field != field) continue;
      if (issue.blocking) return issue;
      found ??= issue;
    }
    return found;
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) _rowCard(context, i, rows[i]),
      ],
    );
  }

  Widget _rowCard(BuildContext context, int index, BaptismalRegisterRow row) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = highlightedRow == index;

    return Card(
      key: ValueKey('row-$index'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: highlighted
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.4),
          width: highlighted ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onRowTap == null ? null : () => onRowTap!(index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    key: ValueKey('row-select-$index'),
                    value: row.selected,
                    onChanged: (v) => onSelectedChanged(index, v ?? false),
                  ),
                  Text(
                    'Line ${row.lineNo}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (final key in baptismalFieldKeys) _cell(context, index, row, key),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    int rowIndex,
    BaptismalRegisterRow row,
    String key,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final field = row.field(key);
    final issue = _issueFor(rowIndex, key);

    Color? fill;
    if (issue != null && issue.blocking) {
      fill = scheme.errorContainer.withValues(alpha: 0.35);
    } else if (field.inherited) {
      fill = Colors.blue.withValues(alpha: 0.10);
    } else if (field.needsReview) {
      fill = Colors.amber.withValues(alpha: 0.18);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextFormField(
        key: ValueKey('cell-$rowIndex-$key'),
        initialValue: field.value,
        onChanged: (v) => onChanged(rowIndex, key, v),
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: baptismalFieldLabels[key],
          filled: fill != null,
          fillColor: fill,
          isDense: true,
          border: const OutlineInputBorder(),
          errorText: issue != null && issue.blocking ? issue.message : null,
          helperText: issue != null && !issue.blocking ? issue.message : null,
          suffixIcon: field.inherited
              ? const Tooltip(
                  message: 'Carried down from the row above — verify it',
                  child: Icon(Icons.arrow_downward, size: 18),
                )
              : field.needsReview
                  ? const Tooltip(
                      message: 'Low OCR confidence — verify this value',
                      child: Icon(Icons.help_outline, size: 18),
                    )
                  : null,
        ),
      ),
    );
  }
}
