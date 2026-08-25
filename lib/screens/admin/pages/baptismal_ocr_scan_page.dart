import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/baptismal_register_row.dart';
import '../../../models/record.dart';
import '../../../models/register_ocr_entry.dart';
import '../../../providers/records_provider.dart';
import '../../../services/baptismal_ocr_service.dart';
import '../../../services/baptismal_row_validation.dart';
import '../../../services/ocr_image_pick.dart';
import '../../../utils/manual_register_notes.dart';
import '../../../widgets/baptismal_ocr_review_table.dart';

enum _Step { pick, preview, processing, review }

/// Human-readable explanations for [BaptismalOcrScan.warnings] codes.
///
/// These are not decoration: several of them (especially
/// `ROW_ALIGNMENT_MISMATCH`) mean the left and right pages of the spread may
/// have been joined onto the WRONG rows -- i.e. a child's name paired with
/// another child's parents and baptism date. A reviewer needs to actually
/// read and act on these before saving.
const Map<String, String> baptismalOcrWarningCopy = {
  'LAYOUT_UNCERTAIN':
      'The page layout could not be confidently detected. Check that every '
      'value landed in the correct column before saving.',
  'ROW_ANCHOR_FALLBACK':
      "Row positions were estimated with a fallback method. Verify each "
      "row's line number matches the physical register.",
  'ROW_COUNT_MISMATCH':
      "The number of rows found doesn't match what was expected on this "
      'page. Check for rows that were skipped or duplicated.',
  'ROW_ALIGNMENT_MISMATCH':
      "The left and right pages of the spread may have been joined onto "
      "the WRONG rows. Double-check that each child's name is paired with "
      'the correct parents, sponsors, and baptism date before saving.',
  'GUTTER_UNCONFIRMED':
      'The gap between the left and right register pages could not be '
      'confirmed. Double-check that left-page and right-page fields line '
      'up on the same row.',
  'MANY_WORDS_UNPLACED':
      'Many words on this page could not be placed into a column. Some '
      'fields may be missing or incomplete -- check every row carefully.',
};

/// Scan -> OCR -> review -> save, for baptismal register spreads.
///
/// The image, the picker and the uploader are injectable so widget tests can
/// run without a camera, a network or Firebase.
class BaptismalOcrScanPage extends ConsumerStatefulWidget {
  const BaptismalOcrScanPage({
    super.key,
    this.ocrService,
    this.imagePicker,
    this.imageUploader,
    this.idTokenProvider,
    this.saveRecords,
    this.existingRecords,
  });

  final BaptismalOcrService? ocrService;
  final Future<Uint8List?> Function(BuildContext context)? imagePicker;
  final Future<String?> Function(String scanId, Uint8List bytes)? imageUploader;

  /// Resolves the existing records to check new rows against for cross-scan
  /// duplicates (see [validateBaptismalRows]'s `existing` parameter).
  /// Defaults to `ref.read(recordsProvider)` when null -- left null in
  /// production. Scanning the same register page twice without this check
  /// previously produced silent duplicate records, because
  /// `validateBaptismalRows(_rows)` only ever saw rows from the CURRENT scan.
  final List<ParishRecord> Function()? existingRecords;

  /// Resolves the Firebase ID token to send with the scan request.
  ///
  /// Only used when non-null. [BaptismalOcrService.scan] already resolves
  /// `FirebaseAuth.instance.currentUser?.getIdToken()` itself exactly once
  /// when it isn't handed a token, so the production path (this left null)
  /// deliberately does NOT duplicate that lookup here -- it passes `idToken:
  /// null` through and lets the service do it a single time. This field
  /// exists purely as the fourth widget-test seam, alongside [ocrService],
  /// [imagePicker] and [imageUploader]: tests inject a fake token here to
  /// short-circuit Firebase entirely (there is no Firebase app registered
  /// in a widget test).
  final Future<String?> Function()? idTokenProvider;

  /// Persists the confirmed rows. Defaults to
  /// `recordsProvider.notifier.addRecordsBatch`.
  ///
  /// `RecordsNotifier` (the provider's implementation) touches live
  /// Firestore/Firebase in its own field initializers -- even a `build()`
  /// override on a subclass can't dodge that, since the base class's field
  /// initializers run first, before `build()` is ever called. Injecting the
  /// save action itself is the only way to keep this page testable without
  /// Firebase; the production default is unchanged.
  final Future<int> Function(List<RegisterRecordDraft> drafts)? saveRecords;

  @override
  ConsumerState<BaptismalOcrScanPage> createState() =>
      _BaptismalOcrScanPageState();
}

class _BaptismalOcrScanPageState extends ConsumerState<BaptismalOcrScanPage> {
  static const _uuid = Uuid();

  late final BaptismalOcrService _service =
      widget.ocrService ?? BaptismalOcrService();

  _Step _step = _Step.pick;
  Uint8List? _bytes;
  String _scanId = '';
  String? _imagePath;
  bool _archiveFailed = false;
  List<BaptismalRegisterRow> _rows = [];
  List<String> _warnings = const [];
  BaptismalOcrFailure? _failure;
  int? _highlightedRow;
  bool _saving = false;

  final _volCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();

  @override
  void dispose() {
    _volCtrl.dispose();
    _seriesCtrl.dispose();
    super.dispose();
  }

  /// Existing records to check for cross-scan duplicates against. Defaults
  /// to the live `recordsProvider` in production; tests inject a fixed list
  /// via [BaptismalOcrScanPage.existingRecords] so this stays reachable
  /// without touching Firebase (see [saveRecords]'s COVERAGE NOTE for why
  /// `RecordsNotifier` itself can't be exercised from a widget test).
  List<ParishRecord> get _existingRecords =>
      widget.existingRecords != null
          ? widget.existingRecords!()
          : ref.read(recordsProvider);

  List<RowIssue> get _issues =>
      validateBaptismalRows(_rows, existing: _existingRecords);

  /// Layout warnings only — the confidence notice is surfaced by its own
  /// banner, not the red "review these before saving" panel.
  List<String> get _layoutWarnings =>
      _warnings.where((c) => c != 'CONFIDENCE_UNAVAILABLE').toList();
  bool get _canSave =>
      !_saving &&
      _rows.any((r) => r.selected) &&
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
      _rows = [];
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

    // The original page image is intentionally NOT archived to Firebase
    // Storage in production: this deployment doesn't use Storage (its bucket
    // has no web CORS policy, so a putData from a browser fails preflight and
    // spammed the console with a CORS error on every scan). Records save
    // without an archived original. Widget tests still inject [imageUploader]
    // to exercise the imagePath path; when it fails there, `_archiveFailed`
    // drives a non-blocking notice in the review step.
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
      // NOT calling widget.idTokenProvider ?? _someDefault here on purpose:
      // when idTokenProvider is null (the production case), passing
      // idToken: null lets BaptismalOcrService.scan() resolve
      // FirebaseAuth.instance.currentUser?.getIdToken() itself, exactly
      // once. Resolving a token here too and passing it down would make the
      // service's own `idToken ?? await _currentUserToken()` fallback
      // redundant only when this lookup succeeds, and would still fire a
      // second Firebase call whenever it returns null -- so this branch is
      // intentionally the single point of resolution.
      //
      // COVERAGE NOTE: every test in test/baptismal_ocr_scan_page_test.dart
      // injects idTokenProvider, so the `null` (production) path below --
      // which touches live FirebaseAuth via BaptismalOcrService -- is never
      // exercised by the automated suite. See the fix report for the manual
      // verification this needs.
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
        _rows = scan.rows;
        _warnings = scan.warnings;
        _step = _Step.review;
      });
    } on BaptismalOcrFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e;
        _step = _Step.preview;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final selected = _rows.where((r) => r.selected).toList();
    final drafts = <RegisterRecordDraft>[];

    for (final row in selected) {
      final date = baptismDateOf(row);
      if (date == null) continue;
      final fields = {
        for (final key in baptismalFieldKeys) key: row.field(key).value.trim(),
      };
      drafts.add(
        RegisterRecordDraft(
          type: RecordType.baptism,
          name: fields['nameOfChild'] ?? '',
          date: date,
          parish: (fields['residentsOf'] ?? '').isNotEmpty
              ? fields['residentsOf']
              : 'Parish Register',
          imagePath: _imagePath,
          // Only reached once a human has stepped through review and
          // pressed Save -- toBaptismalOcrNotesMap defaults status to
          // 'official', so this call must never happen speculatively.
          notes: _encodeNotes(row, fields),
        ),
      );
    }

    try {
      // COVERAGE NOTE: every test in test/baptismal_ocr_scan_page_test.dart
      // injects widget.saveRecords, so this `?? (...)` fallback -- the
      // actual recordsProvider.notifier.addRecordsBatch call that writes
      // sacramental records to Firestore -- is never exercised by the
      // automated suite. RecordsNotifier (records_provider.dart, which is
      // on the do-not-touch list) touches live FirebaseFirestore.instance
      // in an eager field initializer that runs before build(), so a
      // widget test cannot reach this line without a real Firebase app.
      // See the fix report for the manual verification this needs.
      final saveRecords =
          widget.saveRecords ??
          ((List<RegisterRecordDraft> d) =>
              ref.read(recordsProvider.notifier).addRecordsBatch(d));
      final saved = await saveRecords(drafts);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $saved baptismal record(s).')),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _encodeNotes(BaptismalRegisterRow row, Map<String, String> fields) {
    final map = ManualRegisterNotes.toBaptismalOcrNotesMap(
      volNo: _volCtrl.text.trim(),
      seriesNo: _seriesCtrl.text.trim(),
      lineNo: row.lineNo,
      fields: fields,
      scanId: _scanId,
      imagePath: _imagePath,
    );
    return jsonEncode(map);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Baptismal Records (OCR)')),
      body: switch (_step) {
        _Step.pick => _pickStep(),
        _Step.preview => _previewStep(),
        _Step.processing => _processingStep(),
        _Step.review => _reviewStep(),
      },
    );
  }

  Widget _pickStep() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.document_scanner_outlined, size: 64),
          const SizedBox(height: 12),
          const Text('Upload or capture a register page'),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('pick-image'),
            onPressed: _pick,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Choose image'),
          ),
        ],
      ),
    );
  }

  Widget _previewStep() {
    final failure = _failure;
    // Only OcrRecovery.retry means resubmitting the exact same bytes may
    // succeed. Every other recovery kind (differentImage / signIn /
    // contactAdmin) would fail identically on retry, so no retry action is
    // offered for those. In every case the image is retained and the step
    // returns to preview (never back to the bare pick step) -- the user is
    // never forced to re-pick just because a scan failed.
    final showScanAction =
        failure == null || failure.recovery == OcrRecovery.retry;
    // "Choose a different image" is only a genuine fix when the problem
    // might be the image itself (no failure yet, a transient failure worth
    // retrying with the same bytes, or differentImage where the bytes truly
    // are unusable). For signIn/contactAdmin the image was never the
    // problem, so pairing this button with those failures would falsely
    // imply picking a new photo helps; the error banner's hint carries the
    // real guidance for those two instead.
    final showChooseDifferent =
        failure == null ||
        failure.recovery == OcrRecovery.retry ||
        failure.recovery == OcrRecovery.differentImage;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (failure != null) _errorBanner(failure),
          if (_bytes != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: Image.memory(_bytes!, fit: BoxFit.contain),
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

  Widget _errorBanner(BaptismalOcrFailure failure) {
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Review these before saving',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final code in codes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• ${baptismalOcrWarningCopy[code] ?? code}',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
        ],
      ),
    );
  }

  /// OCR.space returns no per-field confidence, so there is nothing to flag
  /// cell-by-cell. This scan-level banner tells the reviewer to verify every
  /// field before saving.
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

  /// Non-blocking notice: the original page photo could not be archived to
  /// Storage. Saving still proceeds -- the reviewed data is what matters --
  /// but this must never be silent, or a clerk who later needs to re-check
  /// the physical register has no way to know the image isn't there.
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
    final selected = _rows.where((r) => r.selected).length;

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
          child: SingleChildScrollView(
            child: _rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No rows were detected in this scan. Try a clearer '
                      'photo or a different page.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : BaptismalOcrReviewTable(
                    rows: _rows,
                    issues: issues,
                    highlightedRow: _highlightedRow,
                    onRowTap: (i) => setState(() => _highlightedRow = i),
                    onChanged: (i, field, value) {
                      setState(() => _rows[i].setValue(field, value));
                    },
                    onSelectedChanged: (i, v) =>
                        setState(() => _rows[i].selected = v),
                    onLineNoChanged: (i, value) =>
                        setState(() => _rows[i].lineNo = value),
                  ),
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const ValueKey('save-rows'),
                  onPressed: _canSave ? _save : null,
                  icon: const Icon(Icons.save_outlined),
                  label: Text('Save $selected record(s)'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
