class LocalNotification {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final bool archived;

  LocalNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.archived = false,
  });

  factory LocalNotification.fromMap(Map data, String id) {
    return LocalNotification(
      id: id,
      title: (data['title'] ?? '').toString(),
      body: (data['body'] ?? '').toString(),
      createdAt: DateTime.tryParse((data['createdAt'] ?? '').toString()) ?? DateTime.now(),
      read: data['read'] == true,
      archived: data['archived'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'body': body,
      'createdAt': DateTime(createdAt.year, createdAt.month, createdAt.day, createdAt.hour, createdAt.minute, createdAt.second).toIso8601String(),
      'read': read,
      'archived': archived,
    };
  }

  LocalNotification copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? createdAt,
    bool? read,
    bool? archived,
  }) {
    return LocalNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      read: read ?? this.read,
      archived: archived ?? this.archived,
    );
  }
}
