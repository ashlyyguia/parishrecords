import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/ocr_jobs_repository.dart';

class StaffOcrUploadPage extends ConsumerStatefulWidget {
  const StaffOcrUploadPage({super.key});

  @override
  ConsumerState<StaffOcrUploadPage> createState() => _StaffOcrUploadPageState();
}

class _StaffOcrUploadPageState extends ConsumerState<StaffOcrUploadPage> {
  final _bookCtrl = TextEditingController();
  final _pageCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _type = 'baptism';
  bool _creating = false;

  @override
  void dispose() {
    _bookCtrl.dispose();
    _pageCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _createJob() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final repo = OcrJobsRepository();
      await repo.createJob(
        type: _type,
        bookNumber: _bookCtrl.text.trim(),
        pageNumber: _pageCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('OCR job created successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      _bookCtrl.clear();
      _pageCtrl.clear();
      _notesCtrl.clear();
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
                  'OCR Document Upload',
                  style: GoogleFonts.poppins(
                    fontSize: isMobile ? 20 : 24,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Scan and digitize parish register pages',
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

            // Book Number
            TextField(
              controller: _bookCtrl,
              decoration: InputDecoration(
                labelText: 'Book Number',
                hintText: 'Enter register book number',
                prefixIcon: Icon(Icons.menu_book, color: colorScheme.primary),
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

            // Page Number
            TextField(
              controller: _pageCtrl,
              decoration: InputDecoration(
                labelText: 'Page Number',
                hintText: 'Enter page number',
                prefixIcon: Icon(Icons.tag, color: colorScheme.primary),
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
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),

            // Notes
            TextField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                labelText: 'Notes',
                hintText: 'Additional information about this document',
                prefixIcon: Icon(Icons.notes, color: colorScheme.primary),
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
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // Upload Options
            _buildUploadSection(colorScheme, theme, isMobile),
            const SizedBox(height: 24),

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
          Row(
            children: [
              Expanded(
                child: _buildUploadButton(
                  icon: Icons.camera_alt_outlined,
                  label: 'Take Photo',
                  color: colorScheme.primary,
                  onTap: () {},
                ),
              ),
              SizedBox(width: isMobile ? 10 : 12),
              Expanded(
                child: _buildUploadButton(
                  icon: Icons.upload_file_outlined,
                  label: 'Upload File',
                  color: colorScheme.secondary,
                  onTap: () {},
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Supported formats: JPG, PNG, PDF (Max 10MB)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
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
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
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
  }
}
