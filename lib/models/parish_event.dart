import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a parish event that can be one-time or recurring.
class ParishEvent {
  final String id;
  final String title;
  final String description;
  final String? imageUrl;
  final String? imageStoragePath;
  final String location;
  final String eventType; // 'one-time' | 'recurring'
  
  // For one-time events
  final DateTime? eventDateTime;
  final DateTime? eventEndDateTime;
  
  // For recurring events
  final String? recurrencePattern; // e.g., 'weekly', 'monthly'
  final List<String>? recurrenceDays; // e.g., ['Monday', 'Wednesday']
  final String? recurrenceTime; // e.g., '6:00 AM'
  final String? recurrenceEndTime; // e.g., '7:30 PM'
  
  final String status; // 'active' | 'archived' | 'draft'
  final bool pinned;
  final String createdByUid;
  final DateTime createdAt;
  final DateTime updatedAt;

  ParishEvent({
    required this.id,
    required this.title,
    required this.description,
    this.imageUrl,
    this.imageStoragePath,
    required this.location,
    required this.eventType,
    this.eventDateTime,
    this.eventEndDateTime,
    this.recurrencePattern,
    this.recurrenceDays,
    this.recurrenceTime,
    this.recurrenceEndTime,
    required this.status,
    required this.pinned,
    required this.createdByUid,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ParishEvent.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final createdAt = _readTimestamp(data['createdAt']) ?? DateTime.now();
    final updatedAt = _readTimestamp(data['updatedAt']) ?? createdAt;
    final eventDateTime = _readTimestamp(data['eventDateTime']);
    final eventEndDateTime = _readTimestamp(data['eventEndDateTime']);

    return ParishEvent(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      imageUrl: data['imageUrl'] as String?,
      imageStoragePath: data['imageStoragePath'] as String?,
      location: (data['location'] ?? '').toString(),
      eventType: (data['eventType'] ?? 'one-time').toString(),
      eventDateTime: eventDateTime,
      eventEndDateTime: eventEndDateTime,
      recurrencePattern: data['recurrencePattern'] as String?,
      recurrenceDays: data['recurrenceDays'] != null
          ? List<String>.from(data['recurrenceDays'] as List)
          : null,
      recurrenceTime: data['recurrenceTime'] as String?,
      recurrenceEndTime: data['recurrenceEndTime'] as String?,
      status: (data['status'] ?? 'draft').toString(),
      pinned: data['pinned'] == true,
      createdByUid: (data['createdByUid'] ?? '').toString(),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'imageStoragePath': imageStoragePath,
      'location': location,
      'eventType': eventType,
      'eventDateTime': eventDateTime != null
          ? Timestamp.fromDate(eventDateTime!)
          : null,
      'eventEndDateTime': eventEndDateTime != null
          ? Timestamp.fromDate(eventEndDateTime!)
          : null,
      'recurrencePattern': recurrencePattern,
      'recurrenceDays': recurrenceDays,
      'recurrenceTime': recurrenceTime,
      'recurrenceEndTime': recurrenceEndTime,
      'status': status,
      'pinned': pinned,
      'createdByUid': createdByUid,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  ParishEvent copyWith({
    String? id,
    String? title,
    String? description,
    String? imageUrl,
    String? imageStoragePath,
    String? location,
    String? eventType,
    DateTime? eventDateTime,
    DateTime? eventEndDateTime,
    String? recurrencePattern,
    List<String>? recurrenceDays,
    String? recurrenceTime,
    String? recurrenceEndTime,
    String? status,
    bool? pinned,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ParishEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      imageStoragePath: imageStoragePath ?? this.imageStoragePath,
      location: location ?? this.location,
      eventType: eventType ?? this.eventType,
      eventDateTime: eventDateTime ?? this.eventDateTime,
      eventEndDateTime: eventEndDateTime ?? this.eventEndDateTime,
      recurrencePattern: recurrencePattern ?? this.recurrencePattern,
      recurrenceDays: recurrenceDays ?? this.recurrenceDays,
      recurrenceTime: recurrenceTime ?? this.recurrenceTime,
      recurrenceEndTime: recurrenceEndTime ?? this.recurrenceEndTime,
      status: status ?? this.status,
      pinned: pinned ?? this.pinned,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Gets a display string for when the event occurs
  String get displayTime {
    if (eventType == 'recurring') {
      final days = recurrenceDays?.join(', ') ?? '';
      final time = recurrenceTime ?? '';
      final endTime = recurrenceEndTime;
      if (endTime != null && endTime.isNotEmpty) {
        return '$days: $time - $endTime';
      }
      return '$days: $time';
    } else {
      if (eventDateTime == null) return '';
      final date = '${eventDateTime!.month}/${eventDateTime!.day}/${eventDateTime!.year}';
      final time = '${eventDateTime!.hour}:${eventDateTime!.minute.toString().padLeft(2, '0')}';
      if (eventEndDateTime != null) {
        final endTime = '${eventEndDateTime!.hour}:${eventEndDateTime!.minute.toString().padLeft(2, '0')}';
        return '$date: $time - $endTime';
      }
      return '$date at $time';
    }
  }

  /// Gets a short label for the event (e.g., "Every Sunday" or "Dec 25, 2024")
  String get displayLabel {
    if (eventType == 'recurring') {
      final pattern = recurrencePattern ?? 'regular';
      final days = recurrenceDays?.join(', ') ?? '';
      if (pattern == 'weekly' && recurrenceDays != null && recurrenceDays!.length == 1) {
        return 'Every ${recurrenceDays!.first}';
      }
      return '$pattern on $days';
    } else {
      if (eventDateTime == null) return '';
      final now = DateTime.now();
      final isToday = eventDateTime!.year == now.year &&
          eventDateTime!.month == now.month &&
          eventDateTime!.day == now.day;
      if (isToday) return 'Today';
      
      final isTomorrow = eventDateTime!.year == now.year &&
          eventDateTime!.month == now.month &&
          eventDateTime!.day == now.day + 1;
      if (isTomorrow) return 'Tomorrow';
      
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[eventDateTime!.month - 1]} ${eventDateTime!.day}, ${eventDateTime!.year}';
    }
  }
}

DateTime? _readTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
