import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Represents identified fields from a certificate.
class CertificateFields {
  final String? childName;
  final String? childDateOfBirth;
  final String? placeOfBirth;
  final String? fatherName;
  final String? motherName;
  final String? sacramentDate;
  final String? sacramentType; // baptism, confirmation, etc.
  final String? minister;
  final String? sponsor;
  final Map<String, dynamic> rawData; // unmatched text for review

  CertificateFields({
    this.childName,
    this.childDateOfBirth,
    this.placeOfBirth,
    this.fatherName,
    this.motherName,
    this.sacramentDate,
    this.sacramentType,
    this.minister,
    this.sponsor,
    this.rawData = const {},
  });

  @override
  String toString() => 'CertificateFields('
      'name: $childName, dob: $childDateOfBirth, place: $placeOfBirth, '
      'father: $fatherName, mother: $motherName, '
      'sacrament: $sacramentType on $sacramentDate, '
      'minister: $minister, sponsor: $sponsor)';
}

/// Extracts structured fields from certificate OCR text.
class CertificateFieldExtractor {
  // Field anchors (labels that precede the data)
  static final _childNamePattern = RegExp(
    r'That\s+([A-Z][A-Za-z\s\.]+?)(?=\s+Child\s+of|$)',
    caseSensitive: false,
  );

  static final _parentPattern = RegExp(
    r'Child\s+of\s+([A-Z][A-Za-z\s\.]+?)\s+and\s+([A-Z][A-Za-z\s\.]+?)(?=\s+born|$)',
    caseSensitive: false,
    dotAll: true,
  );

  static final _fatherPattern = RegExp(
    r'Father:?\s+([A-Z][A-Za-z\s\.]+?)(?=\s+Mother|$)',
    caseSensitive: false,
  );

  static final _motherPattern = RegExp(
    r'Mother:?\s+([A-Z][A-Za-z\s\.]+?)(?=\s+born|$)',
    caseSensitive: false,
  );

  static final _birthPlacePattern = RegExp(
    r'born\s+in\s+([A-Z][A-Za-z\s\.,]+?)(?=\s+on\s+the|,|$)',
    caseSensitive: false,
  );

  static final _birthDatePattern = RegExp(
    r'on\s+the\s+(\d{1,2}(?:st|nd|rd|th)?)\s+day\s+of\s+'
    r'(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})',
    caseSensitive: false,
  );

  static final _sacramentDatePattern = RegExp(
    r'Was\s+(?:Baptized|Confirmed|Married)\s+on\s+the\s+'
    r'(\d{1,2}(?:st|nd|rd|th)?)\s+day\s+of\s+'
    r'(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{4})',
    caseSensitive: false,
  );

  static final _sacramentTypePattern = RegExp(
    r'Was\s+(Baptized|Confirmed|Married)',
    caseSensitive: false,
  );

  static final _ministerPattern = RegExp(
    r'(?:by\s+)?(?:the\s+)?(?:Rev\.?\s*)?(?:Fr\.?\s+)?([A-Z][A-Za-z\.\s]+?)(?=\s+The\s+Sponsor|\s*$)',
    caseSensitive: false,
  );

  static final _sponsorPattern = RegExp(
    r'The\s+Sponsor\(s\)?\s+being\s+([A-Z][A-Za-z\s\.,/]+?)(?=\s+as\s+appears|$)',
    caseSensitive: false,
  );

  static final _datePattern = RegExp(
    r'(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})',
  );

  /// Extract fields from raw OCR text.
  static CertificateFields extractFromText(String ocrText) {
    if (ocrText.trim().isEmpty) {
      return CertificateFields();
    }

    final normalized = _normalizeText(ocrText);
    String? childName;
    String? fatherName;
    String? motherName;
    String? placeOfBirth;
    String? birthDate;
    String? sacramentDate;
    String? sacramentType;
    String? minister;
    String? sponsor;

    // Extract child name
    final nameMatch = _childNamePattern.firstMatch(normalized);
    if (nameMatch != null) {
      childName = _cleanField(nameMatch.group(1) ?? '');
    }

    // Extract parents (preferred method: "Child of X and Y")
    final parentMatch = _parentPattern.firstMatch(normalized);
    if (parentMatch != null) {
      fatherName = _cleanField(parentMatch.group(1) ?? '');
      motherName = _cleanField(parentMatch.group(2) ?? '');
    } else {
      // Fallback: separate Father/Mother labels
      final fatherMatch = _fatherPattern.firstMatch(normalized);
      if (fatherMatch != null) {
        fatherName = _cleanField(fatherMatch.group(1) ?? '');
      }
      final motherMatch = _motherPattern.firstMatch(normalized);
      if (motherMatch != null) {
        motherName = _cleanField(motherMatch.group(1) ?? '');
      }
    }

    // Extract birthplace
    final placeMatch = _birthPlacePattern.firstMatch(normalized);
    if (placeMatch != null) {
      placeOfBirth = _cleanField(placeMatch.group(1) ?? '');
    }

    // Extract birth date
    final birthDateMatch = _birthDatePattern.firstMatch(normalized);
    if (birthDateMatch != null) {
      birthDate = _formatDate(
        birthDateMatch.group(1),
        birthDateMatch.group(2),
        birthDateMatch.group(3),
      );
    }

    // Extract sacrament type
    final sacrTypeMatch = _sacramentTypePattern.firstMatch(normalized);
    if (sacrTypeMatch != null) {
      sacramentType = sacrTypeMatch.group(1)?.toLowerCase();
    }

    // Extract sacrament date (most important: the actual event date)
    final sacrDateMatch = _sacramentDatePattern.firstMatch(normalized);
    if (sacrDateMatch != null) {
      sacramentDate = _formatDate(
        sacrDateMatch.group(1),
        sacrDateMatch.group(2),
        sacrDateMatch.group(3),
      );
    }

    // Extract minister (priest/friar name)
    final ministerMatch = _ministerPattern.firstMatch(normalized);
    if (ministerMatch != null) {
      minister = _cleanField(ministerMatch.group(1) ?? '');
    }

    // Extract sponsor
    final sponsorMatch = _sponsorPattern.firstMatch(normalized);
    if (sponsorMatch != null) {
      sponsor = _cleanField(sponsorMatch.group(1) ?? '');
    }

    return CertificateFields(
      childName: childName,
      childDateOfBirth: birthDate,
      placeOfBirth: placeOfBirth,
      fatherName: fatherName,
      motherName: motherName,
      sacramentDate: sacramentDate,
      sacramentType: sacramentType,
      minister: minister,
      sponsor: sponsor,
      rawData: {
        'originalText': ocrText,
        'normalizedText': normalized,
      },
    );
  }

  /// Extract fields from ML Kit recognition result (with bounding boxes).
  static CertificateFields extractFromRecognizedText(RecognizedText recognized) {
    // Use bounding box positions to improve field extraction
    final textWithPositions = <String>[];
    for (final block in recognized.blocks) {
      textWithPositions.add(_extractBlockText(block));
    }
    final fullText = textWithPositions.join('\n');
    return extractFromText(fullText);
  }

  /// Group blocks into logical sections (header, body, footer).
  static String _extractBlockText(TextBlock block) {
    return block.lines.map((line) => line.text).join(' ');
  }

  /// Normalize text: remove extra whitespace, normalize dates.
  static String _normalizeText(String raw) {
    var text = raw
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'([a-z])([A-Z])'), r'$1 $2'); // Camel case → spaces

    // Fix common OCR errors
    text = text
        .replaceAll('|', 'I') // Pipe → I
        .replaceAll('O0', 'OO') // O-zero
        .replaceAll('l1', 'll'); // l-one

    return text.trim();
  }

  /// Clean extracted field values.
  static String _cleanField(String raw) {
    var s = raw
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^\w\s\.\-/]'), ''); // Remove non-alphanumeric
    return s.trim();
  }

  /// Format date from parts: (day, month_name, year) → "DD/MM/YYYY".
  static String _formatDate(String? day, String? month, String? year) {
    if (day == null || month == null || year == null) return '';

    const months = {
      'january': '01', 'february': '02', 'march': '03', 'april': '04',
      'may': '05', 'june': '06', 'july': '07', 'august': '08',
      'september': '09', 'october': '10', 'november': '11', 'december': '12',
    };

    final monthNum = months[month.toLowerCase()] ?? '';
    final dayNum = day.replaceAll(RegExp(r'[^\d]'), '').padLeft(2, '0');
    final yearNum = year.padLeft(4, '0');

    return '$dayNum/$monthNum/$yearNum';
  }
}
