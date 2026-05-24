import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/register_ocr_entry.dart';
import '../../../providers/records_provider.dart';
import '../../../services/register_ocr_parser.dart';
import '../../../services/register_ocr_record_save.dart';
import '../../../widgets/register_ocr_table.dart';

/// Review parsed register rows in a table and save multiple official records.
class StaffOcrBulkRecordsPage extends ConsumerStatefulWidget {
  const StaffOcrBulkRecordsPage({
    super.key,
    required this.rawText,
    required this.recordType,
    this.volNumber = '',
    this.seriesNumber = '',
    this.initialEntries,
  });

  final String rawText;
  final String recordType;
  final String volNumber;
  final String seriesNumber;
  final List<RegisterOcrEntry>? initialEntries;

  @override
  ConsumerState<StaffOcrBulkRecordsPage> createState() =>
      _StaffOcrBulkRecordsPageState();
}

class _StaffOcrBulkRecordsPageState
    extends ConsumerState<StaffOcrBulkRecordsPage> {
  late List<RegisterOcrEntry> _entries;
  late int _skippedLines;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialEntries != null && widget.initialEntries!.isNotEmpty) {
      _entries = List.from(widget.initialEntries!);
      _skippedLines = 0;
    } else {
      final result = RegisterOcrParser.parse(
        widget.rawText,
        recordType: widget.recordType,
      );
      _entries = result.entries;
      _skippedLines = result.skippedLines;
    }
  }

  int get _selectedValidCount =>
      _entries.where((e) => e.selected && e.isValid).length;

  void _reparse() {
    final result = RegisterOcrParser.parse(
      widget.rawText,
      recordType: widget.recordType,
    );
    setState(() {
      _entries = result.entries;
      _skippedLines = result.skippedLines;
    });
  }

  void _toggleAll(bool value) {
    setState(() {
      for (final e in _entries) {
        e.selected = value;
      }
    });
  }

  Future<void> _saveSelected() async {
    final toSave = _entries.where((e) => e.selected && e.isValid).toList();
    if (toSave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select at least one row with a name and baptism date before saving.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save official records?'),
        content: Text(
          'This will create ${toSave.length} '
          '${widget.recordType} record(s) in Firestore. '
          'You can edit full details later from Records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Save ${toSave.length}'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final count = await saveRegisterOcrEntries(
        ref: ref,
        entries: toSave,
        recordType: widget.recordType,
        volNumber: widget.volNumber,
        seriesNumber: widget.seriesNumber,
        source: 'register_ocr_bulk',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count official record(s) created.'),
          backgroundColor: Colors.green,
        ),
      );
      context.go('/staff/records');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addManualRow() {
    setState(() {
      _entries.add(
        RegisterOcrEntry(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: '',
          lineNo: '${_entries.length + 1}',
          baptismDateText: '',
          rawLine: '',
          selected: true,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final typeLabel = widget.recordType[0].toUpperCase() +
        widget.recordType.substring(1);
    final isBaptism = widget.recordType.toLowerCase() == 'baptism';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(isBaptism ? 'Baptism Register' : 'Bulk Register Import'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _selectedValidCount == 0 ? null : _saveSelected,
              icon: const Icon(Icons.save_outlined),
              label: Text('Save ($_selectedValidCount)'),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryBanner(
            typeLabel: typeLabel,
            volNumber: widget.volNumber,
            seriesNumber: widget.seriesNumber,
            entryCount: _entries.length,
            skipped: _skippedLines,
            validSelected: _selectedValidCount,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _toggleAll(true),
                  icon: const Icon(Icons.select_all, size: 18),
                  label: const Text('Select all'),
                ),
                TextButton.icon(
                  onPressed: () => _toggleAll(false),
                  icon: const Icon(Icons.deselect, size: 18),
                  label: const Text('Clear'),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _addManualRow,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add row'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _entries.isEmpty
                ? _EmptyParseState(onReparse: _reparse)
                : RegisterOcrTable(
                    fillGeneration: 0,
                    entries: _entries,
                    onChanged: () => setState(() {}),
                    onRemove: (i) => setState(() => _entries.removeAt(i)),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _saving || _selectedValidCount == 0
                ? null
                : _saveSelected,
            icon: const Icon(Icons.library_add_check_outlined),
            label: Text(
              _saving
                  ? 'Saving…'
                  : 'Create $_selectedValidCount official record(s)',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({
    required this.typeLabel,
    required this.volNumber,
    required this.seriesNumber,
    required this.entryCount,
    required this.skipped,
    required this.validSelected,
  });

  final String typeLabel;
  final String volNumber;
  final String seriesNumber;
  final int entryCount;
  final int skipped;
  final int validSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$typeLabel · Register page',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          if (volNumber.isNotEmpty || seriesNumber.isNotEmpty)
            Text(
              [
                if (volNumber.isNotEmpty) 'Vol $volNumber',
                if (seriesNumber.isNotEmpty) 'Series $seriesNumber',
              ].join(' · '),
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _Chip(label: '$entryCount parsed'),
              if (skipped > 0) _Chip(label: '$skipped skipped lines'),
              _Chip(
                label: '$validSelected ready to save',
                highlight: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.highlight = false});
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? cs.primary.withValues(alpha: 0.15)
            : cs.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
          color: highlight ? cs.primary : cs.onSurface,
        ),
      ),
    );
  }
}

class _EmptyParseState extends StatelessWidget {
  const _EmptyParseState({required this.onReparse});
  final VoidCallback onReparse;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.table_rows_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            const Text(
              'No register rows detected',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Each row should include No, Name of Child, Place & Date of Birth, '
              'Parents, Residents Of, Date of Baptism, Minister, and Sponsors. '
              'Use Add row to enter records manually.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(
                      alpha: 0.7,
                    ),
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onReparse,
              icon: const Icon(Icons.refresh),
              label: const Text('Re-parse text'),
            ),
          ],
        ),
      ),
    );
  }
}
