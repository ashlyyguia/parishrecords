import 'package:cloud_firestore/cloud_firestore.dart';

class Announcement {
  final String id;
  final String title;
  final String description;
  final String? imageUrl;
  final String? imageStoragePath;
  final String? attachmentUrl;
  final String? attachmentStoragePath;
  final DateTime eventDateTime;
  final String location;
  final String status; // active | archived | draft
  final bool pinned;
  final String createdByUid;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int views;

  Announcement({
    required this.id,
    required this.title,
    required this.description,
    this.imageUrl,
    this.imageStoragePath,
    this.attachmentUrl,
    this.attachmentStoragePath,
    required this.eventDateTime,
    required this.location,
    required this.status,
    required this.pinned,
    required this.createdByUid,
    required this.createdAt,
    required this.updatedAt,
    required this.views,
  });

  factory Announcement.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final createdAt = _readTimestamp(data['createdAt']) ?? DateTime.now();
    final updatedAt = _readTimestamp(data['updatedAt']) ?? createdAt;
    final event = _readTimestamp(data['eventDateTime']) ?? DateTime.now();

    return Announcement(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      imageUrl: data['imageUrl'] as String?,
      imageStoragePath: data['imageStoragePath'] as String?,
      attachmentUrl: data['attachmentUrl'] as String?,
      attachmentStoragePath: data['attachmentStoragePath'] as String?,
      eventDateTime: event,
      location: (data['location'] ?? '').toString(),
      status: (data['status'] ?? 'draft').toString(),
      pinned: data['pinned'] == true,
      createdByUid: (data['createdByUid'] ?? '').toString(),
      createdAt: createdAt,
      updatedAt: updatedAt,
      views: (data['views'] ?? 0) is int
          ? data['views'] as int
          : int.tryParse(data['views'].toString()) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'imageStoragePath': imageStoragePath,
      'attachmentUrl': attachmentUrl,
      'attachmentStoragePath': attachmentStoragePath,
      'eventDateTime': Timestamp.fromDate(eventDateTime),
      'location': location,
      'status': status,
      'pinned': pinned,
      'createdByUid': createdByUid,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'views': views,
    };
  }

  Announcement copyWith({
    String? id,
    String? title,
    String? description,
    String? imageUrl,
    String? imageStoragePath,
    String? attachmentUrl,
    String? attachmentStoragePath,
    DateTime? eventDateTime,
    String? location,
    String? status,
    bool? pinned,
    String? createdByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? views,
  }) {
    return Announcement(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      imageStoragePath: imageStoragePath ?? this.imageStoragePath,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      attachmentStoragePath:
          attachmentStoragePath ?? this.attachmentStoragePath,
      eventDateTime: eventDateTime ?? this.eventDateTime,
      location: location ?? this.location,
      status: status ?? this.status,
      pinned: pinned ?? this.pinned,
      createdByUid: createdByUid ?? this.createdByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      views: views ?? this.views,
    );
  }
}

DateTime? _readTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
