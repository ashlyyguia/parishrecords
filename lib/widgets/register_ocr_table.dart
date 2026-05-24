import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/register_ocr_entry.dart';
import '../services/register_ocr_parser.dart';

/// Baptism register columns shown after OCR scan.
class RegisterOcrTable extends StatelessWidget {
  const RegisterOcrTable({
    super.key,
    required this.entries,
    required this.fillGeneration,
    this.onChanged,
    this.onRemove,
    this.showCheckboxes = true,
    this.compact = false,
    this.readOnly = false,
    this.maxHeight,
  });

  final List<RegisterOcrEntry> entries;
  /// Bumped after OCR so fields reload with scanned values.
  final int fillGeneration;
  final VoidCallback? onChanged;
  final void Function(int index)? onRemove;
  final bool showCheckboxes;
  final bool compact;
  final bool readOnly;
  final double? maxHeight;

  static const columns = [
    'No',
    'Name of Child',
    'Place & Date of Birth',
    'Parents',
    'Residents Of',
    'Date of Baptism',
    'Minister',
    'Sponsor',
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
                'No register rows detected',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Try scanning again or tap Add row to enter records manually.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      );
    }

    final table = LayoutBuilder(
      builder: (context, constraints) {
        final minTableWidth = compact ? 1100.0 : 1200.0;
        final height = maxHeight ??
            (constraints.maxHeight.isFinite ? constraints.maxHeight : null);

        final dataTable = ConstrainedBox(
          constraints: BoxConstraints(minWidth: minTableWidth),
          child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                cs.primaryContainer.withValues(alpha: 0.6),
              ),
              headingTextStyle: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onPrimaryContainer,
              ),
              dataTextStyle: theme.textTheme.bodySmall,
              dataRowMinHeight: readOnly ? 48 : 56,
              dataRowMaxHeight: readOnly ? 64 : 96,
              columnSpacing: compact ? 12 : 16,
              horizontalMargin: 12,
              columns: [
                if (showCheckboxes)
                  const DataColumn(label: SizedBox(width: 36)),
                ...columns.map((c) => DataColumn(label: Text(c))),
                if (onRemove != null) const DataColumn(label: Text('')),
              ],
              rows: [
                for (var i = 0; i < entries.length; i++)
                  _buildRow(context, i, entries[i]),
              ],
            ),
        );

        final scrollable = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: dataTable,
          ),
        );

        if (height != null && height > 0) {
          return SizedBox(height: height, child: scrollable);
        }
        return scrollable;
      },
    );

    return table;
  }

  DataRow _buildRow(BuildContext context, int index, RegisterOcrEntry entry) {
    final cs = Theme.of(context).colorScheme;
    final invalid = !entry.isValid;
    final hasData = entry.name.trim().isNotEmpty ||
        entry.placeAndBirthDate.trim().isNotEmpty;

    return DataRow(
      key: ValueKey('baptism-row-$index-gen$fillGeneration-h${entry.hashCode}'),
      color: WidgetStateProperty.resolveWith((states) {
        if (invalid && hasData) {
          return cs.tertiaryContainer.withValues(alpha: 0.25);
        }
        if (invalid) {
          return cs.errorContainer.withValues(alpha: 0.15);
        }
        if (hasData) {
          return cs.primaryContainer.withValues(alpha: 0.12);
        }
        return null;
      }),
      cells: [
        if (showCheckboxes && !readOnly)
          DataCell(
            Checkbox(
              value: entry.selected,
              onChanged: (v) {
                entry.selected = v ?? false;
                onChanged?.call();
              },
            ),
          ),
        DataCell(
          _OcrFieldCell(
            fillGeneration: fillGeneration,
            fieldKey: 'row-$index-no',
            value: entry.lineNo ?? '${index + 1}',
            width: 48,
            onChanged: (v) {
              entry.lineNo = v;
              onChanged?.call();
            },
          ),
        ),
        DataCell(
          _OcrFieldCell(
            fillGeneration: fillGeneration,
            fieldKey: 'row-$index-name',
            value: entry.name,
            width: 140,
            onChanged: (v) {
              entry.name = v;
              onChanged?.call();
            },
          ),
        ),
        DataCell(
          _OcrFieldCell(
            fillGeneration: fillGeneration,
            fieldKey: 'row-$index-birth',
            value: entry.placeAndBirthDate,
            width: 180,
            maxLines: 3,
            onChanged: (v) {
              entry.placeAndBirthDate = v;
              onChanged?.call();
            },
          ),
        ),
        DataCell(
          _OcrFieldCell(
            fillGeneration: fillGeneration,
            fieldKey: 'row-$index-parents',
            value: entry.parents,
            width: 160,
            maxLines: 3,
            onChanged: (v) {
              entry.parents = v;
              onChanged?.call();
            },
          ),
        ),
        DataCell(
          _OcrFieldCell(
            fillGeneration: fillGeneration,
            fieldKey: 'row-$index-residents',
            value: entry.residentsOf,
            width: 160,
            maxLines: 3,
            onChanged: (v) {
              entry.residentsOf = v;
              onChanged?.call();
            },
          ),
        ),
        DataCell(
          readOnly
              ? _readOnlyDate(entry)
              : _BaptismDateField(
                  fillGeneration: fillGeneration,
                  fieldKey: 'row-$index-baptism',
                  entry: entry,
                  onChanged: onChanged,
                ),
        ),
        DataCell(
          _OcrFieldCell(
            fillGeneration: fillGeneration,
            fieldKey: 'row-$index-minister',
            value: entry.minister,
            width: 120,
            onChanged: (v) {
              entry.minister = v;
              onChanged?.call();
            },
          ),
        ),
        DataCell(
          _OcrFieldCell(
            fillGeneration: fillGeneration,
            fieldKey: 'row-$index-sponsors',
            value: entry.sponsors,
            width: 160,
            maxLines: 3,
            onChanged: (v) {
              entry.sponsors = v;
              onChanged?.call();
            },
          ),
        ),
        if (onRemove != null)
          DataCell(
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => onRemove!(index),
              tooltip: 'Remove row',
            ),
          ),
      ],
    );
  }

  Widget _readOnlyDate(RegisterOcrEntry entry) {
    final text = entry.baptismDateText.isNotEmpty
        ? entry.baptismDateText
        : (entry.date != null
            ? DateFormat('dd MMM yyyy').format(entry.date!)
            : '—');
    return SizedBox(
      width: 130,
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

/// Text field that reloads when [fillGeneration] changes (after OCR autofill).
class _OcrFieldCell extends StatefulWidget {
  const _OcrFieldCell({
    required this.fillGeneration,
    required this.fieldKey,
    required this.value,
    required this.onChanged,
    this.width = 120,
    this.maxLines = 2,
  });

  final int fillGeneration;
  final String fieldKey;
  final String value;
  final ValueChanged<String> onChanged;
  final double width;
  final int maxLines;

  @override
  State<_OcrFieldCell> createState() => _OcrFieldCellState();
}

class _OcrFieldCellState extends State<_OcrFieldCell> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_OcrFieldCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fillGeneration != widget.fillGeneration ||
        oldWidget.value != widget.value) {
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
    return SizedBox(
      width: widget.width,
      child: TextFormField(
        key: ValueKey('${widget.fieldKey}-${widget.fillGeneration}'),
        controller: _controller,
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        maxLines: widget.maxLines,
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _BaptismDateField extends StatefulWidget {
  const _BaptismDateField({
    required this.fillGeneration,
    required this.fieldKey,
    required this.entry,
    this.onChanged,
  });

  final int fillGeneration;
  final String fieldKey;
  final RegisterOcrEntry entry;
  final VoidCallback? onChanged;

  @override
  State<_BaptismDateField> createState() => _BaptismDateFieldState();
}

class _BaptismDateFieldState extends State<_BaptismDateField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.entry.baptismDateText);
  }

  @override
  void didUpdateWidget(_BaptismDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fillGeneration != widget.fillGeneration ||
        oldWidget.entry.baptismDateText != widget.entry.baptismDateText) {
      _controller.text = widget.entry.baptismDateText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.entry.date ?? DateTime.now(),
      firstDate: DateTime(1800),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      widget.entry.date = picked;
      widget.entry.baptismDateText =
          RegisterOcrParser.formatWrittenDate(picked);
      _controller.text = widget.entry.baptismDateText;
      widget.onChanged?.call();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: TextFormField(
        key: ValueKey('${widget.fieldKey}-baptism-${widget.fillGeneration}'),
        controller: _controller,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          hintText: '16 May 2016',
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_today, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Pick date',
            onPressed: _pickDate,
          ),
        ),
        onChanged: (v) {
          widget.entry.baptismDateText = v;
          widget.entry.date = RegisterOcrParser.parseDate(v);
          widget.onChanged?.call();
        },
      ),
    );
  }
}
