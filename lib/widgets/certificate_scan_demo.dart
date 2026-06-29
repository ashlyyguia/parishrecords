import 'dart:io';
import 'package:flutter/material.dart';

import '../models/certificate_data.dart';
import '../services/certificate_ocr_helper.dart';

/// Example widget showing certificate OCR field extraction.
///
/// This demonstrates how to:
/// 1. Scan a certificate image
/// 2. Extract fields automatically
/// 3. Display confidence score
/// 4. Show which fields need review
class CertificateScanDemo extends StatefulWidget {
  final File imageFile;
  final String sacramentType;

  const CertificateScanDemo({
    required this.imageFile,
    required this.sacramentType,
    super.key,
  });

  @override
  State<CertificateScanDemo> createState() => _CertificateScanDemoState();
}

class _CertificateScanDemoState extends State<CertificateScanDemo> {
  late Future<CertificateData> _scanFuture;

  @override
  void initState() {
    super.initState();
    _scanFuture = CertificateOcrHelper.scanCertificate(
      widget.imageFile,
      sacramentType: widget.sacramentType,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CertificateData>(
      future: _scanFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        }

        final cert = snapshot.data!;
        final confidence = CertificateOcrHelper.getConfidenceScore(cert);
        final needsReview = CertificateOcrHelper.getFieldsNeedingReview(cert);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Confidence indicator
              _buildConfidenceCard(context, confidence),
              const SizedBox(height: 16),

              // Extracted fields
              _buildFieldsCard(context, cert),
              const SizedBox(height: 16),

              // Fields needing review
              if (needsReview.isNotEmpty) ...[
                _buildReviewCard(context, needsReview),
                const SizedBox(height: 16),
              ],

              // Actions
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, cert),
                      child: const Text('Accept & Continue'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Edit Manually'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConfidenceCard(BuildContext context, double confidence) {
    final theme = Theme.of(context);
    final color = confidence > 0.7
        ? Colors.green
        : confidence > 0.4
            ? Colors.orange
            : Colors.red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: color),
                const SizedBox(width: 8),
                Text(
                  'Extraction Confidence',
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  '${(confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: confidence,
                minHeight: 8,
                backgroundColor: color.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldsCard(BuildContext context, CertificateData cert) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Extracted Fields',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            _buildFieldRow('Child Name', cert.childName),
            _buildFieldRow('Father', cert.fatherName),
            _buildFieldRow('Mother', cert.motherName),
            _buildFieldRow('Date of Birth', cert.dateOfBirth),
            _buildFieldRow('Place of Birth', cert.placeOfBirth),
            _buildFieldRow(
              'Sacrament Date',
              cert.sacramentDate,
              suffix: '(${cert.sacramentType})',
            ),
            _buildFieldRow('Minister', cert.minister),
            _buildFieldRow('Sponsor', cert.sponsor),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldRow(
    String label,
    String? value, {
    String? suffix,
  }) {
    final isEmpty = value == null || value.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '—',
              style: TextStyle(
                color: isEmpty ? Colors.grey : Colors.black,
                fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          if (suffix != null) ...[
            const SizedBox(width: 8),
            Text(
              suffix,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewCard(BuildContext context, List<String> needsReview) {
    final theme = Theme.of(context);
    return Card(
      color: Colors.orange.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_rounded,
                  color: Colors.orange[700],
                ),
                const SizedBox(width: 8),
                Text(
                  'Please Review',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.orange[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...needsReview.map(
              (field) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Text('• '),
                    Text(field),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
