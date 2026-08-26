import 'package:flutter/material.dart';

import '../models/baptismal_register_row.dart';
import '../services/baptismal_row_validation.dart';

/// Editable review table for OCR-extracted baptismal register rows.
///
/// Responsive by width:
///  * **Wide screens (>= [_wideBreakpoint]px)** — a columnar table whose
///    columns mirror the physical register left-to-right (No. → Observations),
///    one register line per table row, with a pinned header, a visible
///    horizontal scrollbar (so the last column is always reachable), and its
///    own vertical scroll for the rows.
///  * **Narrow screens** — one card per register line, fields stacked
///    vertically, so it stays usable on a phone without horizontal scrolling
///    through ten columns.
///
/// Both layouts manage their own scrolling, so the widget expects a **bounded
/// height** from its parent (e.g. an `Expanded`), not to be dropped inside a
/// `SingleChildScrollView`. Both share the same widget keys, flag colours,
/// validation, and callbacks, so the hosting page (and its tests) work
/// identically in either.
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
class BaptismalOcrReviewTable extends StatefulWidget {
  const BaptismalOcrReviewTable({
    super.key,
    required this.rows,
    required this.issues,
    required this.onChanged,
    required this.onSelectedChanged,
    this.onLineNoChanged,
    this.highlightedRow,
    this.onRowTap,
    this.onInsertRowBelow,
    this.onDeleteRow,
    this.onMergeWithNext,
  });

  final List<BaptismalRegisterRow> rows;
  final List<RowIssue> issues;
  final void Function(int rowIndex, String field, String value) onChanged;
  final void Function(int rowIndex, bool selected) onSelectedChanged;

  /// Edits the row's `lineNo`. `lineNo` is read off the printed NO. column
  /// and falls back to a fabricated sequential value (`"1"`, `"2"`, ...)
  /// when that column is unreadable -- a spread starting at physical
  /// register line 47 would otherwise silently save as lines 1-9. It is what
  /// a clerk uses to find the physical entry, so it must be correctable like
  /// every other field, not rendered as static text.
  final void Function(int rowIndex, String value)? onLineNoChanged;
  final int? highlightedRow;
  final void Function(int rowIndex)? onRowTap;

  /// Row-set edits so a reviewer can correct over/under-counted OCR output:
  /// insert a blank row below [rowIndex], delete it, or merge it with the row
  /// below (the fix for one entry OCR split across two rows).
  final void Function(int rowIndex)? onInsertRowBelow;
  final void Function(int rowIndex)? onDeleteRow;
  final void Function(int rowIndex)? onMergeWithNext;

  @override
  State<BaptismalOcrReviewTable> createState() =>
      _BaptismalOcrReviewTableState();
}

class _BaptismalOcrReviewTableState extends State<BaptismalOcrReviewTable> {
  /// Below this width the ten-column table can't fit, so the card layout is
  /// used instead. Above 800 (the default widget-test surface) so tests keep
  /// exercising the card layout unless they explicitly widen the view.
  static const double _wideBreakpoint = 900;

  /// Pixel width of each register column in the wide table. Sized to fit the
  /// handwriting these columns actually hold (names/parents/sponsors need
  /// room; the legitimacy check-mark needs almost none).
  static const Map<String, double> _columnWidths = {
    'nameOfChild': 150,
    'placeAndBirthDate': 172,
    'legitimacy': 72,
    'parents': 160,
    'residentsOf': 140,
    'dateOfBaptism': 120,
    'minister': 132,
    'sponsors': 150,
    'observations': 150,
  };
  static const double _selectWidth = 44;
  static const double _lineNoWidth = 60;
  static const double _menuWidth = 40;

  // Separate controllers so each scrollbar attaches to exactly one view.
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  bool get _hasRowActions =>
      widget.onInsertRowBelow != null ||
      widget.onDeleteRow != null ||
      widget.onMergeWithNext != null;

  Widget _rowMenu(BuildContext context, int index) {
    final canMerge =
        widget.onMergeWithNext != null && index < widget.rows.length - 1;
    return PopupMenuButton<String>(
      key: ValueKey('row-menu-$index'),
      icon: const Icon(Icons.more_vert, size: 18),
      tooltip: 'Row actions',
      onSelected: (v) {
        switch (v) {
          case 'insert':
            widget.onInsertRowBelow?.call(index);
            break;
          case 'merge':
            widget.onMergeWithNext?.call(index);
            break;
          case 'delete':
            widget.onDeleteRow?.call(index);
            break;
        }
      },
      itemBuilder: (context) => [
        if (widget.onInsertRowBelow != null)
          const PopupMenuItem(
            value: 'insert',
            child: Text('Insert blank row below'),
          ),
        if (canMerge)
          const PopupMenuItem(
            value: 'merge',
            child: Text('Merge with row below'),
          ),
        if (widget.onDeleteRow != null)
          const PopupMenuItem(value: 'delete', child: Text('Delete row')),
      ],
    );
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  double get _totalWidth {
    var w = _selectWidth + _lineNoWidth + (_hasRowActions ? _menuWidth : 0);
    for (final key in baptismalFieldKeys) {
      w += _columnWidths[key] ?? 140;
    }
    return w;
  }

  /// Finds the issue to show for one cell.
  ///
  /// A field can theoretically collect more than one issue (e.g. a blocking
  /// "required" issue and a non-blocking duplicate warning added by a caller
  /// that doesn't short-circuit). A blocking issue always wins so the cell
  /// never shows a soft warning when saving is actually impossible.
  RowIssue? _issueFor(int rowIndex, String field) {
    RowIssue? found;
    for (final issue in widget.issues) {
      if (issue.rowIndex != rowIndex || issue.field != field) continue;
      if (issue.blocking) return issue;
      found ??= issue;
    }
    return found;
  }

  /// The fill colour that flags a cell (or null when nothing needs flagging).
  /// Shared by both layouts so the red/blue/amber meaning is identical.
  Color? _fillFor(BuildContext context, OcrField field, RowIssue? issue) {
    final scheme = Theme.of(context).colorScheme;
    if (issue != null && issue.blocking) {
      return scheme.errorContainer.withValues(alpha: 0.35);
    }
    if (field.inherited) return Colors.blue.withValues(alpha: 0.10);
    if (field.needsReview) return Colors.amber.withValues(alpha: 0.18);
    return null;
  }

  /// The verify-me hint for an inherited or low-confidence field, or null.
  String? _flagMessage(OcrField field) {
    if (field.inherited) return 'Carried down from the row above — verify it';
    if (field.needsReview) return 'Low OCR confidence — verify this value';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) return _wideTable(context);
        return _cardsList(context);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Wide (desktop/tablet) layout: a columnar table, No. -> Observations, with a
  // pinned header and always-visible horizontal scrollbar.
  // ---------------------------------------------------------------------------

  Widget _wideTable(BuildContext context) {
    return Scrollbar(
      controller: _horizontal,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _horizontal,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _totalWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerRow(context),
              Expanded(
                child: Scrollbar(
                  controller: _vertical,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _vertical,
                    padding: EdgeInsets.zero,
                    itemCount: widget.rows.length,
                    itemBuilder: (context, i) =>
                        _tableRow(context, i, widget.rows[i]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: scheme.primary,
    );
    return Container(
      color: scheme.primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_hasRowActions) const SizedBox(width: _menuWidth),
          const SizedBox(width: _selectWidth),
          _headerCell('No.', _lineNoWidth, style, required: false),
          for (final key in baptismalFieldKeys)
            _headerCell(
              baptismalFieldLabels[key] ?? key,
              _columnWidths[key] ?? 140,
              style,
              required: baptismalRequiredFields.contains(key),
            ),
        ],
      ),
    );
  }

  Widget _headerCell(
    String label,
    double width,
    TextStyle? style, {
    required bool required,
  }) {
    // A required column's header carries the visible " *" (matching the
    // register's own convention) but the glyph alone isn't the accessible
    // signal: excludeSemantics swaps the raw "<label> *" node for an explicit
    // "<label>, required" announcement, exactly as the cell labels do.
    final child = required
        ? Semantics(
            label: '$label, required',
            excludeSemantics: true,
            child: Text('$label *', style: style),
          )
        : Text(label, style: style);
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: child,
      ),
    );
  }

  Widget _tableRow(BuildContext context, int index, BaptismalRegisterRow row) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = widget.highlightedRow == index;
    return Container(
      key: ValueKey('row-$index'),
      decoration: BoxDecoration(
        color: highlighted ? scheme.primary.withValues(alpha: 0.06) : null,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hasRowActions)
            SizedBox(width: _menuWidth, child: _rowMenu(context, index)),
          SizedBox(
            width: _selectWidth,
            child: Checkbox(
              key: ValueKey('row-select-$index'),
              value: row.selected,
              onChanged: (v) => widget.onSelectedChanged(index, v ?? false),
            ),
          ),
          SizedBox(
            width: _lineNoWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: TextFormField(
                key: ValueKey('line-no-$index'),
                initialValue: row.lineNo,
                enabled: widget.onLineNoChanged != null,
                onChanged: widget.onLineNoChanged == null
                    ? null
                    : (v) => widget.onLineNoChanged!(index, v),
                style: Theme.of(context).textTheme.bodySmall,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                ),
              ),
            ),
          ),
          for (final key in baptismalFieldKeys)
            _tableCell(context, index, row, key),
        ],
      ),
    );
  }

  Widget _tableCell(
    BuildContext context,
    int rowIndex,
    BaptismalRegisterRow row,
    String key,
  ) {
    final field = row.field(key);
    final issue = _issueFor(rowIndex, key);
    final fill = _fillFor(context, field, issue);
    final flagMessage = _flagMessage(field);

    Widget cell = TextFormField(
      key: ValueKey('cell-$rowIndex-$key'),
      initialValue: field.value,
      onChanged: (v) => widget.onChanged(rowIndex, key, v),
      minLines: 1,
      maxLines: 3,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: InputDecoration(
        filled: fill != null,
        fillColor: fill,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        border: const OutlineInputBorder(),
        errorMaxLines: 2,
        helperMaxLines: 2,
        errorText: issue != null && issue.blocking ? issue.message : null,
        helperText: issue != null && !issue.blocking ? issue.message : null,
      ),
    );

    // Inherited / low-confidence cells carry no RowIssue message, so their
    // only textual signal in the compact table is a hover/long-press tooltip
    // (the fill colour is the at-a-glance one).
    if (issue == null && flagMessage != null) {
      cell = Tooltip(message: flagMessage, child: cell);
    }

    return SizedBox(
      width: _columnWidths[key] ?? 140,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: cell,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Narrow (phone) layout: one card per register line, in its own scroll view.
  // ---------------------------------------------------------------------------

  Widget _cardsList(BuildContext context) {
    return ListView.builder(
      controller: _vertical,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: widget.rows.length,
      itemBuilder: (context, i) => _rowCard(context, i, widget.rows[i]),
    );
  }

  Widget _rowCard(BuildContext context, int index, BaptismalRegisterRow row) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = widget.highlightedRow == index;

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
        onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(index),
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
                    onChanged: (v) =>
                        widget.onSelectedChanged(index, v ?? false),
                  ),
                  Text('Line', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: TextFormField(
                      key: ValueKey('line-no-$index'),
                      initialValue: row.lineNo,
                      enabled: widget.onLineNoChanged != null,
                      onChanged: widget.onLineNoChanged == null
                          ? null
                          : (v) => widget.onLineNoChanged!(index, v),
                      style: Theme.of(context).textTheme.titleSmall,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_hasRowActions) _rowMenu(context, index),
                ],
              ),
              const SizedBox(height: 4),
              for (final key in baptismalFieldKeys)
                _cell(context, index, row, key),
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
    final field = row.field(key);
    final issue = _issueFor(rowIndex, key);
    final fieldLabel = baptismalFieldLabels[key] ?? key;
    final isRequired = baptismalRequiredFields.contains(key);
    final fill = _fillFor(context, field, issue);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextFormField(
        key: ValueKey('cell-$rowIndex-$key'),
        initialValue: field.value,
        onChanged: (v) => widget.onChanged(rowIndex, key, v),
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(
          // A required field's label carries the asterisk visibly (matches
          // the register's own convention) but the glyph alone is not the
          // accessible signal: `excludeSemantics` drops the raw "<label> *"
          // text node from the semantics tree and replaces it with an
          // explicit "<label>, required" announcement, mirroring how the
          // inherited/needsReview icons below pair a visual mark with a
          // real tooltip string instead of relying on shape/colour alone.
          label: isRequired
              ? Semantics(
                  label: '$fieldLabel, required',
                  excludeSemantics: true,
                  child: Text('$fieldLabel *'),
                )
              : Text(fieldLabel),
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
