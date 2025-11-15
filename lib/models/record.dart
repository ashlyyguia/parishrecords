enum RecordType { baptism, marriage, funeral, confirmation }

extension RecordTypeExtension on RecordType {
  String get value {
    switch (this) {
      case RecordType.baptism:
        return 'baptism';
      case RecordType.marriage:
        return 'marriage';
      case RecordType.funeral:
        return 'funeral';
      case RecordType.confirmation:
        return 'confirmation';
    }
  }

  static RecordType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'baptism':
        return RecordType.baptism;
      case 'marriage':
        return RecordType.marriage;
      case 'funeral':
        return RecordType.funeral;
      case 'confirmation':
        return RecordType.confirmation;
      default:
        return RecordType.baptism;
    }
  }
}

enum CertificateStatus { pending, approved, rejected }

extension CertificateStatusExtension on CertificateStatus {
  String get value {
    switch (this) {
      case CertificateStatus.pending:
        return 'pending';
      case CertificateStatus.approved:
        return 'approved';
      case CertificateStatus.rejected:
        return 'rejected';
    }
  }

  static CertificateStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'approved':
        return CertificateStatus.approved;
      case 'rejected':
        return CertificateStatus.rejected;
      default:
        return CertificateStatus.pending;
    }
  }
}

class ParishRecord {
  final String id;
  final RecordType type;
  final String name;
  final DateTime date;
  final String? imagePath;
  final String? parish;
  final String? notes;
  final CertificateStatus certificateStatus;

  ParishRecord({
    required this.id,
    required this.type,
    required this.name,
    required this.date,
    this.imagePath,
    this.parish,
    this.notes,
    this.certificateStatus = CertificateStatus.pending,
  });
}
