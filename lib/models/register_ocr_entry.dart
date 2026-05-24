import 'record.dart';

/// One parsed row from a parish baptism register OCR scan.
class RegisterOcrEntry {
  RegisterOcrEntry({
    required this.id,
    required this.name,
    this.lineNo,
    this.placeAndBirthDate = '',
    this.parents = '',
    this.residentsOf = '',
    this.baptismDateText = '',
    this.minister = '',
    this.sponsors = '',
    this.date,
    required this.rawLine,
    this.selected = true,
  });

  final String id;
  String name;
  String? lineNo;
  String placeAndBirthDate;
  String parents;
  String residentsOf;
  String baptismDateText;
  String minister;
  String sponsors;
  DateTime? date;
  final String rawLine;
  bool selected;

  bool get isValid =>
      name.trim().length >= 2 &&
      (date != null || baptismDateText.trim().isNotEmpty);

  RegisterOcrEntry copyWith({String? id}) {
    return RegisterOcrEntry(
      id: id ?? this.id,
      name: name,
      lineNo: lineNo,
      placeAndBirthDate: placeAndBirthDate,
      parents: parents,
      residentsOf: residentsOf,
      baptismDateText: baptismDateText,
      minister: minister,
      sponsors: sponsors,
      date: date,
      rawLine: rawLine,
      selected: selected,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'line_no': lineNo,
        'name': name,
        'place_and_birth_date': placeAndBirthDate,
        'parents': parents,
        'residents_of': residentsOf,
        'baptism_date_text': baptismDateText,
        'minister': minister,
        'sponsors': sponsors,
        if (date != null) 'date': date!.toIso8601String(),
        'raw_line': rawLine,
        'selected': selected,
      };

  static RegisterOcrEntry fromMap(Map<String, dynamic> m) {
    DateTime? parsedDate;
    final dateVal = m['date'];
    if (dateVal is String && dateVal.isNotEmpty) {
      parsedDate = DateTime.tryParse(dateVal);
    }

    return RegisterOcrEntry(
      id: m['id']?.toString() ?? '',
      lineNo: m['line_no']?.toString(),
      name: m['name']?.toString() ?? '',
      placeAndBirthDate: m['place_and_birth_date']?.toString() ?? '',
      parents: m['parents']?.toString() ?? '',
      residentsOf: m['residents_of']?.toString() ?? '',
      baptismDateText: m['baptism_date_text']?.toString() ?? '',
      minister: m['minister']?.toString() ?? '',
      sponsors: m['sponsors']?.toString() ?? '',
      date: parsedDate,
      rawLine: m['raw_line']?.toString() ?? '',
      selected: m['selected'] as bool? ?? true,
    );
  }

  static List<RegisterOcrEntry> listFromJobData(Map<String, dynamic> job) {
    final stored = job['parsed_entries'];
    if (stored is List && stored.isNotEmpty) {
      return stored
          .whereType<Map>()
          .map((e) => RegisterOcrEntry.fromMap(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty || e.name.isNotEmpty)
          .toList();
    }
    return const [];
  }
}

/// Draft passed to [RecordsRepository.addBatch].
class RegisterRecordDraft {
  const RegisterRecordDraft({
    required this.type,
    required this.name,
    required this.date,
    this.parish,
    this.notes,
    this.imagePath,
    /// `temporary` for manual register drafts; `official` is the default.
    this.recordStatus = 'official',
  });

  final RecordType type;
  final String name;
  final DateTime date;
  final String? parish;
  final String? notes;
  final String? imagePath;
  final String recordStatus;
}
