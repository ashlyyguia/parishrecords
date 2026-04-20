class ScannedDocument {
  final String id;
  final String imagePath;
  final String extractedText;
  final String? editedText;
  final DateTime scannedAt;
  final DateTime? savedAt;
  final String? recordId;
  final Map<String, String> extractedFields;
  final bool isHistorical;

  ScannedDocument({
    required this.id,
    required this.imagePath,
    required this.extractedText,
    this.editedText,
    required this.scannedAt,
    this.savedAt,
    this.recordId,
    Map<String, String>? extractedFields,
    this.isHistorical = false,
  }) : extractedFields = extractedFields ?? {};

  String get displayText => editedText ?? extractedText;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'imagePath': imagePath,
      'extractedText': extractedText,
      'editedText': editedText,
      'scannedAt': scannedAt.toIso8601String(),
      'savedAt': savedAt?.toIso8601String(),
      'recordId': recordId,
      'extractedFields': extractedFields,
      'isHistorical': isHistorical,
    };
  }

  factory ScannedDocument.fromMap(Map<String, dynamic> map) {
    return ScannedDocument(
      id: map['id'] as String,
      imagePath: map['imagePath'] as String,
      extractedText: map['extractedText'] as String,
      editedText: map['editedText'] as String?,
      scannedAt: DateTime.parse(map['scannedAt'] as String),
      savedAt: map['savedAt'] != null
          ? DateTime.parse(map['savedAt'] as String)
          : null,
      recordId: map['recordId'] as String?,
      extractedFields: Map<String, String>.from(
        map['extractedFields'] as Map? ?? {},
      ),
      isHistorical: map['isHistorical'] as bool? ?? false,
    );
  }

  ScannedDocument copyWith({
    String? id,
    String? imagePath,
    String? extractedText,
    String? editedText,
    DateTime? scannedAt,
    DateTime? savedAt,
    String? recordId,
    Map<String, String>? extractedFields,
    bool? isHistorical,
  }) {
    return ScannedDocument(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      extractedText: extractedText ?? this.extractedText,
      editedText: editedText ?? this.editedText,
      scannedAt: scannedAt ?? this.scannedAt,
      savedAt: savedAt ?? this.savedAt,
      recordId: recordId ?? this.recordId,
      extractedFields: extractedFields ?? this.extractedFields,
      isHistorical: isHistorical ?? this.isHistorical,
    );
  }
}

