import '../models/record.dart';

/// A single field a certificate must (or may) provide for a record type.
class CertField {
  final String key;
  final String label;
  final bool required;
  final String? hint;

  const CertField(
    this.key,
    this.label, {
    this.required = true,
    this.hint,
  });
}

/// Field requirements per record type, in display order.
///
/// Keys double as the map keys of [CertificateExtraction.values].
List<CertField> certificateFieldsFor(RecordType type) {
  const registry = [
    CertField('dated', 'Dated (issue date)', required: false),
    CertField('page', 'Page No.', required: false),
    CertField('vol', 'Vol. No.', required: false),
    CertField('series', 'Series', required: false),
  ];

  switch (type) {
    case RecordType.baptism:
      return const [
        CertField('fullName', 'Full name of child'),
        CertField('fatherName', 'Father\'s name'),
        CertField('motherName', 'Mother\'s name'),
        CertField('birthPlace', 'Place of birth'),
        CertField('birthDate', 'Date of birth'),
        CertField('sacramentDate', 'Date of baptism'),
        CertField('minister', 'Minister (Rev. Fr.)'),
        CertField('sponsors', 'Sponsor(s)'),
        ...registry,
      ];
    case RecordType.confirmation:
      return const [
        CertField('fullName', 'Full name'),
        CertField('fatherName', 'Father\'s name'),
        CertField('motherName', 'Mother\'s name'),
        CertField('birthPlace', 'Place of birth'),
        CertField('birthDate', 'Date of birth'),
        CertField('sacramentDate', 'Date of confirmation'),
        CertField('minister', 'Minister (Rev. Fr.)'),
        CertField('sponsors', 'Sponsor(s)'),
        ...registry,
      ];
    case RecordType.marriage:
      return const [
        CertField('groomName', 'Groom\'s name'),
        CertField('brideName', 'Bride\'s name'),
        CertField('sacramentDate', 'Date of marriage'),
        CertField('marriagePlace', 'Place of marriage', required: false),
        CertField('minister', 'Officiating priest'),
        CertField('witnesses', 'Witnesses / sponsors'),
        ...registry,
      ];
    case RecordType.funeral:
      return const [
        CertField('deceasedName', 'Name of deceased'),
        CertField('deathDate', 'Date of death'),
        CertField('burialDate', 'Date of burial'),
        CertField('burialPlace', 'Place of burial'),
        CertField('minister', 'Officiating priest'),
        ...registry,
      ];
  }
}

/// Result of extracting certificate fields from OCR text.
class CertificateExtraction {
  final RecordType type;
  final Map<String, String> values;
  final String rawText;

  const CertificateExtraction({
    required this.type,
    required this.values,
    required this.rawText,
  });

  List<CertField> get missingRequired => certificateFieldsFor(type)
      .where((f) => f.required && (values[f.key] ?? '').trim().isEmpty)
      .toList();

  int get detectedRequiredCount => certificateFieldsFor(type)
      .where((f) => f.required && (values[f.key] ?? '').trim().isNotEmpty)
      .length;

  int get totalRequiredCount =>
      certificateFieldsFor(type).where((f) => f.required).length;
}

/// Extracts fields from parish certificate OCR text based on record type.
///
/// Tuned to the Holy Rosary Parish certificate layout:
///   That NAME / Child of FATHER / and MOTHER / born in PLACE /
///   on the D day of MONTH, YEAR / Was Baptized|Confirmed /
///   by the Rev. Fr. MINISTER / The Sponsor(s) being SPONSORS /
///   Dated: ... / Page: ... / Vol.: ... / Series: ...
class CertificateOcrExtractor {
  CertificateOcrExtractor._();

  static const _months =
      r'(?:January|February|March|April|May|June|July|August|September|October|November|December)';

  static CertificateExtraction extract(String ocrText, RecordType type) {
    final text = _normalize(ocrText);
    final lines = ocrText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final values = <String, String>{};

    switch (type) {
      case RecordType.baptism:
      case RecordType.confirmation:
        _extractBaptismConfirmation(text, lines, values);
        break;
      case RecordType.marriage:
        _extractMarriage(text, lines, values);
        break;
      case RecordType.funeral:
        _extractFuneral(text, lines, values);
        break;
    }

    _extractRegistry(text, values);

    return CertificateExtraction(type: type, values: values, rawText: ocrText);
  }

  static void _extractBaptismConfirmation(
    String text,
    List<String> lines,
    Map<String, String> values,
  ) {
    _put(
      values,
      'fullName',
      _firstGroup(
        RegExp(
          r'That[:\s]+([A-Z][A-Za-z\s.\-]+?)(?=\s+Child\s+of|\s*$)',
          caseSensitive: false,
        ),
        text,
      ) ??
          _valueNearLabel(lines, RegExp(r'^That\b', caseSensitive: false)),
    );

    _put(
      values,
      'fatherName',
      _firstGroup(
        RegExp(
          r'Child\s+of[:\s]+([A-Z][A-Za-z\s.\-]+?)(?=\s+and\b|\s*$)',
          caseSensitive: false,
        ),
        text,
      ) ??
          _valueNearLabel(
            lines,
            RegExp(r'^Child\s+of\b', caseSensitive: false),
          ),
    );

    _put(
      values,
      'motherName',
      _firstGroup(
        RegExp(
          r'\band[:\s]+([A-Z][A-Za-z\s.\-]+?)(?=\s+born\b|\s*$)',
          caseSensitive: false,
        ),
        text,
      ),
    );

    _put(
      values,
      'birthPlace',
      _firstGroup(
        RegExp(
          r'born\s+in[:\s]+([A-Z][A-Za-z\s.,\-]+?)(?=\s+on\s+the\b|\s*$)',
          caseSensitive: false,
        ),
        text,
      ) ??
          _valueNearLabel(
            lines,
            RegExp(r'^born\s+in\b', caseSensitive: false),
          ),
    );

    // Two "on the D day of MONTH, YEAR" clauses: first = birth,
    // the one after "Was Baptized/Confirmed" = sacrament date.
    final dayOf = RegExp(
      r'on\s+the\s+(\d{1,2})\s*(?:st|nd|rd|th)?\s+day\s+of\s+(' +
          _months +
          r')?[,\s]*(\d{4})',
      caseSensitive: false,
    );
    final dates = dayOf.allMatches(text).toList();
    final sacramentAnchor = RegExp(
      r'Was\s+(?:Baptized|Confirmed)',
      caseSensitive: false,
    ).firstMatch(text);

    for (final m in dates) {
      final formatted = _dayOfDate(m);
      if (formatted.isEmpty) continue;
      final isAfterAnchor =
          sacramentAnchor != null && m.start > sacramentAnchor.start;
      if (isAfterAnchor && !values.containsKey('sacramentDate')) {
        values['sacramentDate'] = formatted;
      } else if (!isAfterAnchor && !values.containsKey('birthDate')) {
        values['birthDate'] = formatted;
      }
    }
    // Fallback when the anchor was not read: two dates in order.
    if (dates.length >= 2 &&
        !values.containsKey('sacramentDate') &&
        values.containsKey('birthDate')) {
      values['sacramentDate'] = _dayOfDate(dates[1]);
    }

    _put(values, 'minister', _extractMinister(text, lines));

    _put(
      values,
      'sponsors',
      _firstGroup(
        RegExp(
          r'Sponsor\(?s?\)?\s+being[|:\s]+([A-Z][A-Za-z\s.,&\-]+?)(?=\s+as\s+appears|\s*$)',
          caseSensitive: false,
        ),
        text,
      ) ??
          _valueNearLabel(
            lines,
            RegExp(r'Sponsor\(?s?\)?\s+being', caseSensitive: false),
          ),
    );

    // If both landed on the same line, the minister match is the bad one.
    if (values['minister'] != null &&
        values['minister'] == values['sponsors']) {
      values.remove('minister');
    }
  }

  /// The minister may print inline ("by the Rev. Fr. LUKE LYNCH") or on the
  /// line above/below the label; a FR/REV prefix marks the right neighbour.
  static String? _extractMinister(String text, List<String> lines) {
    final labelStart = RegExp(r'^by\s+the\s+Rev', caseSensitive: false);
    final labelFull = RegExp(
      r'^by\s+the\s+Rev\.?\s*Fr\.?[.:\s]*',
      caseSensitive: false,
    );
    final priestPrefix = RegExp(r'^(FR|REV|MSGR)\b', caseSensitive: false);

    for (var i = 0; i < lines.length; i++) {
      if (!labelStart.hasMatch(lines[i])) continue;
      final same = lines[i].replaceFirst(labelFull, '').trim();
      if (_looksLikeValue(same)) return same;
      final prev = i > 0 ? lines[i - 1] : '';
      final next = i + 1 < lines.length ? lines[i + 1] : '';
      if (priestPrefix.hasMatch(prev.trim()) && _looksLikeValue(prev)) {
        return prev;
      }
      if (priestPrefix.hasMatch(next.trim()) && _looksLikeValue(next)) {
        return next;
      }
      if (_looksLikeValue(next)) return next;
      if (_looksLikeValue(prev)) return prev;
    }

    return _firstGroup(
      RegExp(
        r'by\s+the\s+Rev\.?\s*Fr\.?[:\s]+([A-Z][A-Za-z\s.\-]+?)(?=\s+The\s+Sponsor|\s*$)',
        caseSensitive: false,
      ),
      text,
    );
  }

  static void _extractMarriage(
    String text,
    List<String> lines,
    Map<String, String> values,
  ) {
    final couple = RegExp(
      r'That[:\s]+([A-Z][A-Za-z\s.\-]+?)\s+and\s+([A-Z][A-Za-z\s.\-]+?)(?=\s+were\b|\s+of\b|\s*$)',
      caseSensitive: false,
    ).firstMatch(text);
    if (couple != null) {
      _put(values, 'groomName', couple.group(1));
      _put(values, 'brideName', couple.group(2));
    } else {
      _put(
        values,
        'groomName',
        _valueNearLabel(lines, RegExp(r'^Groom\b', caseSensitive: false)),
      );
      _put(
        values,
        'brideName',
        _valueNearLabel(lines, RegExp(r'^Bride\b', caseSensitive: false)),
      );
    }

    final dayOf = RegExp(
      r'on\s+the\s+(\d{1,2})\s*(?:st|nd|rd|th)?\s+day\s+of\s+(' +
          _months +
          r')?[,\s]*(\d{4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (dayOf != null) _put(values, 'sacramentDate', _dayOfDate(dayOf));

    _put(
      values,
      'marriagePlace',
      _firstGroup(
        RegExp(
          r'(?:married|solemnized)\s+(?:at|in)[:\s]+([A-Z][A-Za-z\s.,\-]+?)(?=\s+on\b|\s*$)',
          caseSensitive: false,
        ),
        text,
      ),
    );

    _put(
      values,
      'minister',
      _firstGroup(
        RegExp(
          r'by\s+the\s+Rev\.?\s*Fr\.?[:\s]+([A-Z][A-Za-z\s.\-]+?)(?=\s+The\s+|witness|\s*$)',
          caseSensitive: false,
        ),
        text,
      ) ??
          _valueNearLabel(
            lines,
            RegExp(r'^by\s+the\s+Rev', caseSensitive: false),
          ),
    );

    _put(
      values,
      'witnesses',
      _firstGroup(
        RegExp(
          r'(?:witness(?:es)?|sponsor\(?s?\)?)\s+being[|:\s]+([A-Z][A-Za-z\s.,&\-]+?)(?=\s+as\s+appears|\s*$)',
          caseSensitive: false,
        ),
        text,
      ) ??
          _valueNearLabel(
            lines,
            RegExp(r'witness(?:es)?\s+being', caseSensitive: false),
          ),
    );
  }

  static void _extractFuneral(
    String text,
    List<String> lines,
    Map<String, String> values,
  ) {
    _put(
      values,
      'deceasedName',
      _firstGroup(
        RegExp(
          r'That[:\s]+([A-Z][A-Za-z\s.\-]+?)(?=\s+died\b|\s+of\b|\s*$)',
          caseSensitive: false,
        ),
        text,
      ) ??
          _valueNearLabel(lines, RegExp(r'^That\b', caseSensitive: false)),
    );

    _put(
      values,
      'deathDate',
      _firstGroup(
        RegExp(
          r'died\s+on(?:\s+the)?[:\s]+(\d{1,2}\s*(?:st|nd|rd|th)?\s+(?:day\s+of\s+)?' +
              _months +
              r'[,\s]*\d{4})',
          caseSensitive: false,
        ),
        text,
      ),
    );

    _put(
      values,
      'burialDate',
      _firstGroup(
        RegExp(
          r'(?:buried|interred)\s+on(?:\s+the)?[:\s]+(\d{1,2}\s*(?:st|nd|rd|th)?\s+(?:day\s+of\s+)?' +
              _months +
              r'[,\s]*\d{4})',
          caseSensitive: false,
        ),
        text,
      ),
    );

    _put(
      values,
      'burialPlace',
      _firstGroup(
        RegExp(
          r'(?:buried|interred)\s+(?:at|in)[:\s]+([A-Z][A-Za-z\s.,\-]+?)(?=\s+on\b|\s*$)',
          caseSensitive: false,
        ),
        text,
      ),
    );

    _put(
      values,
      'minister',
      _firstGroup(
        RegExp(
          r'by\s+the\s+Rev\.?\s*Fr\.?[:\s]+([A-Z][A-Za-z\s.\-]+?)(?=\s+as\s+appears|\s*$)',
          caseSensitive: false,
        ),
        text,
      ) ??
          _valueNearLabel(
            lines,
            RegExp(r'^by\s+the\s+Rev', caseSensitive: false),
          ),
    );
  }

  /// Registry footer shared by all certificate types.
  static void _extractRegistry(String text, Map<String, String> values) {
    _put(
      values,
      'dated',
      _firstGroup(
        RegExp(
          r'Dated\s*[:\s]\s*(' + _months + r'\s+\d{1,2},?\s+\d{4})',
          caseSensitive: false,
        ),
        text,
      ),
    );
    _put(
      values,
      'page',
      _firstGroup(
        RegExp(r'Page\s*[:\s]\s*([A-Za-z0-9\-]+)', caseSensitive: false),
        text,
      ),
    );
    _put(
      values,
      'vol',
      _firstGroup(
        RegExp(r'Vol\.?\s*[:\s]\s*([A-Za-z0-9\-]+)', caseSensitive: false),
        text,
      ),
    );
    _put(
      values,
      'series',
      _firstGroup(
        RegExp(
          r'Series\s*[:\s]\s*([0-9]{4}\s*-\s*[0-9]{4}|[A-Za-z0-9\-]+)',
          caseSensitive: false,
        ),
        text,
      ),
    );
  }

  /// Parses dates the extractor produces ("30 April 1958") and the
  /// certificate footer style ("January 8, 2026"). Returns null when the
  /// month is unreadable (e.g. "30 ??? 1958").
  static DateTime? parseCertDate(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;

    const months = {
      'january': 1, 'february': 2, 'march': 3, 'april': 4,
      'may': 5, 'june': 6, 'july': 7, 'august': 8,
      'september': 9, 'october': 10, 'november': 11, 'december': 12,
    };

    // "30 April 1958"
    var m = RegExp(
      r'^(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})$',
    ).firstMatch(s);
    if (m != null) {
      final month = months[m.group(2)!.toLowerCase()];
      if (month == null) return null;
      return DateTime(int.parse(m.group(3)!), month, int.parse(m.group(1)!));
    }

    // "January 8, 2026"
    m = RegExp(
      r'^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})$',
    ).firstMatch(s);
    if (m != null) {
      final month = months[m.group(1)!.toLowerCase()];
      if (month == null) return null;
      return DateTime(int.parse(m.group(3)!), month, int.parse(m.group(2)!));
    }

    return DateTime.tryParse(s);
  }

  // ---- helpers ----

  static void _put(Map<String, String> values, String key, String? raw) {
    final v = _clean(raw);
    if (v.isNotEmpty && !values.containsKey(key)) values[key] = v;
  }

  static String? _firstGroup(RegExp re, String text) =>
      re.firstMatch(text)?.group(1);

  /// ML Kit often puts a value on the line before/after its label.
  /// Returns text after the label on the same line, else the nearest
  /// neighbouring line that looks like a value (mostly uppercase words).
  static String? _valueNearLabel(List<String> lines, RegExp label) {
    for (var i = 0; i < lines.length; i++) {
      if (!label.hasMatch(lines[i])) continue;
      final same = lines[i].replaceFirst(label, '').trim();
      if (_looksLikeValue(same)) return same;
      if (i + 1 < lines.length && _looksLikeValue(lines[i + 1])) {
        return lines[i + 1];
      }
      if (i > 0 && _looksLikeValue(lines[i - 1])) return lines[i - 1];
    }
    return null;
  }

  static bool _looksLikeValue(String s) {
    final t = s.trim();
    if (t.length < 3) return false;
    // Reject other labels of the certificate body.
    if (RegExp(
      r'^(That|Child of|and\b|born in|on the|day of|Was |According|by the|The Sponsor|as appears|Dated|Page|Vol|Series|Rev\.?$|Parish|This is)',
      caseSensitive: false,
    ).hasMatch(t)) {
      return false;
    }
    final letters = t.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.isEmpty) return false;
    final upper = letters.replaceAll(RegExp(r'[^A-Z]'), '');
    return upper.length / letters.length >= 0.6;
  }

  static String _dayOfDate(RegExpMatch m) {
    final day = m.group(1);
    final month = m.group(2);
    final year = m.group(3);
    if (day == null || year == null) return '';
    if (month == null || month.isEmpty) return '$day ??? $year';
    return '$day ${_titleCase(month)} $year';
  }

  static String _titleCase(String s) => s.isEmpty
      ? s
      : s[0].toUpperCase() + s.substring(1).toLowerCase();

  static String _normalize(String raw) => raw
      .replaceAll('|', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('on.the', 'on the')
      .replaceAll(RegExp(r'\bihe\b'), 'the')
      .trim();

  static String _clean(String? raw) {
    if (raw == null) return '';
    return raw
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[|:,\-\s]+|[|:,\-\s]+$'), '')
        .trim();
  }
}
