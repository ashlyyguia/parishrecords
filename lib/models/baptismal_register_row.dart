/// Ordered field keys captured for a baptismal register row, matching the
/// register columns the parish tracks: No. (lineNo, handled separately) then
/// these left-to-right.
///
/// The physical book also has an "L or ILL" (legitimacy) column and an
/// "Observations" column; they are intentionally NOT captured here — the
/// backend still parses them, but they are not shown in the OCR review or
/// saved. `toBaptismalOcrNotesMap` still writes them (as empty) so the notes
/// schema stays backward-compatible.
const List<String> baptismalFieldKeys = [
  'nameOfChild',
  'placeAndBirthDate',
  'parents',
  'residentsOf',
  'dateOfBaptism',
  'minister',
  'sponsors',
];

const Map<String, String> baptismalFieldLabels = {
  'nameOfChild': 'Name of Child',
  'placeAndBirthDate': 'Place & Date of Birth',
  'legitimacy': 'L or ILL',
  'parents': 'Parents (Mother\'s Maiden Name)',
  'residentsOf': 'Residents Of',
  'dateOfBaptism': 'Date of Baptism',
  'minister': 'Minister',
  'sponsors': 'Sponsors',
  'observations': 'Observations',
};

/// Fields the register always fills in and that the app requires to save.
const Set<String> baptismalRequiredFields = {'nameOfChild', 'dateOfBaptism'};

/// Below this, OCR output is shown as needing verification.
const double kOcrReviewThreshold = 0.60;

/// One extracted cell: the text, how sure OCR was, and whether it was carried
/// down from the row above rather than actually read.
class OcrField {
  OcrField({
    required this.value,
    required this.confidence,
    this.inherited = false,
    this.edited = false,
  });

  String value;
  final double confidence;
  final bool inherited;

  /// True once a human has confirmed or corrected this field via [setValue]
  /// (or a [copyWith] that supplies a new value). Client-side only: never
  /// sent to the backend, never expected from [fromJson].
  final bool edited;

  /// True when a human should look at this before it is saved.
  ///
  /// An edited field is never flagged: a human has already looked at it,
  /// which is the whole point of the review step. Otherwise, an empty field
  /// is never flagged (empty-and-required is a validation concern, handled
  /// separately); non-empty fields are flagged when inherited or low
  /// confidence.
  bool get needsReview {
    if (edited) return false;
    if (value.trim().isEmpty) return false;
    return inherited || confidence < kOcrReviewThreshold;
  }

  factory OcrField.fromJson(Map<String, dynamic>? json) {
    if (json == null) return OcrField(value: '', confidence: 0);
    final rawConfidence = json['confidence'];
    return OcrField(
      value: json['value']?.toString() ?? '',
      confidence: rawConfidence is num ? rawConfidence.toDouble() : 0,
      inherited: json['inherited'] == true,
    );
  }

  /// Returns a copy of this field. Supplying [value] marks the result as
  /// [edited] — a human has reviewed/confirmed the value, even if it is
  /// unchanged from the original.
  OcrField copyWith({String? value}) => OcrField(
    value: value ?? this.value,
    confidence: confidence,
    inherited: inherited,
    edited: value != null ? true : edited,
  );
}

/// One row of the register — one prospective baptism record.
class BaptismalRegisterRow {
  BaptismalRegisterRow({
    required this.lineNo,
    required this.fields,
    this.selected = true,
  });

  String lineNo;
  final Map<String, OcrField> fields;
  bool selected;

  OcrField field(String key) => fields[key] ?? OcrField(value: '', confidence: 0);

  void setValue(String key, String value) {
    fields[key] = field(key).copyWith(value: value);
  }

  factory BaptismalRegisterRow.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'];
    final map = <String, OcrField>{};
    for (final key in baptismalFieldKeys) {
      final raw = rawFields is Map ? rawFields[key] : null;
      map[key] = OcrField.fromJson(
        raw is Map ? Map<String, dynamic>.from(raw) : null,
      );
    }
    return BaptismalRegisterRow(
      lineNo: json['lineNo']?.toString() ?? '',
      fields: map,
    );
  }
}

/// A whole scanned spread.
class BaptismalOcrScan {
  BaptismalOcrScan({
    required this.scanId,
    required this.rows,
    required this.rotation,
    required this.warnings,
  });

  final String scanId;
  final List<BaptismalRegisterRow> rows;
  final int rotation;
  final List<String> warnings;

  factory BaptismalOcrScan.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'];
    final rawRotation = json['rotation'];
    final rawWarnings = json['warnings'];
    return BaptismalOcrScan(
      scanId: json['scanId']?.toString() ?? '',
      rotation: rawRotation is num ? rawRotation.toInt() : 0,
      warnings: rawWarnings is List
          ? rawWarnings.map((w) => w.toString()).toList()
          : const [],
      rows: rawRows is List
          ? rawRows
              .whereType<Map>()
              .map((r) => BaptismalRegisterRow.fromJson(Map<String, dynamic>.from(r)))
              .toList()
          : <BaptismalRegisterRow>[],
    );
  }
}
