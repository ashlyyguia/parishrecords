class AuditLogEntry {
  final String id;
  final String action; // e.g., create_record, update_record, delete_record, login
  final String userId;
  final DateTime timestamp;
  final Map<String, dynamic>? meta;

  AuditLogEntry({
    required this.id,
    required this.action,
    required this.userId,
    required this.timestamp,
    this.meta,
  });
}
