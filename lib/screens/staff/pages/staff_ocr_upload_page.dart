import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../providers/ocr_jobs_provider.dart';
import '../../../services/ocr_jobs_repository.dart';
import '../../../models/register_marriage_entry.dart';
import '../../../models/register_ocr_entry.dart';
import '../../../services/ocr_image_pick.dart';
import '../../../services/ocr_service.dart';
import '../../../services/register_marriage_ocr_helper.dart';
import '../../../services/register_ocr_parser.dart';
import '../../../services/register_ocr_scan_helper.dart';
import '../../../widgets/register_scan_launcher.dart';
import 'staff_ocr_result_page.dart';

class StaffOcrUploadPage extends ConsumerStatefulWidget {
  const StaffOcrUploadPage({super.key});

  @override
  ConsumerState<StaffOcrUploadPage> createState() => _StaffOcrUploadPageState();
}

class _StaffOcrUploadPageState extends ConsumerState<StaffOcrUploadPage> {
  bool _handledRouteExtra = false;
  final _volCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  final _extractedTextCtrl = TextEditingController();
  String _type = 'baptism';
  bool _creating = false;
  String? _selectedImageName;
  String? _lastImagePath;
  List<RegisterOcrEntry> _lastParsedEntries = [];
  List<RegisterMarriageEntry> _lastMarriageEntries = [];
  int _lastLineCount = 0;
  int _lastCellCount = 0;
  int _scannedPageCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledRouteExtra) return;
    final extra = GoRouterState.of(context).extra;
    if (extra is Map && extra['scanResult'] is StaffOcrScanResult) {
      _handledRouteExtra = true;
      _applyScanResult(extra['scanResult'] as StaffOcrScanResult);
    }
  }

  @override
  void dispose() {
    _volCtrl.dispose();
    _seriesCtrl.dispose();
    _extractedTextCtrl.dispose();
    super.dispose();
  }

  bool get _hasRegisterData =>
      _lastParsedEntries.isNotEmpty ||
      _lastMarriageEntries.isNotEmpty ||
      _extractedTextCtrl.text.trim().isNotEmpty ||
      _lastImagePath != null;

  bool get _isMarriage => _type.toLowerCase() == 'marriage';

  Future<void> _openOcrEditor() async {
    final result = await Navigator.push<StaffOcrScanResult>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => StaffOcrResultPage(
          imagePath: _extractedTextCtrl.text.trim().isEmpty &&
                  _lastParsedEntries.isEmpty
              ? _lastImagePath
              : null,
          initialText: _extractedTextCtrl.text,
          initialEntries: _lastParsedEntries.isNotEmpty
              ? RegisterOcrScanHelper.ensureUniqueEntryIds(_lastParsedEntries)
              : null,
          initialMarriageEntries: _lastMarriageEntries.isNotEmpty
              ? RegisterMarriageOcrHelper.ensureUniqueEntryIds(
                  _lastMarriageEntries,
                )
              : null,
          initialPageCount: _scannedPageCount > 0 ? _scannedPageCount : 1,
          scannedLineCount: _lastLineCount,
          scannedCellCount: _lastCellCount,
          recordType: _type,
          volNumber: _volCtrl.text.trim(),
          seriesNumber: _seriesCtrl.text.trim(),
          showSaveAction: true,
        ),
      ),
    );
    _applyScanResult(result);
  }

  StaffOcrScanResult? _buildExistingScan() {
    if (_extractedTextCtrl.text.trim().isEmpty &&
        _lastParsedEntries.isEmpty &&
        _lastMarriageEntries.isEmpty) {
      return null;
    }
    return StaffOcrScanResult(
      text: _extractedTextCtrl.text,
      entries: _lastParsedEntries,
      marriageEntries: _lastMarriageEntries,
      lineCount: _lastLineCount,
      cellCount: _lastCellCount,
    );
  }

  void _applyScanResult(StaffOcrScanResult? result) {
    if (result == null || !mounted) return;
    final normalized = RegisterOcrScanHelper.finalizeScanResult(
      result,
      recordType: _type,
    );
    setState(() {
      _extractedTextCtrl.text = normalized.text;
      _lastParsedEntries = normalized.entries;
      _lastMarriageEntries = normalized.marriageEntries;
      _lastLineCount = result.lineCount > 0
          ? result.lineCount
          : _extractedTextCtrl.text
              .split(RegExp(r'\r?\n'))
              .where((l) => l.trim().isNotEmpty)
              .length;
      _lastCellCount = _isMarriage
          ? _lastMarriageEntries.length
          : _lastParsedEntries.length;
    });
  }

  Future<void> _takePhoto() async {
    await _pickAndScanPages(allowMultiple: false, preferCamera: true);
  }

  Future<void> _uploadFile() async {
    await _pickAndScanPages(allowMultiple: true, preferCamera: false);
  }

  Future<void> _scanMorePages() async {
    await _pickAndScanPages(allowMultiple: true, preferCamera: false);
  }

  Future<void> _pickAndScanPages({
    required bool allowMultiple,
    required bool preferCamera,
  }) async {
    try {
      List<XFile> picked;
      if (preferCamera && ocrSupportsCamera) {
        final shot = await OcrImagePick.pickCameraPhoto();
        if (shot == null || !mounted) return;
        picked = [shot];
      } else if (_hasRegisterData || !ocrSupportsCamera) {
        picked = await OcrImagePick.pickRegisterPages(
          context,
          allowMultiple: allowMultiple,
          includeCamera: ocrSupportsCamera,
        );
      } else {
        picked = await OcrImagePick.pickRegisterPages(
          context,
          allowMultiple: allowMultiple,
        );
      }
      if (picked.isEmpty || !mounted) return;
      final label = picked.length == 1
          ? picked.first.name
          : '${picked.length} pages';
      await _scanPickedFiles(picked, label);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to pick image: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _scanPickedFiles(List<XFile> files, String label) async {
    setState(() {
      _selectedImageName = label;
      _lastImagePath = files.first.path;
    });

    final result = await RegisterScanLauncher.scanXFilesAutofill(
      context: context,
      files: files,
      recordType: _type,
      volNumber: _volCtrl.text.trim(),
      seriesNumber: _seriesCtrl.text.trim(),
      existing: _buildExistingScan(),
      openReviewIfEmpty: false,
    );
    if (result == null || !mounted) return;

    _applyScanResult(result);
    setState(() => _scannedPageCount += files.length);

    if (!mounted) return;
    await _openOcrEditor();
  }

  List<RegisterOcrEntry> _baptismEntriesForForm() {
    if (_lastParsedEntries.any(
      (e) =>
          e.name.trim().isNotEmpty ||
          e.placeAndBirthDate.trim().isNotEmpty ||
          e.parents.trim().isNotEmpty,
    )) {
      return RegisterOcrScanHelper.autofillForTable(_lastParsedEntries);
    }
    final text = _extractedTextCtrl.text.trim();
    if (text.isEmpty) return [];
    return RegisterOcrScanHelper.resolveTableRows(
      ocrText: text,
      parsed: RegisterOcrParser.parse(text, recordType: 'baptism').entries,
      recordType: 'baptism',
    );
  }

  List<RegisterMarriageEntry> _marriageEntriesForForm() {
    if (_lastMarriageEntries.any(RegisterMarriageOcrHelper.entryHasData)) {
      return RegisterMarriageOcrHelper.autofillForTable(_lastMarriageEntries);
    }
    final text = _extractedTextCtrl.text.trim();
    if (text.isEmpty) return [];
    return RegisterMarriageOcrHelper.resolveTableRows(
      ocrText: text,
      parsedOcr: RegisterOcrParser.parse(text, recordType: 'marriage').entries,
    );
  }

  void _openManualRegister() {
    if (_isMarriage) {
      final entries = _marriageEntriesForForm();
      if (entries.isEmpty && _extractedTextCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scan or upload a register photo first.')),
        );
        return;
      }
      context.push(
        '/staff/records/manual-marriage',
        extra: {
          'volNo': _volCtrl.text.trim(),
          'seriesNo': _seriesCtrl.text.trim(),
          'marriageEntries': entries,
        },
      );
      return;
    }
    final entries = _baptismEntriesForForm();
    if (entries.isEmpty && _extractedTextCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan or upload a register photo first.')),
      );
      return;
    }
    context.push(
      '/staff/records/manual-baptism',
      extra: {
        'volNo': _volCtrl.text.trim(),
        'seriesNo': _seriesCtrl.text.trim(),
        'ocrEntries': entries,
      },
    );
  }

  void _openBulkImport() {
    final text = _extractedTextCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scan or paste register text first.'),
        ),
      );
      return;
    }
    context.push(
      '/staff/ocr/bulk-records',
      extra: {
        'rawText': text,
        'recordType': _type,
        'volNumber': _volCtrl.text.trim(),
        'seriesNumber': _seriesCtrl.text.trim(),
      },
    );
  }

  Future<void> _createJob() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final rawText = _extractedTextCtrl.text.trim();
      final entries = _lastParsedEntries.isNotEmpty
          ? _lastParsedEntries
          : RegisterOcrParser.parse(rawText, recordType: _type).entries;
      final repo = OcrJobsRepository();
      final jobId = await repo.createJob(
        type: _type,
        volNumber: _volCtrl.text.trim(),
        seriesNumber: _seriesCtrl.text.trim(),
        rawText: rawText,
        parsedEntries: registerEntriesToMaps(entries),
      );
      if (!mounted) return;
      ref.invalidate(ocrJobsAssignedToMeProvider(50));
      final goVerify = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('OCR job created'),
          content: const Text(
            'Open verification now to review rows and save official records?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Verify now'),
            ),
          ],
        ),
      );
      if (goVerify == true && mounted) {
        context.go('/staff/ocr/verify', extra: {'id': jobId});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('OCR job created — find it under OCR Verify'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      _volCtrl.clear();
      _seriesCtrl.clear();
      _extractedTextCtrl.clear();
      setState(() {
        _selectedImageName = null;
        _lastImagePath = null;
        _lastParsedEntries = [];
        _lastMarriageEntries = [];
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create OCR job: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.of(context).size;
    final width = size.width;

    // Responsive breakpoints
    final isDesktop = width >= 1200;
    final isTablet = width >= 768 && width < 1200;
    final isMobile = width < 768;

    final horizontalPadding = isDesktop ? 32.0 : (isTablet ? 24.0 : 16.0);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(horizontalPadding),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(colorScheme, theme, isMobile),
                  SizedBox(height: isTablet ? 24 : 20),
                  _buildFormCard(colorScheme, theme, isMobile),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme, ThemeData theme, bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.secondary.withValues(alpha: 0.15),
            colorScheme.primary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 10 : 12),
            decoration: BoxDecoration(
              color: colorScheme.secondary,
              borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.secondary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.document_scanner_outlined,
              color: colorScheme.onSecondary,
              size: isMobile ? 24 : 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upload register photo',
                  style: GoogleFonts.poppins(
                    fontSize: isMobile ? 20 : 24,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ocrUploadHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(
    ColorScheme colorScheme,
    ThemeData theme,
    bool isMobile,
  ) {
    return Card(
      elevation: 2,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 20 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sacrament Type
            _buildDropdown(colorScheme, theme),
            const SizedBox(height: 20),

            // Volume & Series Number
            TextField(
              controller: _volCtrl,
              decoration: InputDecoration(
                labelText: 'Vol Number',
                hintText: 'Enter register volume number',
                prefixIcon: Icon(Icons.library_books_outlined,
                    color: colorScheme.primary),
                filled: true,
                fillColor: colorScheme.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _seriesCtrl,
              decoration: InputDecoration(
                labelText: 'Series Number',
                hintText: 'Enter register series number',
                prefixIcon: Icon(Icons.numbers_outlined,
                    color: colorScheme.primary),
                filled: true,
                fillColor: colorScheme.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Upload Options
            _buildUploadSection(colorScheme, theme, isMobile),
            const SizedBox(height: 24),

            // Register table section (after scan or manual open)
            if (_hasRegisterData || _selectedImageName != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.table_chart_outlined,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Register table ready',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (_isMarriage
                              ? _lastMarriageEntries.length
                              : _lastParsedEntries.length) >
                          0
                          ? '${_isMarriage ? _lastMarriageEntries.length : _lastParsedEntries.length} '
                              'record(s) from ${_scannedPageCount > 0 ? _scannedPageCount : 1} '
                              'page(s). Add another page to merge by register No.'
                          : (_isMarriage
                              ? 'Scan left page (Man/Woman rows), then right page '
                                  '(Parents, Sponsors, Minister, License).'
                              : 'Scan left page first, then add the opposite page '
                                  'for Residents, Baptism, Minister, Sponsors.'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _hasRegisterData ? _openOcrEditor : null,
                        icon: const Icon(Icons.table_view_outlined),
                        label: const Text('View & Edit Register Table'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: _hasRegisterData ? _scanMorePages : null,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          _scannedPageCount > 0
                              ? 'Add another page (${_scannedPageCount} scanned)'
                              : 'Add another page',
                        ),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: FilledButton.tonalIcon(
                        onPressed: _hasRegisterData ? _openManualRegister : null,
                        icon: const Icon(Icons.edit_note_outlined),
                        label: Text(
                          _isMarriage
                              ? 'Fill Marriage Register Form'
                              : 'Fill Baptism Register Form',
                        ),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: (_extractedTextCtrl.text.trim().isNotEmpty ||
                                _lastParsedEntries.isNotEmpty ||
                                _lastMarriageEntries.isNotEmpty)
                            ? _openBulkImport
                            : null,
                        icon: const Icon(Icons.library_add_check_outlined),
                        label: const Text('Save Records to Firestore'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _creating ? null : _createJob,
                icon: _creating
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.add_circle_outline),
                label: Text(
                  _creating ? 'Creating...' : 'Create OCR Job',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(ColorScheme colorScheme, ThemeData theme) {
    final sacramentTypes = [
      ('baptism', 'Baptism', Icons.water_drop_outlined, Colors.blue),
      ('marriage', 'Marriage', Icons.favorite_outline, Colors.pink),
      ('confirmation', 'Confirmation', Icons.church_outlined, Colors.purple),
      ('death', 'Death', Icons.sentiment_dissatisfied_outlined, Colors.grey),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sacrament Type',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.category, color: colorScheme.primary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              items: sacramentTypes.map((type) {
                return DropdownMenuItem(
                  value: type.$1,
                  child: Row(
                    children: [
                      Icon(type.$3, color: type.$4, size: 20),
                      const SizedBox(width: 12),
                      Text(type.$2),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => _type = v ?? 'baptism'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadSection(
    ColorScheme colorScheme,
    ThemeData theme,
    bool isMobile,
  ) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                color: colorScheme.primary,
                size: isMobile ? 18 : 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Upload Options',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (ocrSupportsCamera)
            Row(
              children: [
                Expanded(
                  child: _buildUploadButton(
                    icon: Icons.camera_alt_outlined,
                    label: 'Take Photo',
                    color: colorScheme.primary,
                    onTap: _takePhoto,
                  ),
                ),
                SizedBox(width: isMobile ? 10 : 12),
                Expanded(
                  child: _buildUploadButton(
                    icon: Icons.upload_file_outlined,
                    label: 'Upload Image',
                    color: colorScheme.secondary,
                    onTap: _uploadFile,
                  ),
                ),
              ],
            )
          else
            _buildUploadButton(
              icon: Icons.upload_file_outlined,
              label: 'Upload Image',
              color: colorScheme.primary,
              onTap: _uploadFile,
              fullWidth: true,
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/staff/ocr/preprocess'),
              icon: const Icon(Icons.tune_outlined, size: 18),
              label: const Text('Preprocess image first'),
            ),
          ),
          const SizedBox(height: 10),
          if (_hasRegisterData)
            SizedBox(
              width: double.infinity,
              height: 40,
              child: TextButton.icon(
                onPressed: _scanMorePages,
                icon: const Icon(Icons.layers_outlined, size: 18),
                label: Text(
                  _scannedPageCount > 0
                      ? 'Scan more pages (${_scannedPageCount} merged)'
                      : 'Scan more pages',
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (_selectedImageName != null) ...[
            Text(
              'Selected file: $_selectedImageName',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Center(
            child: Text(
              ocrSupportsCamera
                  ? 'JPG/PNG — pick multiple images or scan page-by-page (merged by No.)'
                  : 'JPG/PNG — select multiple pages at once; rows merge by register No.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool fullWidth = false,
  }) {
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
    return button;
  }
}
