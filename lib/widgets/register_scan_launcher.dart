import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/register_marriage_entry.dart';
import '../models/register_ocr_entry.dart';
import '../screens/staff/pages/staff_ocr_result_page.dart';
import '../services/ocr_image_pick.dart';
import '../services/ocr_service.dart';
import '../services/register_marriage_ocr_helper.dart';
import '../services/register_ocr_scan_helper.dart';

/// Upload parish register photos → OCR → autofill table rows.
class RegisterScanLauncher {
  RegisterScanLauncher._();

  /// Pick photo(s), run OCR, return rows for the parent form to apply.
  /// Shows a loading dialog while reading the image. Opens review only if empty.
  /// Pick from gallery/camera sheet, then OCR + autofill.
  static Future<StaffOcrScanResult?> uploadPhotoAutofill({
    required BuildContext context,
    required String recordType,
    String volNumber = '',
    String seriesNumber = '',
    StaffOcrScanResult? existing,
    bool allowMultiple = true,
  }) async {
    final files = await _pickImageFiles(context, allowMultiple: allowMultiple);
    if (files == null || files.isEmpty || !context.mounted) return null;

    return scanXFilesAutofill(
      context: context,
      files: files,
      recordType: recordType,
      volNumber: volNumber,
      seriesNumber: seriesNumber,
      existing: existing,
      openReviewIfEmpty: true,
    );
  }

  /// OCR + autofill from picked image files (camera or upload).
  static Future<StaffOcrScanResult?> scanXFilesAutofill({
    required BuildContext context,
    required List<XFile> files,
    required String recordType,
    String volNumber = '',
    String seriesNumber = '',
    StaffOcrScanResult? existing,
    bool openReviewIfEmpty = true,
  }) async {
    if (files.isEmpty || !context.mounted) return null;

    final scan = await _runScanWithProgress(
      context,
      files: files,
      recordType: recordType,
      existing: existing,
    );
    if (!context.mounted || scan == null) return null;

    final finalized = RegisterOcrScanHelper.finalizeScanResult(
      scan,
      recordType: recordType,
    );

    final hasRows = RegisterOcrScanHelper.scanHasAutofillData(finalized);

    if (!hasRows && openReviewIfEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'No register rows detected. Wait for OCR to finish (first run '
                    'downloads language data), try a clearer photo, or edit manually.'
                : 'No register rows detected. Try a clearer photo or edit manually.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      final review = await _openEditor(
        context,
        recordType: recordType,
        volNumber: volNumber,
        seriesNumber: seriesNumber,
        imagePath: files.length == 1 ? files.first.path : null,
        initialText: finalized.text,
        initialEntries: finalized.entries.isNotEmpty ? finalized.entries : null,
        initialMarriageEntries: finalized.marriageEntries.isNotEmpty
            ? finalized.marriageEntries
            : null,
        lineCount: finalized.lineCount,
        cellCount: finalized.cellCount,
        pageCount: files.length,
      );
      return review != null
          ? RegisterOcrScanHelper.finalizeScanResult(
              review,
              recordType: recordType,
            )
          : finalized;
    }

    return finalized;
  }

  /// OCR + autofill from paths already chosen (camera or gallery).
  static Future<StaffOcrScanResult?> scanPathsAutofill({
    required BuildContext context,
    required List<String> paths,
    required String recordType,
    String volNumber = '',
    String seriesNumber = '',
    StaffOcrScanResult? existing,
    bool openReviewIfEmpty = true,
  }) async {
    if (paths.isEmpty || !context.mounted) return null;
    final files = paths.map((p) => XFile(p)).toList();
    return scanXFilesAutofill(
      context: context,
      files: files,
      recordType: recordType,
      volNumber: volNumber,
      seriesNumber: seriesNumber,
      existing: existing,
      openReviewIfEmpty: openReviewIfEmpty,
    );
  }

  /// Legacy: pick source then scan (may open review editor).
  static Future<StaffOcrScanResult?> scanRegister({
    required BuildContext context,
    required String recordType,
    String volNumber = '',
    String seriesNumber = '',
    StaffOcrScanResult? existing,
  }) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Upload photo'),
              subtitle: const Text('Gallery — select one or more pages'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            if (ocrSupportsCamera)
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
          ],
        ),
      ),
    );

    if (!context.mounted || source == null) return null;

    List<XFile> files;
    if (source == ImageSource.gallery) {
      files = await OcrImagePick.pickImages(allowMultiple: true);
      if (files.isEmpty || !context.mounted) return null;
    } else {
      final picked = await OcrImagePick.pickCameraPhoto();
      if (picked == null || !context.mounted) return null;
      files = [picked];
    }

    final scan = await _runScanWithProgress(
      context,
      files: files,
      recordType: recordType,
      existing: existing,
    );
    if (!context.mounted || scan == null) return null;

    return _openEditor(
      context,
      recordType: recordType,
      volNumber: volNumber,
      seriesNumber: seriesNumber,
      imagePath: files.length == 1 ? files.first.path : null,
      initialText: scan.text,
      initialEntries: scan.entries.isNotEmpty ? scan.entries : null,
      initialMarriageEntries:
          scan.marriageEntries.isNotEmpty ? scan.marriageEntries : null,
      lineCount: scan.lineCount,
      cellCount: scan.cellCount,
      pageCount: files.length,
    );
  }

  static Future<List<XFile>?> _pickImageFiles(
    BuildContext context, {
    required bool allowMultiple,
  }) async {
    if (!context.mounted) return null;
    final picked = await OcrImagePick.pickRegisterPages(
      context,
      allowMultiple: allowMultiple,
    );
    return picked.isEmpty ? null : picked;
  }

  static Future<StaffOcrScanResult?> _runScanWithProgress(
    BuildContext context, {
    required List<XFile> files,
    required String recordType,
    StaffOcrScanResult? existing,
  }) async {
    return showDialog<StaffOcrScanResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ScanProgressDialog(
        files: files,
        recordType: recordType,
        existing: existing,
      ),
    );
  }

  static Future<StaffOcrScanResult?> _openEditor(
    BuildContext context, {
    required String recordType,
    required String volNumber,
    required String seriesNumber,
    String? imagePath,
    String initialText = '',
    List<RegisterOcrEntry>? initialEntries,
    List<RegisterMarriageEntry>? initialMarriageEntries,
    int lineCount = 0,
    int cellCount = 0,
    int pageCount = 0,
  }) {
    return Navigator.push<StaffOcrScanResult>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => StaffOcrResultPage(
          imagePath: imagePath,
          initialText: initialText,
          initialEntries: initialEntries,
          initialMarriageEntries: initialMarriageEntries,
          scannedLineCount: lineCount,
          scannedCellCount: cellCount,
          initialPageCount: pageCount,
          recordType: recordType,
          volNumber: volNumber,
          seriesNumber: seriesNumber,
          showSaveAction: false,
        ),
      ),
    );
  }
}

class _ScanProgressDialog extends StatefulWidget {
  const _ScanProgressDialog({
    required this.files,
    required this.recordType,
    this.existing,
  });

  final List<XFile> files;
  final String recordType;
  final StaffOcrScanResult? existing;

  @override
  State<_ScanProgressDialog> createState() => _ScanProgressDialogState();
}

class _ScanProgressDialogState extends State<_ScanProgressDialog> {
  String _status = 'Preparing…';
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      final total = widget.files.length;
      var mergedText = widget.existing?.text ?? '';
      var mergedBaptism =
          List<RegisterOcrEntry>.from(widget.existing?.entries ?? []);
      var mergedMarriage = List<RegisterMarriageEntry>.from(
        widget.existing?.marriageEntries ?? [],
      );
      var lineCount = widget.existing?.lineCount ?? 0;
      var cellCount = widget.existing?.cellCount ?? 0;
      final isMarriage = widget.recordType.toLowerCase() == 'marriage';

      for (var i = 0; i < total; i++) {
        if (!mounted) return;
        setState(() {
          _page = i + 1;
          _status = total > 1
              ? 'Reading page $_page of $total…'
              : (kIsWeb
                  ? 'Reading register (first scan may take 1–2 min)…'
                  : 'Reading register photo…');
        });

        final scan = await RegisterOcrScanHelper.scanXFile(
          widget.files[i],
          recordType: widget.recordType,
        );

        mergedText = RegisterOcrScanHelper.mergeScanText(mergedText, scan.text);
        lineCount += scan.lineCount;
        cellCount += scan.cellCount;

        if (isMarriage) {
          mergedMarriage = RegisterMarriageOcrHelper.appendPageEntries(
            mergedMarriage,
            scan.marriageEntries,
          );
        } else {
          mergedBaptism = RegisterOcrScanHelper.appendPageEntries(
            mergedBaptism,
            scan.entries,
          );
        }
      }

      if (!mounted) return;

      final merged = StaffOcrScanResult(
        text: mergedText,
        entries: mergedBaptism,
        marriageEntries: mergedMarriage,
        lineCount: lineCount,
        cellCount: cellCount,
      );
      final result = RegisterOcrScanHelper.finalizeScanResult(
        merged,
        recordType: widget.recordType,
      );

      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not read photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reading register'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 20),
          Text(_status, textAlign: TextAlign.center),
          if (widget.files.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              'Pages are merged by register number (No.)',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
