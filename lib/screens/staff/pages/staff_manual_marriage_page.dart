import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/record.dart';
import '../../../models/register_marriage_entry.dart';
import '../../../models/register_ocr_entry.dart';
import '../../../providers/records_provider.dart';
import '../../../utils/manual_register_notes.dart';
import '../../../services/register_marriage_ocr_helper.dart';
import '../../../services/register_ocr_scan_helper.dart';
import '../../../widgets/register_marriage_table.dart';
import '../../../widgets/register_scan_launcher.dart';

/// Manual marriage register entry (temporary records) for staff.
class StaffManualMarriagePage extends ConsumerStatefulWidget {
  const StaffManualMarriagePage({
    super.key,
    this.existing,
    this.initialMarriageEntries,
    this.initialVolNo,
    this.initialSeriesNo,
    this.returnRoute = '/staff/records',
  });

  final ParishRecord? existing;
  final List<RegisterMarriageEntry>? initialMarriageEntries;
  final String? initialVolNo;
  final String? initialSeriesNo;
  final String returnRoute;

  @override
  ConsumerState<StaffManualMarriagePage> createState() =>
      _StaffManualMarriagePageState();
}

class _StaffManualMarriagePageState extends ConsumerState<StaffManualMarriagePage> {
  final _volCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  late List<RegisterMarriageEntry> _entries;
  bool _saving = false;
  String? _editingRecordId;
  int _fillGeneration = 0;
  int _readyCount = 0;

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

    if (existing != null && ManualRegisterNotes.isManualMarriageRecord(existing)) {
      _editingRecordId = existing.id;
      final data = ManualRegisterNotes.tryDecode(existing.notes)!;
      _volCtrl.text = ManualRegisterNotes.field(data, 'volNo');
      _seriesCtrl.text = ManualRegisterNotes.field(data, 'seriesNo');
      _entries = [
        ManualRegisterNotes.marriageEntryFromMap(data, id: existing.id),
      ];
      _fillGeneration++;
    } else if (widget.initialMarriageEntries != null &&
        widget.initialMarriageEntries!.isNotEmpty) {
      _entries = RegisterMarriageOcrHelper.autofillForTable(
        widget.initialMarriageEntries!,
      );
      _fillGeneration++;
    } else {
      _entries = List.generate(5, (i) => _emptyRow(i + 1));
    }
    _readyCount = _entries.where((e) => e.selected && e.isReadyToSave).length;
  }

  void _onEntryChanged({bool rebuildUi = false}) {
    final count = _entries.where((e) => e.selected && e.isReadyToSave).length;
    if (rebuildUi || count != _readyCount) {
      setState(() => _readyCount = count);
    }
  }

  @override
  void dispose() {
    _volCtrl.dispose();
    _seriesCtrl.dispose();
    super.dispose();
  }

  RegisterMarriageEntry _emptyRow(int no) {
    return RegisterMarriageEntry(
      id: '${DateTime.now().microsecondsSinceEpoch}-$no',
      lineNo: '$no',
    );
  }

  StaffOcrScanResult? _existingScanForUpload() {
    final hasData = _entries.any(
      (e) =>
          e.groom.name.trim().isNotEmpty ||
          e.bride.name.trim().isNotEmpty ||
          e.dateOfMarriage.trim().isNotEmpty,
    );
    if (!hasData) return null;
    return StaffOcrScanResult(text: '', marriageEntries: _entries);
  }

  Future<void> _uploadPhoto() async {
    final result = await RegisterScanLauncher.uploadPhotoAutofill(
      context: context,
      recordType: 'marriage',
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
      recordType: 'marriage',
    );
    var scannedRows = normalized.marriageEntries;
    if (!scannedRows.any(RegisterMarriageOcrHelper.entryHasData) &&
        normalized.text.trim().isNotEmpty) {
      scannedRows = RegisterMarriageOcrHelper.resolveTableRows(
        ocrText: normalized.text,
        parsedOcr: normalized.entries,
      );
    }
    setState(() {
      _entries = RegisterMarriageOcrHelper.mergeIntoForm(
        current: _entries,
        scanned: scannedRows,
      );
      if (_entries.isEmpty) {
        _entries = List.generate(3, (i) => _emptyRow(i + 1));
      }
      _fillGeneration++;
      _readyCount =
          _entries.where((e) => e.selected && e.isReadyToSave).length;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _readyCount > 0
              ? 'Autofilled $_readyCount marriage record(s). Review Man/Woman rows.'
              : 'Photo read — upload a clearer image or enter rows manually.',
        ),
        backgroundColor: _readyCount > 0 ? Colors.green : null,
      ),
    );
  }

  void _addRow() {
    setState(() {
      _entries.add(_emptyRow(_entries.length + 1));
    });
  }

  void _toggleAll(bool value) {
    setState(() {
      for (final e in _entries) {
        e.selected = value;
      }
    });
  }

  Future<void> _saveTemporary() async {
    final toSave = _entries.where((e) => e.selected && e.isReadyToSave).toList();
    if (toSave.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter at least one marriage with Man or Woman name filled in.',
          ),
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
        await ref.read(recordsProvider.notifier).updateRecord(
              _editingRecordId!,
              type: RecordType.marriage,
              name: e.recordDisplayName,
              date: ManualRegisterNotes.marriageDateForEntry(e),
              parish: e.primaryAddress.isNotEmpty
                  ? e.primaryAddress
                  : 'Manual Register',
              notes: jsonEncode(
                ManualRegisterNotes.toMarriageNotesMap(
                  volNo: vol,
                  seriesNo: series,
                  entry: e,
                ),
              ),
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Marriage register entry updated.'),
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
          'This saves ${toSave.length} marriage row(s) as temporary manual '
          'entries${vol.isNotEmpty || series.isNotEmpty ? ' (Vol $vol, Series $series)' : ''}.',
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
          type: RecordType.marriage,
          name: e.recordDisplayName,
          date: ManualRegisterNotes.marriageDateForEntry(e),
          parish: e.primaryAddress.isNotEmpty
              ? e.primaryAddress
              : 'Manual Register',
          notes: jsonEncode(
            ManualRegisterNotes.toMarriageNotesMap(
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
          content: Text('$count temporary marriage record(s) saved.'),
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
          _isEditing ? 'Edit Marriage Register' : 'Manual Marriage Register',
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
              color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.secondary.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.favorite_outlined, color: colorScheme.secondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'MARRIAGE — Temporary manual entry',
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
                  'Tap Upload photo — the table autofills (Man + Woman per No.). '
                  'Upload both pages of the book to merge by register number.',
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
            child: RegisterMarriageTable(
              key: ValueKey('marriage-table-$_fillGeneration'),
              fillGeneration: _fillGeneration,
              entries: _entries,
              onChanged: _onEntryChanged,
              onSelectionChanged: () => _onEntryChanged(rebuildUi: true),
              onRemove: (i) => setState(() {
                _entries.removeAt(i);
                _readyCount =
                    _entries.where((e) => e.selected && e.isReadyToSave).length;
              }),
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
