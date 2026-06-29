/// Represents extracted data from a single sacrament certificate.
class CertificateData {
  final String id;
  final String childName;
  final String? fatherName;
  final String? motherName;
  final String? dateOfBirth;
  final String? placeOfBirth;
  final String sacramentType; // baptism, confirmation, marriage
  final String? sacramentDate;
  final String? minister;
  final String? sponsor;
  final String rawOcrText;
  final DateTime scannedAt;

  CertificateData({
    required this.id,
    required this.childName,
    this.fatherName,
    this.motherName,
    this.dateOfBirth,
    this.placeOfBirth,
    required this.sacramentType,
    this.sacramentDate,
    this.minister,
    this.sponsor,
    required this.rawOcrText,
    required this.scannedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'childName': childName,
    'fatherName': fatherName,
    'motherName': motherName,
    'dateOfBirth': dateOfBirth,
    'placeOfBirth': placeOfBirth,
    'sacramentType': sacramentType,
    'sacramentDate': sacramentDate,
    'minister': minister,
    'sponsor': sponsor,
    'rawOcrText': rawOcrText,
    'scannedAt': scannedAt.toIso8601String(),
  };

  factory CertificateData.fromMap(Map<String, dynamic> map) => CertificateData(
    id: map['id'] ?? '',
    childName: map['childName'] ?? '',
    fatherName: map['fatherName'],
    motherName: map['motherName'],
    dateOfBirth: map['dateOfBirth'],
    placeOfBirth: map['placeOfBirth'],
    sacramentType: map['sacramentType'] ?? '',
    sacramentDate: map['sacramentDate'],
    minister: map['minister'],
    sponsor: map['sponsor'],
    rawOcrText: map['rawOcrText'] ?? '',
    scannedAt: map['scannedAt'] is String
        ? DateTime.parse(map['scannedAt'])
        : DateTime.now(),
  );
}
