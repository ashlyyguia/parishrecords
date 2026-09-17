import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/record.dart';
import '../../../models/register_marriage_entry.dart';
import '../../../models/register_ocr_entry.dart';
import '../../../providers/records_provider.dart';
import '../../../services/marriage_ocr_service.dart';
import '../../../services/marriage_row_validation.dart';
import '../../../services/ocr_image_pick.dart';
import '../../../utils/manual_register_notes.dart';
import '../../../widgets/page_header.dart';
import '../../../widgets/register_marriage_table.dart';

enum _Step { pick, preview, processing, review }

/// Human-readable explanations for [MarriageOcrScan.warnings] codes.
///
/// Reuses the baptismal copy for the shared codes and adds the marriage-only
/// [GROOM_BRIDE_SPLIT_UNCERTAIN], which means the two printed lines (groom on
/// top, bride below) couldn't be told apart in one or more rows -- a reviewer
/// must check which value belongs to whom before saving.
const Map<String, String> marriageOcrWarningCopy = {
  'LAYOUT_UNCERTAIN':
      'The page layout could not be confidently detected. Check that every '
      'value landed in the correct column before saving.',
  'ROW_ANCHOR_FALLBACK':
      "Row positions were estimated with a fallback method. Verify each "
      "row's line number matches the physical register.",
  'GUTTER_UNCONFIRMED':
      'The gap between the left and right register pages could not be '
      'confirmed. Double-check that left-page and right-page fields line '
      'up on the same row.',
  'GROOM_BRIDE_SPLIT_UNCERTAIN':
      'Groom and bride could not be told apart in one or more rows — check '
      "each row's top (groom) and bottom (bride) values before saving.",
};

/// Scan -> OCR -> review -> save, for marriage register spreads.
///
/// Mirrors [BaptismalOcrScanPage]: the image, picker, uploader, token, save
/// action and existing records are all injectable so widget tests run without a
/// camera, a network or Firebase.
class MarriageOcrScanPage extends ConsumerStatefulWidget {
  const MarriageOcrScanPage({
    super.key,
    this.ocrService,
    this.imagePicker,
    this.imageUploader,
    this.idTokenProvider,
    this.saveRecords,
    this.existingRecords,
  });

  final MarriageOcrService? ocrService;
  final Future<Uint8List?> Function(BuildContext context)? imagePicker;
  final Future<String?> Function(String scanId, Uint8List bytes)? imageUploader;
  final List<ParishRecord> Function()? existingRecords;
  final Future<String?> Function()? idTokenProvider;
  final Future<int> Function(List<RegisterRecordDraft> drafts)? saveRecords;

  @override
  ConsumerState<MarriageOcrScanPage> createState() =>
      _MarriageOcrScanPageState();
}

class _MarriageOcrScanPageState extends ConsumerState<MarriageOcrScanPage> {
  static const _uuid = Uuid();

  late final MarriageOcrService _service =
      widget.ocrService ?? MarriageOcrService();

  _Step _step = _Step.pick;
  Uint8List? _bytes;
  String _scanId = '';
  String? _imagePath;
  bool _archiveFailed = false;
  List<RegisterMarriageEntry> _entries = [];
  List<String> _warnings = const [];
  MarriageOcrFailure? _failure;
  bool _saving = false;
  // Bumped whenever a fill-down/programmatic edit should force the register
  // table's text fields to rebuild from the model (see RegisterMarriageTable).
  int _fillGen = 0;

  final _volCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();

  @override
  void dispose() {
    _volCtrl.dispose();
    _seriesCtrl.dispose();
    super.dispose();
  }

  List<ParishRecord> get _existingRecords => widget.existingRecords != null
      ? widget.existingRecords!()
      : ref.read(recordsProvider);

  List<MarriageRowIssue> get _issues =>
      validateMarriageRows(_entries, existing: _existingRecords);

  // Layout warnings only -- the confidence notice has its own banner, and
  // CV_UNAVAILABLE is an internal fallback signal, neither of which belongs in
  // the red "review these before saving" panel.
  static const Set<String> _nonLayoutWarnings = {
    'CONFIDENCE_UNAVAILABLE',
    'CV_UNAVAILABLE',
  };
  List<String> get _layoutWarnings =>
      _warnings.where((c) => !_nonLayoutWarnings.contains(c)).toList();

  bool get _canSave =>
      !_saving &&
      _entries.any((e) => e.selected) &&
      !_issues.any((i) => i.blocking);

  Future<void> _pick() async {
    Uint8List? bytes;
    if (widget.imagePicker != null) {
      bytes = await widget.imagePicker!(context);
    } else {
      if (!mounted) return;
      final files = await OcrImagePick.pickRegisterPages(
        context,
        allowMultiple: false,
        fullResolution: true,
      );
      if (files.isNotEmpty) bytes = await files.first.readAsBytes();
    }
    if (bytes == null || !mounted) return;
    setState(() {
      _bytes = bytes;
      _scanId = _uuid.v4();
      _imagePath = null;
      _archiveFailed = false;
      _failure = null;
      _entries = [];
      _warnings = const [];
      _step = _Step.preview;
    });
  }

  Future<void> _runOcr() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() {
      _step = _Step.processing;
      _failure = null;
    });

    final uploader = widget.imageUploader;
    if (_imagePath == null && !_archiveFailed && uploader != null) {
      try {
        final uploaded = await uploader(_scanId, bytes);
        _imagePath = uploaded;
        _archiveFailed = uploaded == null;
      } catch (_) {
        _imagePath = null;
        _archiveFailed = true;
      }
    }

    try {
      final token = widget.idTokenProvider == null
          ? null
          : await widget.idTokenProvider!();
      final scan = await _service.scan(
        scanId: _scanId,
        bytes: bytes,
        idToken: token,
      );
      if (!mounted) return;
      setState(() {
        _entries = scan.entries;
        _warnings = scan.warnings;
        _step = _Step.review;
      });
    } on MarriageOcrFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e;
        _step = _Step.preview;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final selected =
        _entries.where((e) => e.selected && e.isReadyToSave).toList();
    final drafts = <RegisterRecordDraft>[];

    for (final entry in selected) {
      drafts.add(
        RegisterRecordDraft(
          type: RecordType.marriage,
          name: entry.recordDisplayName,
          date: ManualRegisterNotes.marriageDateForEntry(entry),
          parish: entry.primaryAddress.isNotEmpty
              ? entry.primaryAddress
              : 'Parish Register',
          imagePath: _imagePath,
          notes: jsonEncode(
            ManualRegisterNotes.toMarriageOcrNotesMap(
              volNo: _volCtrl.text.trim(),
              seriesNo: _seriesCtrl.text.trim(),
              entry: entry,
              scanId: _scanId,
              imagePath: _imagePath,
            ),
          ),
        ),
      );
    }

    try {
      final saveRecords = widget.saveRecords ??
          ((List<RegisterRecordDraft> d) =>
              ref.read(recordsProvider.notifier).addRecordsBatch(d));
      final saved = await saveRecords(drafts);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $saved marriage record(s).')),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard reviewed rows?'),
        content: const Text("The rows you've reviewed and edited will be lost."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: PageHeader(
                icon: Icons.document_scanner_outlined,
                title: 'Add Marriage Records (OCR)',
                subtitle:
                    'Scan a marriage register spread, review the rows, then save.',
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: switch (_step) {
                _Step.pick => _pickStep(),
                _Step.preview => _previewStep(),
                _Step.processing => _processingStep(),
                _Step.review => _reviewStep(),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _captureGuide() {
    const tips = <(IconData, String)>[
      (Icons.menu_book_outlined,
          'Lay the book flat and press the spine down — the top cause of an unreadable page.'),
      (Icons.crop_free, 'Fit both pages fully in the frame, straight-on.'),
      (Icons.wb_sunny_outlined,
          'Even lighting — no glare or shadow across the page.'),
      (Icons.zoom_in,
          "Fill the frame with the register; don't shoot from far away."),
    ];
    return Card(
      key: const ValueKey('capture-guide'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('For a readable scan',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final (icon, text) in tips)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pickStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _captureGuide(),
                  FilledButton.icon(
                    key: const ValueKey('pick-image'),
                    onPressed: _pick,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Choose image'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewStep() {
    final failure = _failure;
    final showScanAction =
        failure == null || failure.recovery == OcrRecovery.retry;
    final showChooseDifferent = failure == null ||
        failure.recovery == OcrRecovery.retry ||
        failure.recovery == OcrRecovery.differentImage;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (failure != null) ...[
            _captureGuide(),
            _errorBanner(failure),
          ],
          if (_bytes != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: Image.memory(
                _bytes!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    _previewUnavailable(),
              ),
            ),
          const SizedBox(height: 16),
          if (showScanAction)
            FilledButton.icon(
              onPressed: _runOcr,
              icon: const Icon(Icons.play_arrow),
              label: Text(failure != null ? 'Retry OCR' : 'Scan / Process OCR'),
            ),
          if (showScanAction) const SizedBox(height: 8),
          if (showChooseDifferent)
            OutlinedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.refresh),
              label: const Text('Choose a different image'),
            ),
        ],
      ),
    );
  }

  Widget _previewUnavailable() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 160,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined,
              color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            "Preview isn't available for this image format here (e.g. HEIC), "
            'but scanning will still work.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(MarriageOcrFailure failure) {
    final scheme = Theme.of(context).colorScheme;
    final hint = switch (failure.recovery) {
      OcrRecovery.retry => null,
      OcrRecovery.differentImage =>
        "This image can't be read as a register page. Choose a clearer or "
            'different photo below.',
      OcrRecovery.signIn => 'Sign in again, then retry.',
      OcrRecovery.contactAdmin =>
        'This is a server configuration problem -- contact your system '
            'administrator. Nothing here can fix it.',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  failure.message,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (failure.detail != null) ...[
            const SizedBox(height: 8),
            Text(failure.detail!,
                style: TextStyle(color: scheme.onErrorContainer)),
          ],
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(hint, style: TextStyle(color: scheme.onErrorContainer)),
          ],
        ],
      ),
    );
  }

  Widget _processingStep() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Reading the register with OCR.space...'),
          SizedBox(height: 4),
          Text('This can take a few seconds for a full page.'),
        ],
      ),
    );
  }

  Widget _warningsPanel(BuildContext context, List<String> codes) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('warnings-panel'),
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          iconColor: scheme.onErrorContainer,
          collapsedIconColor: scheme.onErrorContainer,
          leading: Icon(Icons.warning_amber_rounded, color: scheme.error),
          title: Text(
            '${codes.length} ${codes.length == 1 ? 'issue' : 'issues'} to review before saving',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.bold,
                ),
          ),
          children: [
            for (final code in codes)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${marriageOcrWarningCopy[code] ?? code}',
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _confidenceBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('confidence-banner'),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        children: [
          Icon(Icons.fact_check_outlined, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This OCR engine cannot score confidence. Please verify every '
              'field against the page before saving.',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _archiveFailedNotice(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('archive-failed-notice'),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'The original page photo could not be archived. The reviewed '
              'data below will still save normally.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewStep() {
    final issues = _issues;
    final blocking = issues.where((i) => i.blocking).length;
    final selected = _entries.where((e) => e.selected).length;

    return Column(
      children: [
        if (_warnings.contains('CONFIDENCE_UNAVAILABLE'))
          _confidenceBanner(context),
        if (_layoutWarnings.isNotEmpty) _warningsPanel(context, _layoutWarnings),
        if (_archiveFailed) _archiveFailedNotice(context),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _volCtrl,
                  decoration: const InputDecoration(labelText: 'Vol. No.'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _seriesCtrl,
                  decoration: const InputDecoration(labelText: 'Series'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No rows were detected in this scan. Try a clearer '
                      'photo or a different page.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RegisterMarriageTable(
                  entries: _entries,
                  fillGeneration: _fillGen,
                  onChanged: () => setState(() {}),
                  onSelectionChanged: () => setState(() {}),
                  onRemove: (i) => setState(() {
                    _entries.removeAt(i);
                    _fillGen++;
                  }),
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                if (blocking > 0)
                  Text(
                    '$blocking field(s) need attention before saving.',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const ValueKey('save-rows'),
                  onPressed: _canSave ? _save : null,
                  icon: const Icon(Icons.save_outlined),
                  label: Text('Save $selected record(s)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('choose-another-image'),
                  onPressed: () async {
                    if (await _confirmDiscard()) await _pick();
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Choose another image'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
