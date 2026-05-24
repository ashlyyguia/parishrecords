import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a household in the parish
class Household {
  final String id;
  final String householdId; // Unique Household ID (e.g., HH-2024-001)
  final String familyName;
  final String headOfFamilyId; // Reference to member who is head
  final String address;
  final String barangay;
  final String city;
  final String province;
  final String zipCode;
  final String contactNumber;
  final String email;
  final DateTime registeredAt;
  final DateTime? updatedAt;
  final bool isArchived;
  final String? notes;
  final Map<String, dynamic> metadata;

  Household({
    required this.id,
    required this.householdId,
    required this.familyName,
    required this.headOfFamilyId,
    required this.address,
    required this.barangay,
    required this.city,
    this.province = '',
    this.zipCode = '',
    this.contactNumber = '',
    this.email = '',
    required this.registeredAt,
    this.updatedAt,
    this.isArchived = false,
    this.notes,
    this.metadata = const {},
  });

  factory Household.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Household(
      id: doc.id,
      householdId: data['householdId'] ?? '',
      familyName: data['familyName'] ?? '',
      headOfFamilyId: data['headOfFamilyId'] ?? '',
      address: data['address'] ?? '',
      barangay: data['barangay'] ?? '',
      city: data['city'] ?? '',
      province: data['province'] ?? '',
      zipCode: data['zipCode'] ?? '',
      contactNumber: data['contactNumber'] ?? '',
      email: data['email'] ?? '',
      registeredAt:
          (data['registeredAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      isArchived: data['isArchived'] ?? false,
      notes: data['notes'],
      metadata: data['metadata'] ?? {},
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'householdId': householdId,
      'familyName': familyName,
      'headOfFamilyId': headOfFamilyId,
      'address': address,
      'barangay': barangay,
      'city': city,
      'province': province,
      'zipCode': zipCode,
      'contactNumber': contactNumber,
      'email': email,
      'registeredAt': Timestamp.fromDate(registeredAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'isArchived': isArchived,
      'notes': notes,
      'metadata': metadata,
    };
  }

  Household copyWith({
    String? id,
    String? householdId,
    String? familyName,
    String? headOfFamilyId,
    String? address,
    String? barangay,
    String? city,
    String? province,
    String? zipCode,
    String? contactNumber,
    String? email,
    DateTime? registeredAt,
    DateTime? updatedAt,
    bool? isArchived,
    String? notes,
    Map<String, dynamic>? metadata,
  }) {
    return Household(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      familyName: familyName ?? this.familyName,
      headOfFamilyId: headOfFamilyId ?? this.headOfFamilyId,
      address: address ?? this.address,
      barangay: barangay ?? this.barangay,
      city: city ?? this.city,
      province: province ?? this.province,
      zipCode: zipCode ?? this.zipCode,
      contactNumber: contactNumber ?? this.contactNumber,
      email: email ?? this.email,
      registeredAt: registeredAt ?? this.registeredAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
      notes: notes ?? this.notes,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Represents a family member within a household
class HouseholdMember {
  final String id;
  final String householdId;
  final String firstName;
  final String middleName;
  final String lastName;
  final String? suffix; // Jr., Sr., III, etc.
  final String fullName;
  final String role; // Father, Mother, Child, Guardian, etc.
  final DateTime? birthDate;
  final String? birthPlace;
  final String gender; // Male, Female
  final String civilStatus; // Single, Married, Widowed, etc.
  final String? occupation;
  final String? contactNumber;
  final String? email;
  final DateTime? dateAdded;
  final DateTime? updatedAt;
  final bool isActive;

  // Sacrament tracking
  final String? baptismRecordId;
  final String? confirmationRecordId;
  final String? marriageRecordId;
  final String? deathRecordId;

  final Map<String, dynamic> metadata;

  HouseholdMember({
    required this.id,
    required this.householdId,
    required this.firstName,
    this.middleName = '',
    required this.lastName,
    this.suffix,
    required this.fullName,
    required this.role,
    this.birthDate,
    this.birthPlace,
    required this.gender,
    this.civilStatus = 'Single',
    this.occupation,
    this.contactNumber,
    this.email,
    this.dateAdded,
    this.updatedAt,
    this.isActive = true,
    this.baptismRecordId,
    this.confirmationRecordId,
    this.marriageRecordId,
    this.deathRecordId,
    this.metadata = const {},
  });

  factory HouseholdMember.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return HouseholdMember(
      id: doc.id,
      householdId: data['householdId'] ?? '',
      firstName: data['firstName'] ?? '',
      middleName: data['middleName'] ?? '',
      lastName: data['lastName'] ?? '',
      suffix: data['suffix'],
      fullName: data['fullName'] ?? '',
      role: data['role'] ?? 'Member',
      birthDate: (data['birthDate'] as Timestamp?)?.toDate(),
      birthPlace: data['birthPlace'],
      gender: data['gender'] ?? 'Male',
      civilStatus: data['civilStatus'] ?? 'Single',
      occupation: data['occupation'],
      contactNumber: data['contactNumber'],
      email: data['email'],
      dateAdded: (data['dateAdded'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      isActive: data['isActive'] ?? true,
      baptismRecordId: data['baptismRecordId'],
      confirmationRecordId: data['confirmationRecordId'],
      marriageRecordId: data['marriageRecordId'],
      deathRecordId: data['deathRecordId'],
      metadata: data['metadata'] ?? {},
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'householdId': householdId,
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'suffix': suffix,
      'fullName': fullName,
      'role': role,
      'birthDate': birthDate != null ? Timestamp.fromDate(birthDate!) : null,
      'birthPlace': birthPlace,
      'gender': gender,
      'civilStatus': civilStatus,
      'occupation': occupation,
      'contactNumber': contactNumber,
      'email': email,
      'dateAdded': dateAdded != null
          ? Timestamp.fromDate(dateAdded!)
          : Timestamp.now(),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'isActive': isActive,
      'baptismRecordId': baptismRecordId,
      'confirmationRecordId': confirmationRecordId,
      'marriageRecordId': marriageRecordId,
      'deathRecordId': deathRecordId,
      'metadata': metadata,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'householdId': householdId,
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'suffix': suffix,
      'fullName': fullName,
      'role': role,
      'birthDate': birthDate?.toIso8601String(),
      'birthPlace': birthPlace,
      'gender': gender,
      'civilStatus': civilStatus,
      'occupation': occupation,
      'contactNumber': contactNumber,
      'email': email,
      'dateAdded': dateAdded?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isActive': isActive,
      'baptismRecordId': baptismRecordId,
      'confirmationRecordId': confirmationRecordId,
      'marriageRecordId': marriageRecordId,
      'deathRecordId': deathRecordId,
      'metadata': metadata,
    };
  }

  HouseholdMember copyWith({
    String? id,
    String? householdId,
    String? firstName,
    String? middleName,
    String? lastName,
    String? suffix,
    String? fullName,
    String? role,
    DateTime? birthDate,
    String? birthPlace,
    String? gender,
    String? civilStatus,
    String? occupation,
    String? contactNumber,
    String? email,
    DateTime? dateAdded,
    DateTime? updatedAt,
    bool? isActive,
    String? baptismRecordId,
    String? confirmationRecordId,
    String? marriageRecordId,
    String? deathRecordId,
    Map<String, dynamic>? metadata,
  }) {
    return HouseholdMember(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      suffix: suffix ?? this.suffix,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      birthDate: birthDate ?? this.birthDate,
      birthPlace: birthPlace ?? this.birthPlace,
      gender: gender ?? this.gender,
      civilStatus: civilStatus ?? this.civilStatus,
      occupation: occupation ?? this.occupation,
      contactNumber: contactNumber ?? this.contactNumber,
      email: email ?? this.email,
      dateAdded: dateAdded ?? this.dateAdded,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      baptismRecordId: baptismRecordId ?? this.baptismRecordId,
      confirmationRecordId: confirmationRecordId ?? this.confirmationRecordId,
      marriageRecordId: marriageRecordId ?? this.marriageRecordId,
      deathRecordId: deathRecordId ?? this.deathRecordId,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Helper to generate full name from parts
  static String generateFullName(
    String first,
    String middle,
    String last,
    String? suffix,
  ) {
    final parts = <String>[];
    if (first.isNotEmpty) parts.add(first);
    if (middle.isNotEmpty) parts.add(middle);
    if (last.isNotEmpty) parts.add(last);
    if (suffix != null && suffix.isNotEmpty) parts.add(suffix);
    return parts.join(' ');
  }

  /// Get age from birthdate
  int? get age {
    if (birthDate == null) return null;
    final now = DateTime.now();
    var age = now.year - birthDate!.year;
    if (now.month < birthDate!.month ||
        (now.month == birthDate!.month && now.day < birthDate!.day)) {
      age--;
    }
    return age;
  }

  /// Get initials for avatar
  String get initials {
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '${firstName[0]}${lastName[0]}'.toUpperCase();
    }
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }
}

/// Roles available for family members
class FamilyRoles {
  static const String father = 'Father';
  static const String mother = 'Mother';
  static const String child = 'Child';
  static const String son = 'Son'; // Backward compat
  static const String daughter = 'Daughter'; // Backward compat
  static const String guardian = 'Guardian';
  static const String spouse = 'Spouse';
  static const String grandparent = 'Grandparent';
  static const String grandfather = 'Grandfather'; // Backward compat
  static const String grandmother = 'Grandmother'; // Backward compat
  static const String relative = 'Relative';
  static const String other = 'Other';

  static const List<String> all = [
    father,
    mother,
    child,
    son,
    daughter,
    guardian,
    spouse,
    grandparent,
    grandfather,
    grandmother,
    relative,
    other,
  ];
}

/// Genders for members
class Genders {
  static const String male = 'Male';
  static const String female = 'Female';

  static const List<String> all = [male, female];
}

/// Civil status options
class CivilStatuses {
  static const String single = 'Single';
  static const String married = 'Married';
  static const String widowed = 'Widowed';
  static const String separated = 'Separated';
  static const String annulled = 'Annulled';

  static const List<String> all = [
    single,
    married,
    widowed,
    separated,
    annulled,
  ];
}
