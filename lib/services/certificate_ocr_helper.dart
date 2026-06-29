import 'dart:io';
import 'package:uuid/uuid.dart';

import '../models/certificate_data.dart';
import 'certificate_field_extractor.dart';
import 'ocr_service.dart';

/// Helper for certificate-specific OCR workflows.
class CertificateOcrHelper {
  static const _uuid = Uuid();

  /// Scan a certificate image and extract structured fields.
  static Future<CertificateData> scanCertificate(
    File imageFile, {
    required String sacramentType,
  }) async {
    final ocrService = OcrService.instance;

    // Run OCR
    final ocrResult = await ocrService.recognizeText(
      imageFile,
      mode: OcrMode.printed,
    );

    // Extract fields from OCR text
    final fields = CertificateFieldExtractor.extractFromText(ocrResult.text);

    // Build certificate data
    return CertificateData(
      id: _uuid.v4(),
      childName: fields.childName ?? '',
      fatherName: fields.fatherName,
      motherName: fields.motherName,
      dateOfBirth: fields.childDateOfBirth,
      placeOfBirth: fields.placeOfBirth,
      sacramentType: sacramentType,
      sacramentDate: fields.sacramentDate,
      minister: fields.minister,
      sponsor: fields.sponsor,
      rawOcrText: ocrResult.text,
      scannedAt: DateTime.now(),
    );
  }

  /// Confidence score for extracted data (0.0 - 1.0).
  /// Higher = more fields found.
  static double getConfidenceScore(CertificateData cert) {
    var score = 0.0;
    const maxFields = 9;

    if (cert.childName.isNotEmpty) score += 1;
    if (cert.fatherName != null && cert.fatherName!.isNotEmpty) score += 1;
    if (cert.motherName != null && cert.motherName!.isNotEmpty) score += 1;
    if (cert.dateOfBirth != null && cert.dateOfBirth!.isNotEmpty) score += 1;
    if (cert.placeOfBirth != null && cert.placeOfBirth!.isNotEmpty) score += 1;
    if (cert.sacramentDate != null && cert.sacramentDate!.isNotEmpty) score += 1;
    if (cert.minister != null && cert.minister!.isNotEmpty) score += 1;
    if (cert.sponsor != null && cert.sponsor!.isNotEmpty) score += 1;

    return score / maxFields;
  }

  /// Which fields need manual review (empty/suspicious).
  static List<String> getFieldsNeedingReview(CertificateData cert) {
    final needsReview = <String>[];

    if (cert.childName.isEmpty) needsReview.add('Child Name');
    if (cert.fatherName == null || cert.fatherName!.isEmpty) {
      needsReview.add('Father Name');
    }
    if (cert.motherName == null || cert.motherName!.isEmpty) {
      needsReview.add('Mother Name');
    }
    if (cert.dateOfBirth == null || cert.dateOfBirth!.isEmpty) {
      needsReview.add('Date of Birth');
    }
    if (cert.placeOfBirth == null || cert.placeOfBirth!.isEmpty) {
      needsReview.add('Place of Birth');
    }
    if (cert.sacramentDate == null || cert.sacramentDate!.isEmpty) {
      needsReview.add('Sacrament Date');
    }

    return needsReview;
  }
}
