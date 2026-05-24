import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/record.dart';
import '../../../models/register_ocr_entry.dart';
import '../../../providers/records_provider.dart';
import '../../../services/register_ocr_parser.dart';
import '../../../utils/manual_register_notes.dart';
import '../../../services/register_ocr_scan_helper.dart';
import '../../../widgets/register_ocr_table.dart';
import '../../../widgets/register_scan_launcher.dart';

/// Manual baptism register entry (temporary records) for staff.
class StaffManualBaptismPage extends ConsumerStatefulWidget {
  const StaffManualBaptismPage({
    super.key,
    this.existing,
    this.initialOcrEntries,
    this.initialVolNo,
    this.initialSeriesNo,
    this.returnRoute = '/staff/records',
  });

  /// When set, opens in edit mode for one saved register row.
  final ParishRecord? existing;
  final List<RegisterOcrEntry>? initialOcrEntries;
  final String? initialVolNo;
  final String? initialSeriesNo;
  final String returnRoute;

  @override
  ConsumerState<StaffManualBaptismPage> createState() =>
      _StaffManualBaptismPageState();
}

class _StaffManualBaptismPageState extends ConsumerState<StaffManualBaptismPage> {
  final _volCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  late List<RegisterOcrEntry> _entries;
  bool _saving = false;
  String? _editingRecordId;
  int _fillGeneration = 0;

  bool get _isEditing => _editingRecordId != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (widget.initialVolNo != null && widget.initialVolNo!.trim().isNotEmpty) {
      _volCtrl.text = widget.initialVolNo!.trim();
    }
    if (widget.initialSeriesNo != null &&
        widget.initialSeriesNo!.trim().isNotEmpty) {
      _seriesCtrl.text = widget.initialSeriesNo!.trim();
    }

    if (existing != null && ManualRegisterNotes.isManualBaptismRecord(existing)) {
      _editingRecordId = existing.id;
      final data = ManualRegisterNotes.tryDecode(existing.notes)!;
      _volCtrl.text = ManualRegisterNotes.field(data, 'volNo');
      _seriesCtrl.text = ManualRegisterNotes.field(data, 'seriesNo');
      _entries = [
        ManualRegisterNotes.entryFromMap(data, id: existing.id),
      ];
      _fillGeneration++;
    } else if (widget.initialOcrEntries != null &&
        widget.initialOcrEntries!.isNotEmpty) {
      _entries =
          RegisterOcrScanHelper.autofillForTable(widget.initialOcrEntries!);
      _fillGeneration++;
    } else {
      _entries = List.generate(5, (i) => _emptyRow(i + 1));
    }
  }

  @override
  void dispose() {
    _volCtrl.dispose();
    _seriesCtrl.dispose();
    super.dispose();
  }

  RegisterOcrEntry _emptyRow(int no) {
    return RegisterOcrEntry(
      id: '${DateTime.now().microsecondsSinceEpoch}-$no',
      name: '',
      lineNo: '$no',
      rawLine: '',
      selected: true,
    );
  }

  bool _rowReadyToSave(RegisterOcrEntry e) =>
      e.selected && e.name.trim().length >= 2;

  int get _readyCount => _entries.where(_rowReadyToSave).length;

  void _addRow() {
    setState(() {
      _entries.add(_emptyRow(_entries.length + 1));
    });
  }

  StaffOcrScanResult? _existingScanForUpload() {
    final hasData = _entries.any(
      (e) =>
          e.name.trim().isNotEmpty ||
          e.placeAndBirthDate.trim().isNotEmpty ||
          e.parents.trim().isNotEmpty,
    );
    if (!hasData) return null;
    return StaffOcrScanResult(text: '', entries: _entries);
  }

  Future<void> _uploadPhoto() async {
    final result = await RegisterScanLauncher.uploadPhotoAutofill(
      context: context,
      recordType: 'baptism',
      volNumber: _volCtrl.text.trim(),
      seriesNumber: _seriesCtrl.text.trim(),
      existing: _existingScanForUpload(),
    );
    if (result == null || !mounted) return;
    _applyUploadResult(result);
  }

  void _applyUploadResult(StaffOcrScanResult result) {
    final normalized = RegisterOcrScanHelper.finalizeScanResult(
      result,
      recordType: 'baptism',
    );
    var scannedRows = normalized.entries;
    if (!RegisterOcrScanHelper.hasMeaningfulEntries(scannedRows) &&
        normalized.text.trim().isNotEmpty) {
      scannedRows = RegisterOcrScanHelper.buildEveryLineRows(normalized.text);
    }
    setState(() {
      final formHasData = _entries.any(
        (e) =>
            e.name.trim().isNotEmpty ||
            e.placeAndBirthDate.trim().isNotEmpty ||
            e.parents.trim().isNotEmpty,
      );
      _entries = formHasData && scannedRows.isNotEmpty
          ? RegisterOcrScanHelper.appendPageEntries(_entries, scannedRows)
          : (scannedRows.isNotEmpty
              ? scannedRows
              : List.generate(5, (i) => _emptyRow(i + 1)));
      _fillGeneration++;
    });
    final filled = _entries
        .where(
          (e) =>
              e.name.trim().isNotEmpty ||
              e.placeAndBirthDate.trim().isNotEmpty,
        )
        .length;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          filled > 0
              ? 'Autofilled $filled baptism row(s) from photo. Review and save.'
              : 'Photo read — add or edit rows, or upload a clearer image.',
        ),
        backgroundColor: filled > 0 ? Colors.green : null,
      ),
    );
  }

  void _toggleAll(bool value) {
    setState(() {
      for (final e in _entries) {
        e.selected = value;
      }
    });
  }

  DateTime _dateForEntry(RegisterOcrEntry e) {
    if (e.date != null) return e.date!;
    final fromText = RegisterOcrParser.parseDate(e.baptismDateText);
    if (fromText != null) return fromText;
    return DateTime.now();
  }

  Future<void> _saveTemporary() async {
    final toSave = _entries.where(_rowReadyToSave).toList();
    if (toSave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter at least one child name (No. + Name of Child).'),
        ),
      );
      return;
    }

    final vol = _volCtrl.text.trim();
    final series = _seriesCtrl.text.trim();

    if (_isEditing) {
      setState(() => _saving = true);
      try {
        final e = toSave.first;
        final parish = e.residentsOf.trim().isNotEmpty
            ? e.residentsOf.trim()
            : 'Manual Register';
        await ref.read(recordsProvider.notifier).updateRecord(
              _editingRecordId!,
              type: RecordType.baptism,
              name: e.name.trim(),
              date: _dateForEntry(e),
              parish: parish,
              notes: jsonEncode(
                ManualRegisterNotes.toNotesMap(
                  volNo: vol,
                  seriesNo: series,
                  entry: e,
                ),
              ),
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Register entry updated.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go(widget.returnRoute);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Update failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save temporary records?'),
        content: Text(
          'This saves ${toSave.length} baptism row(s) as temporary manual '
          'entries${vol.isNotEmpty || series.isNotEmpty ? ' (Vol $vol, Series $series)' : ''}. '
          'You can complete them later from Records.',
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
      final drafts = toSave.map((e) {
        return RegisterRecordDraft(
          type: RecordType.baptism,
          name: e.name.trim(),
          date: _dateForEntry(e),
          parish: e.residentsOf.trim().isNotEmpty
              ? e.residentsOf.trim()
              : 'Manual Register',
          notes: jsonEncode(
            ManualRegisterNotes.toNotesMap(
              volNo: vol,
              seriesNo: series,
              entry: e,
            ),
          ),
          recordStatus: 'temporary',
        );
      }).toList();

      final count = await ref.read(recordsProvider.notifier).addRecordsBatch(
            drafts,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count temporary baptism record(s) saved.'),
          backgroundColor: Colors.green,
        ),
      );
      context.go(widget.returnRoute);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Baptism Register' : 'Manual Baptism Register',
        ),
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
              onPressed: _readyCount == 0 ? null : _saveTemporary,
              icon: const Icon(Icons.save_outlined),
              label: Text('Save ($_readyCount)'),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.tertiary.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.edit_note, color: colorScheme.tertiary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'BAPTISM — Temporary manual entry',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap Upload photo to scan the register — the table autofills. '
                  'For two pages: upload left page first, then upload again for '
                  'Residents / Baptism / Minister / Sponsors (merged by No.).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _volCtrl,
                        decoration: InputDecoration(
                          labelText: 'Volume Number',
                          hintText: 'e.g. 1',
                          filled: true,
                          fillColor: colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _seriesCtrl,
                        decoration: InputDecoration(
                          labelText: 'Series Number',
                          hintText: 'e.g. A',
                          filled: true,
                          fillColor: colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
                Text(
                  '$_readyCount row(s) ready',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _uploadPhoto,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Upload photo'),
                ),
                if (!_isEditing) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add row'),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: RegisterOcrTable(
              key: ValueKey('baptism-table-$_fillGeneration'),
              fillGeneration: _fillGeneration,
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
            onPressed: _saving || _readyCount == 0 ? null : _saveTemporary,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              _saving
                  ? 'Saving…'
                  : _isEditing
                      ? 'Update register entry'
                      : 'Save $_readyCount temporary record(s)',
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
