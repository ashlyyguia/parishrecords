import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String id;
  final String email;
  final String? displayName;
  final String role; // admin, staff
  final DateTime createdAt;
  final DateTime? lastLogin;
  final bool emailVerified;

  AppUser({
    required this.id,
    required this.email,
    this.displayName,
    required this.role,
    DateTime? createdAt,
    this.lastLogin,
    this.emailVerified = false,
  }) : createdAt = createdAt ?? DateTime.now();

  // Convert to Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'role': role,
      'createdAt': createdAt.toIso8601String(),
      'lastLogin': lastLogin?.toIso8601String(),
      'emailVerified': emailVerified,
    };
  }

  // Create from Map
  factory AppUser.fromMap(Map<String, dynamic> map) {
    DateTime? toDate(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      if (v is Timestamp) return v.toDate();
      return null;
    }

    final id = (map['id'] ?? map['uid'] ?? '') as String;

    return AppUser(
      id: id,
      email: (map['email'] ?? '') as String,
      displayName: map['displayName'] as String?,
      role: (map['role'] as String?)?.isNotEmpty == true
          ? map['role'] as String
          : 'staff',
      createdAt: toDate(map['createdAt']),
      lastLogin: toDate(map['lastLogin']),
      emailVerified: map['emailVerified'] as bool? ?? false,
    );
  }

  // Copy with method for immutability
  AppUser copyWith({
    String? id,
    String? email,
    String? displayName,
    String? role,
    DateTime? createdAt,
    DateTime? lastLogin,
    bool? emailVerified,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      emailVerified: emailVerified ?? this.emailVerified,
    );
  }
}
