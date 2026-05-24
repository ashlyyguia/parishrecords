class LocalNotification {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final bool archived;
  final String? type;
  final String? route;
  final String? resourceId;

  LocalNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.archived = false,
    this.type,
    this.route,
    this.resourceId,
  });

  factory LocalNotification.fromMap(Map data, String id) {
    return LocalNotification(
      id: id,
      title: (data['title'] ?? '').toString(),
      body: (data['body'] ?? data['message'] ?? '').toString(),
      createdAt: DateTime.tryParse((data['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      read: data['read'] == true,
      archived: data['archived'] == true,
      type: data['type']?.toString(),
      route: (data['route'] ?? data['action_route'])?.toString(),
      resourceId: (data['resource_id'] ?? data['resourceId'])?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'body': body,
      'createdAt': DateTime(
        createdAt.year,
        createdAt.month,
        createdAt.day,
        createdAt.hour,
        createdAt.minute,
        createdAt.second,
      ).toIso8601String(),
      'read': read,
      'archived': archived,
      if (type != null) 'type': type,
      if (route != null) 'route': route,
      if (resourceId != null) 'resource_id': resourceId,
    };
  }

  LocalNotification copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? createdAt,
    bool? read,
    bool? archived,
    String? type,
    String? route,
    String? resourceId,
  }) {
    return LocalNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      read: read ?? this.read,
      archived: archived ?? this.archived,
      type: type ?? this.type,
      route: route ?? this.route,
      resourceId: resourceId ?? this.resourceId,
    );
  }
}
