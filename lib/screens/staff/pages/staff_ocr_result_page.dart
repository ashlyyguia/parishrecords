import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/register_marriage_entry.dart';
import '../../../models/register_ocr_entry.dart';
import '../../../services/ocr_image_pick.dart';
import '../../../services/register_marriage_ocr_helper.dart';
import '../../../services/register_ocr_parser.dart';
import '../../../services/register_ocr_scan_helper.dart';
import '../../../widgets/register_marriage_table.dart';
import '../../../widgets/register_ocr_table.dart';

/// Shown after OCR scan — editable register table only (no raw text step).
class StaffOcrResultPage extends StatefulWidget {
  const StaffOcrResultPage({
    super.key,
    this.initialText = '',
    this.initialEntries,
    this.initialMarriageEntries,
    this.imagePath,
    this.recordType = 'baptism',
    this.volNumber = '',
    this.seriesNumber = '',
    this.showSaveAction = false,
    this.scannedLineCount = 0,
    this.scannedCellCount = 0,
    this.initialPageCount = 0,
  });

  /// When set, OCR runs on this page and shows a loading state first.
  final String? imagePath;
  final String initialText;
  final List<RegisterOcrEntry>? initialEntries;
  final List<RegisterMarriageEntry>? initialMarriageEntries;
  final int scannedLineCount;
  final int scannedCellCount;
  /// Pages already merged before this screen (e.g. multi-image pick).
  final int initialPageCount;
  final String recordType;
  final String volNumber;
  final String seriesNumber;
  final bool showSaveAction;

  bool get processFromImage =>
      imagePath != null && imagePath!.isNotEmpty;

  @override
  State<StaffOcrResultPage> createState() => _StaffOcrResultPageState();
}

class _StaffOcrResultPageState extends State<StaffOcrResultPage> {
  String _scanText = '';
  List<RegisterOcrEntry> _entries = [];
  List<RegisterMarriageEntry> _marriageEntries = [];
  int _skippedLines = 0;
  int _scannedLines = 0;
  int _scannedCells = 0;
  int _pageCount = 0;
  bool _isProcessing = false;
  String? _error;
  int _tableGeneration = 0;

  bool get _isMarriage => widget.recordType.toLowerCase() == 'marriage';

  @override
  void initState() {
    super.initState();
    _scanText = widget.initialText;
    _scannedLines = widget.scannedLineCount;
    _scannedCells = widget.scannedCellCount;

    final hasInitial = _isMarriage
        ? (widget.initialMarriageEntries?.isNotEmpty ?? false)
        : (widget.initialEntries?.isNotEmpty ?? false);

    final shouldScanImage = widget.processFromImage &&
        !hasInitial &&
        widget.initialText.trim().isEmpty;

    if (shouldScanImage) {
      _isProcessing = true;
      if (_isMarriage) {
        _marriageEntries = [_emptyMarriageRow(1)];
      } else {
        _entries = List.generate(4, (i) => _emptyRow(i + 1));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _runOcrFromImage());
    } else if (_isMarriage &&
        widget.initialMarriageEntries != null &&
        widget.initialMarriageEntries!.isNotEmpty) {
      _marriageEntries = RegisterMarriageOcrHelper.ensureUniqueEntryIds(
        RegisterMarriageOcrHelper.autofillForTable(
          List<RegisterMarriageEntry>.from(widget.initialMarriageEntries!),
        ),
      );
      _tableGeneration = 1;
      _pageCount = widget.initialPageCount > 0 ? widget.initialPageCount : 1;
    } else if (widget.initialEntries != null &&
        widget.initialEntries!.isNotEmpty) {
      _entries = RegisterOcrScanHelper.ensureUniqueEntryIds(
        RegisterOcrScanHelper.autofillForTable(
          List<RegisterOcrEntry>.from(widget.initialEntries!),
        ),
      );
      _tableGeneration = 1;
      _pageCount = widget.initialPageCount > 0 ? widget.initialPageCount : 1;
    } else if (widget.initialText.trim().isNotEmpty) {
      _applyParse(widget.initialText);
      _entries = RegisterOcrScanHelper.ensureUniqueEntryIds(_entries);
      _tableGeneration = 1;
      _pageCount = widget.initialPageCount > 0 ? widget.initialPageCount : 1;
    } else {
      if (_isMarriage) {
        _marriageEntries = [_emptyMarriageRow(1)];
      } else {
        _entries = [_emptyRow(1)];
      }
    }
  }

  RegisterMarriageEntry _emptyMarriageRow(int no) {
    return RegisterMarriageEntry(
      id: 'marriage-placeholder-$no',
      lineNo: '$no',
    );
  }

  RegisterOcrEntry _emptyRow(int no) {
    return RegisterOcrEntry(
      id: 'baptism-placeholder-$no',
      name: '',
      lineNo: '$no',
      rawLine: '',
      selected: true,
    );
  }

  Future<void> _runOcrFromImage() async {
    final path = widget.imagePath;
    if (path == null || path.isEmpty) return;
    await _runOcrFromPath(path, append: false);
  }

  Future<void> _runOcrFromPath(
    String path, {
    required bool append,
    XFile? xFile,
  }) async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      if (!mounted) return;
      await Future<void>.delayed(Duration.zero);

      final scan = await RegisterOcrScanHelper.scanXFile(
        xFile ?? XFile(path),
        recordType: widget.recordType,
      );
      final finalized = RegisterOcrScanHelper.finalizeScanResult(
        scan,
        recordType: widget.recordType,
      );

      if (!mounted) return;

      final previousCount =
          _isMarriage ? _marriageEntries.length : _entries.length;

      setState(() {
        if (_isMarriage) {
          final rows = finalized.marriageEntries.isNotEmpty
              ? finalized.marriageEntries
              : RegisterMarriageOcrHelper.resolveTableRows(
                  ocrText: finalized.text,
                  parsedOcr: finalized.entries,
                );
          if (append) {
            _scanText =
                RegisterOcrScanHelper.mergeScanText(_scanText, finalized.text);
            _marriageEntries = RegisterMarriageOcrHelper.appendPageEntries(
              _marriageEntries,
              rows,
            );
            _pageCount = (_pageCount > 0 ? _pageCount : 1) + 1;
          } else {
            _scanText = finalized.text;
            _marriageEntries =
                rows.isNotEmpty ? rows : [_emptyMarriageRow(1)];
            _pageCount = 1;
          }
        } else {
          final displayRows = finalized.entries.isNotEmpty
              ? finalized.entries
              : RegisterOcrScanHelper.resolveTableRows(
                  ocrText: finalized.text,
                  parsed: const [],
                  recordType: widget.recordType,
                );
          if (append) {
            _scanText =
                RegisterOcrScanHelper.mergeScanText(_scanText, finalized.text);
            _entries = RegisterOcrScanHelper.appendPageEntries(
              _entries,
              displayRows,
            );
            _pageCount = (_pageCount > 0 ? _pageCount : 1) + 1;
          } else {
            _scanText = finalized.text;
            _entries = displayRows.isNotEmpty ? displayRows : [_emptyRow(1)];
            _pageCount = 1;
          }
        }
        _scannedLines += scan.lineCount;
        _scannedCells += scan.cellCount;
        _skippedLines = 0;
        _isProcessing = false;
        _tableGeneration++;
        if (_isMarriage) {
          _marriageEntries =
              RegisterMarriageOcrHelper.ensureUniqueEntryIds(_marriageEntries);
        } else {
          _entries = RegisterOcrScanHelper.ensureUniqueEntryIds(_entries);
        }
      });

      final hasRows = RegisterOcrScanHelper.scanHasAutofillData(
        StaffOcrScanResult(
          text: finalized.text,
          entries: _entries,
          marriageEntries: _marriageEntries,
          lineCount: scan.lineCount,
          cellCount: scan.cellCount,
        ),
      );
      final ocrEmpty = finalized.text.trim().isEmpty && !hasRows;

      if (mounted) {
        setState(() {
          _error = ocrEmpty
              ? 'No text detected. Use brighter light, hold steady, and scan again.'
              : null;
        });
      }

      if (!mounted || ocrEmpty) return;

      final filledCount = _isMarriage
          ? _marriageEntries.where((e) => e.isReadyToSave).length
          : _entries
              .where(
                (e) =>
                    e.name.trim().isNotEmpty ||
                    e.placeAndBirthDate.trim().isNotEmpty ||
                    e.parents.trim().isNotEmpty,
              )
              .length;

      final total = _isMarriage ? _marriageEntries.length : _entries.length;
      final added = append ? filledCount - previousCount : filledCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isMarriage
                ? (append
                    ? 'Merged page $_pageCount — $total marriage No.(s). '
                        'Check Man/Woman rows and shared fields.'
                    : 'Auto-filled $filledCount marriage record(s)')
                : (append
                    ? (added > 0
                        ? 'Merged page $_pageCount into $total register row(s)'
                        : 'Page $_pageCount merged — check right-page columns')
                    : (filledCount > 1
                        ? 'Auto-filled $filledCount rows'
                        : 'Read $filledCount row(s) from scan')),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          if (!append) {
            if (_isMarriage) {
              _marriageEntries = [_emptyMarriageRow(1)];
            } else {
              _entries = [_emptyRow(1)];
            }
            _scanText = '';
          }
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _scanAnotherPage() async {
    if (_isProcessing) return;

    try {
      final picked = await OcrImagePick.pickRegisterPages(
        context,
        allowMultiple: true,
      );
      if (picked.isEmpty || !mounted) return;

      for (final file in picked) {
        if (!mounted) return;
        await _runOcrFromPath(file.path, append: true, xFile: file);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not scan page(s): $e')),
      );
    }
  }

  void _applyParse(String text) {
    if (_isMarriage) {
      final parsed = RegisterOcrParser.parseMarriageRegister(text);
      _marriageEntries = parsed.entries.isNotEmpty
          ? RegisterMarriageOcrHelper.autofillForTable(parsed.entries)
          : RegisterMarriageOcrHelper.resolveTableRows(
              ocrText: text,
              parsedOcr:
                  RegisterOcrParser.parse(text, recordType: 'marriage').entries,
            );
      if (_marriageEntries.isEmpty) _marriageEntries = [_emptyMarriageRow(1)];
      _marriageEntries =
          RegisterMarriageOcrHelper.ensureUniqueEntryIds(_marriageEntries);
      _skippedLines = parsed.skippedLines;
      return;
    }
    final result = RegisterOcrParser.parse(
      text,
      recordType: widget.recordType,
    );
    _entries = RegisterOcrScanHelper.resolveTableRows(
      ocrText: text,
      parsed: result.entries,
      recordType: widget.recordType,
    );
    if (_entries.isEmpty) _entries = [_emptyRow(1)];
    _skippedLines = result.skippedLines;
  }

  String _textForExport() {
    if (_scanText.trim().isNotEmpty) return _scanText.trim();
    final fromRaw = _entries
        .map((e) => e.rawLine.trim())
        .where((s) => s.isNotEmpty)
        .join('\n');
    if (fromRaw.isNotEmpty) return fromRaw;
    return _entries.map(_entryAsLine).join('\n');
  }

  static String _entryAsLine(RegisterOcrEntry e) {
    return [
      e.lineNo ?? '',
      e.name,
      e.placeAndBirthDate,
      e.parents,
      e.residentsOf,
      e.baptismDateText,
      e.minister,
      e.sponsors,
    ].join('\t');
  }

  void _finish() {
    final raw = StaffOcrScanResult(
      text: _textForExport(),
      entries: _entries,
      marriageEntries: _marriageEntries,
      lineCount: _scannedLines,
      cellCount: _scannedCells,
    );
    Navigator.pop(
      context,
      RegisterOcrScanHelper.finalizeScanResult(
        raw,
        recordType: widget.recordType,
      ),
    );
  }

  void _addRow() {
    setState(() {
      if (_isMarriage) {
        _marriageEntries.add(_emptyMarriageRow(_marriageEntries.length + 1));
      } else {
        _entries.add(_emptyRow(_entries.length + 1));
      }
    });
  }

  void _openBulkSave() {
    context.push(
      '/staff/ocr/bulk-records',
      extra: {
        'rawText': _textForExport(),
        'recordType': widget.recordType,
        'volNumber': widget.volNumber,
        'seriesNumber': widget.seriesNumber,
        'entries': _entries,
      },
    );
  }

  void _cancelScan() {
    if (_isProcessing) {
      Navigator.pop(context);
      return;
    }
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isBaptism = !_isMarriage;
    final validCount = _isMarriage
        ? _marriageEntries.where((e) => e.selected && e.isReadyToSave).length
        : _entries.where((e) => e.selected && e.isValid).length;
    final rowCount = _isMarriage ? _marriageEntries.length : _entries.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelScan();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isMarriage
                ? 'Marriage Register'
                : (isBaptism ? 'Baptism Register' : 'Scanned Records'),
          ),
          leading: BackButton(onPressed: _cancelScan),
          actions: [
            if (widget.showSaveAction && validCount > 0 && !_isProcessing)
              TextButton.icon(
                onPressed: _openBulkSave,
                icon: const Icon(Icons.save_outlined),
                label: Text('Save ($validCount)'),
              ),
            if (!_isProcessing)
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: _finish,
                tooltip: 'Done',
              ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  MaterialBanner(
                    content: Text('Scan issue: $_error'),
                    actions: [
                      TextButton(
                        onPressed: () => setState(() => _error = null),
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                _SummaryBar(
                  entryCount: rowCount,
                  skipped: _skippedLines,
                  validCount: validCount,
                  scannedLines: _scannedLines,
                  scannedCells: _scannedCells,
                  isScanning: _isProcessing,
                  pageCount: _pageCount,
                  isMarriage: _isMarriage,
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: _isProcessing ? null : _addRow,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add row'),
                      ),
                      TextButton.icon(
                        onPressed: _isProcessing ? null : _scanAnotherPage,
                        icon: const Icon(Icons.document_scanner_outlined,
                            size: 18),
                        label: Text(
                          _pageCount > 1
                              ? 'Scan other side ($_pageCount)'
                              : (_isMarriage
                                  ? 'Scan other page'
                                  : 'Scan other page'),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _isProcessing
                            ? 'Reading photo…'
                            : (rowCount > 1
                                ? '$rowCount record(s) — edit below'
                                : 'Edit cells below'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isMarriage
                      ? RegisterMarriageTable(
                          key: ValueKey('ocr-marriage-$_tableGeneration'),
                          fillGeneration: _tableGeneration,
                          entries: _marriageEntries,
                          onChanged: () => setState(() {}),
                          onSelectionChanged: () => setState(() {}),
                          onRemove: _isProcessing
                              ? null
                              : (i) =>
                                  setState(() => _marriageEntries.removeAt(i)),
                        )
                      : RegisterOcrTable(
                          key: ValueKey('ocr-table-$_tableGeneration'),
                          fillGeneration: _tableGeneration,
                          entries: _entries,
                          onChanged: () => setState(() {}),
                          onRemove: _isProcessing
                              ? null
                              : (i) => setState(() => _entries.removeAt(i)),
                        ),
                ),
              ],
            ),
            if (_isProcessing)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Center(
                    child: Card(
                      margin: const EdgeInsets.all(32),
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 20),
                            Text(
                              'Scanning register…',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Table will fill in when ready.\nYou can cancel if this takes too long.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isProcessing)
                  OutlinedButton.icon(
                    onPressed: _scanAnotherPage,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(
                      _pageCount > 1
                          ? 'Scan another register page'
                          : 'Add another page to this scan',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                if (!_isProcessing) const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _isProcessing ? null : _finish,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Done'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.entryCount,
    required this.skipped,
    required this.validCount,
    this.scannedLines = 0,
    this.scannedCells = 0,
    this.isScanning = false,
    this.pageCount = 0,
    this.isMarriage = false,
  });

  final int entryCount;
  final int skipped;
  final int validCount;
  final int scannedLines;
  final int scannedCells;
  final bool isScanning;
  final int pageCount;
  final bool isMarriage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isScanning
                ? 'Preparing $entryCount rows…'
                : '$entryCount record(s) — edit in table',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          if (pageCount > 1)
            Text(
              '$pageCount sides scanned (rows merged by register No.)',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          if (scannedLines > 0)
            Text(
              'Scanned $scannedLines lines · $scannedCells cells',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (skipped > 0)
                _Chip(label: '$skipped lines skipped when parsing'),
              _Chip(
                label: '$validCount ready to save',
                highlight: validCount > 0,
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
