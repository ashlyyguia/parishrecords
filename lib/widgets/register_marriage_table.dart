import 'package:flutter/material.dart';

import '../models/register_marriage_entry.dart';

/// Parish marriage register layout: one **No.** with two lines (Man / Woman).
class RegisterMarriageTable extends StatelessWidget {
  const RegisterMarriageTable({
    super.key,
    required this.entries,
    required this.fillGeneration,
    this.onChanged,
    this.onSelectionChanged,
    this.onRemove,
    this.showCheckboxes = true,
  });

  final List<RegisterMarriageEntry> entries;
  final int fillGeneration;
  final VoidCallback? onChanged;
  final VoidCallback? onSelectionChanged;
  final void Function(int index)? onRemove;
  final bool showCheckboxes;

  static const _minTableWidth = 2480.0;

  static const _partyColumns = [
    _Col('Contracting Parties', 168),
    _Col('Legal Status', 96),
    _Col('Actual Address', 148),
    _Col('Dates & Place of Birth', 156),
    _Col('Dates & Place of Baptism', 156),
  ];

  static const _sharedColumns = [
    _Col('Date of Marriage', 132),
    _Col('Parents', 168),
    _Col('Sponsors of Marriage', 168),
    _Col('Minister', 128),
    _Col('License Number', 112),
    _Col('Observations', 140),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.table_chart_outlined, size: 56, color: cs.outline),
              const SizedBox(height: 12),
              const Text(
                'No register entries',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Scroll horizontally. Each No. has a Man row and a Woman row.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      );
    }

    final tableRows = <TableRow>[
      _headerRow(context, showCheckboxes, onRemove != null),
    ];
    for (var i = 0; i < entries.length; i++) {
      tableRows.addAll(
        _entryRows(
          context,
          index: i,
          entry: entries[i],
          fillGeneration: fillGeneration,
          showCheckbox: showCheckboxes,
          showRemove: onRemove != null,
          onChanged: onChanged,
          onSelectionChanged: onSelectionChanged,
          onRemove: onRemove == null ? null : () => onRemove!(i),
          stripe: i.isEven,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: _minTableWidth),
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder.all(
              color: cs.outlineVariant.withValues(alpha: 0.8),
              width: 1,
            ),
            columnWidths: _columnWidths(showCheckboxes, onRemove != null),
            children: tableRows,
          ),
        ),
      ),
    );
  }

  static Map<int, TableColumnWidth> _columnWidths(
    bool showCheckbox,
    bool showRemove,
  ) {
    var col = 0;
    final widths = <int, TableColumnWidth>{};
    if (showCheckbox) {
      widths[col++] = const FixedColumnWidth(44);
    }
    widths[col++] = const FixedColumnWidth(52);
    widths[col++] = const FixedColumnWidth(44);
    for (final c in _partyColumns) {
      widths[col++] = FixedColumnWidth(c.width);
    }
    for (final c in _sharedColumns) {
      widths[col++] = FixedColumnWidth(c.width);
    }
    if (showRemove) {
      widths[col] = const FixedColumnWidth(44);
    }
    return widths;
  }

  static TableRow _headerRow(
    BuildContext context,
    bool showCheckbox,
    bool showRemove,
  ) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: cs.onPrimaryContainer,
        );

    Widget h(String text) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Text(text, style: style),
        );

    return TableRow(
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.85),
      ),
      children: [
        if (showCheckbox) h(''),
        h('No'),
        h('Party'),
        for (final c in _partyColumns) h(c.label),
        for (final c in _sharedColumns) h(c.label),
        if (showRemove) h(''),
      ],
    );
  }

  static List<TableRow> _entryRows(
    BuildContext context, {
    required int index,
    required RegisterMarriageEntry entry,
    required int fillGeneration,
    required bool showCheckbox,
    required bool showRemove,
    required bool stripe,
    VoidCallback? onChanged,
    VoidCallback? onSelectionChanged,
    VoidCallback? onRemove,
  }) {
    final cs = Theme.of(context).colorScheme;
    final bg = stripe
        ? cs.surfaceContainerLow.withValues(alpha: 0.5)
        : cs.surface;

    void touch(void Function() fn) {
      fn();
      onChanged?.call();
    }

    TableRow row({
      required String partyLabel,
      required IconData partyIcon,
      required MarriagePartyInfo party,
      required String idPrefix,
      required bool isFirstLine,
    }) {
      return TableRow(
        key: ValueKey('m-$index-$partyLabel-gen$fillGeneration'),
        decoration: BoxDecoration(color: bg),
        children: [
          if (showCheckbox)
            isFirstLine
                ? _SpanCell(
                    height: 112,
                    child: Checkbox(
                      value: entry.selected,
                      onChanged: (v) {
                        entry.selected = v ?? false;
                        (onSelectionChanged ?? onChanged)?.call();
                      },
                    ),
                  )
                : const SizedBox.shrink(),
          isFirstLine
              ? _SpanCell(
                  height: 112,
                  child: _RegisterField(
                    key: ValueKey('m-$index-no'),
                    label: '',
                    hint: 'No',
                    fillGeneration: fillGeneration,
                    value: entry.lineNo ?? '${index + 1}',
                    width: 44,
                    onChanged: (v) => touch(() => entry.lineNo = v),
                  ),
                )
              : const SizedBox.shrink(),
          _PartyBadge(label: partyLabel, icon: partyIcon),
          _RegisterField(
            key: ValueKey('$idPrefix-name'),
            label: '',
            hint: 'Name',
            fillGeneration: fillGeneration,
            value: party.name,
            width: _partyColumns[0].width - 12,
            onChanged: (v) {
              party.name = v;
              onChanged?.call();
            },
          ),
          _RegisterField(
            key: ValueKey('$idPrefix-legal'),
            label: '',
            hint: 'Status',
            fillGeneration: fillGeneration,
            value: party.legalStatus,
            width: _partyColumns[1].width - 12,
            onChanged: (v) {
              party.legalStatus = v;
              onChanged?.call();
            },
          ),
          _RegisterField(
            key: ValueKey('$idPrefix-addr'),
            label: '',
            hint: 'Address',
            fillGeneration: fillGeneration,
            value: party.actualAddress,
            width: _partyColumns[2].width - 12,
            maxLines: 2,
            onChanged: (v) {
              party.actualAddress = v;
              onChanged?.call();
            },
          ),
          _RegisterField(
            key: ValueKey('$idPrefix-birth'),
            label: '',
            hint: 'Birth',
            fillGeneration: fillGeneration,
            value: party.datesPlaceOfBirth,
            width: _partyColumns[3].width - 12,
            maxLines: 2,
            onChanged: (v) {
              party.datesPlaceOfBirth = v;
              onChanged?.call();
            },
          ),
          _RegisterField(
            key: ValueKey('$idPrefix-baptism'),
            label: '',
            hint: 'Baptism',
            fillGeneration: fillGeneration,
            value: party.datesPlaceOfBaptism,
            width: _partyColumns[4].width - 12,
            maxLines: 2,
            onChanged: (v) {
              party.datesPlaceOfBaptism = v;
              onChanged?.call();
            },
          ),
          isFirstLine
              ? _SpanCell(
                  height: 112,
                  child: _RegisterField(
                    key: ValueKey('m-$index-dom'),
                    label: '',
                    hint: 'Date',
                    fillGeneration: fillGeneration,
                    value: entry.dateOfMarriage,
                    width: _sharedColumns[0].width - 12,
                    maxLines: 2,
                    onChanged: (v) => touch(() => entry.dateOfMarriage = v),
                  ),
                )
              : const SizedBox.shrink(),
          _RegisterField(
            key: ValueKey('$idPrefix-parents'),
            label: '',
            hint: 'Parents',
            fillGeneration: fillGeneration,
            value: party.parents,
            width: _sharedColumns[1].width - 12,
            maxLines: 2,
            onChanged: (v) {
              party.parents = v;
              onChanged?.call();
            },
          ),
          _RegisterField(
            key: ValueKey('$idPrefix-sponsors'),
            label: '',
            hint: 'Sponsors',
            fillGeneration: fillGeneration,
            value: party.sponsors,
            width: _sharedColumns[2].width - 12,
            maxLines: 2,
            onChanged: (v) {
              party.sponsors = v;
              onChanged?.call();
            },
          ),
          isFirstLine
              ? _SpanCell(
                  height: 112,
                  child: _RegisterField(
                    key: ValueKey('m-$index-minister'),
                    label: '',
                    hint: 'Minister',
                    fillGeneration: fillGeneration,
                    value: entry.minister,
                    width: _sharedColumns[3].width - 12,
                    maxLines: 2,
                    onChanged: (v) => touch(() => entry.minister = v),
                  ),
                )
              : const SizedBox.shrink(),
          isFirstLine
              ? _SpanCell(
                  height: 112,
                  child: _RegisterField(
                    key: ValueKey('m-$index-license'),
                    label: '',
                    hint: 'License',
                    fillGeneration: fillGeneration,
                    value: entry.licenseNumber,
                    width: _sharedColumns[4].width - 12,
                    onChanged: (v) => touch(() => entry.licenseNumber = v),
                  ),
                )
              : const SizedBox.shrink(),
          isFirstLine
              ? _SpanCell(
                  height: 112,
                  child: _RegisterField(
                    key: ValueKey('m-$index-obs'),
                    label: '',
                    hint: 'Notes',
                    fillGeneration: fillGeneration,
                    value: entry.observations,
                    width: _sharedColumns[5].width - 12,
                    maxLines: 3,
                    onChanged: (v) => touch(() => entry.observations = v),
                  ),
                )
              : const SizedBox.shrink(),
          if (showRemove)
            isFirstLine
                ? _SpanCell(
                    height: 112,
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: onRemove,
                      tooltip: 'Remove entry',
                    ),
                  )
                : const SizedBox.shrink(),
        ],
      );
    }

    return [
      row(
        partyLabel: 'Man',
        partyIcon: Icons.man_outlined,
        party: entry.groom,
        idPrefix: 'm-$index-groom',
        isFirstLine: true,
      ),
      row(
        partyLabel: 'Woman',
        partyIcon: Icons.woman_outlined,
        party: entry.bride,
        idPrefix: 'm-$index-bride',
        isFirstLine: false,
      ),
    ];
  }
}

class _Col {
  const _Col(this.label, this.width);
  final String label;
  final double width;
}

/// Visual rowspan: fixed height matching two register lines.
class _SpanCell extends StatelessWidget {
  const _SpanCell({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(child: child),
    );
  }
}

class _PartyBadge extends StatelessWidget {
  const _PartyBadge({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMan = label == 'Man';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18,
            color: isMan ? cs.primary : cs.secondary,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterField extends StatefulWidget {
  const _RegisterField({
    super.key,
    required this.label,
    required this.fillGeneration,
    required this.value,
    required this.onChanged,
    this.hint,
    this.width,
    this.maxLines = 1,
  });

  final String label;
  final String? hint;
  final int fillGeneration;
  final String value;
  final ValueChanged<String> onChanged;
  final double? width;
  final int maxLines;

  @override
  State<_RegisterField> createState() => _RegisterFieldState();
}

class _RegisterFieldState extends State<_RegisterField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_RegisterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fillGeneration != widget.fillGeneration) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: SizedBox(
        width: widget.width,
        child: TextField(
          controller: _controller,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            labelText: widget.label.isEmpty ? null : widget.label,
            hintText: widget.hint,
            isDense: true,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
          ),
          maxLines: widget.maxLines,
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
