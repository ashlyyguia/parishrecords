// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/household.dart';

/// Repository for Household and HouseholdMember CRUD operations
class HouseholdRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is Timestamp) return raw.toDate();
    return null;
  }

  Household _householdFromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Household(
      id: doc.id,
      householdId: data['householdId'] as String? ?? doc.id,
      familyName: data['familyName'] as String? ?? '',
      headOfFamilyId: data['headOfFamilyId'] as String? ?? '',
      address: data['address'] as String? ?? '',
      barangay: data['barangay'] as String? ?? '',
      city: data['city'] as String? ?? '',
      province: data['province'] as String? ?? '',
      zipCode: data['zipCode'] as String? ?? '',
      contactNumber: data['contactNumber'] as String? ?? '',
      email: data['email'] as String? ?? '',
      registeredAt: _parseDate(data['registeredAt']) ?? DateTime.now(),
      updatedAt: _parseDate(data['updatedAt']),
      isArchived: data['isArchived'] == true,
      notes: data['notes'] as String?,
      metadata: (data['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  HouseholdMember _memberFromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return HouseholdMember(
      id: doc.id,
      householdId: data['householdId'] as String? ?? '',
      firstName: data['firstName'] as String? ?? '',
      middleName: data['middleName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      suffix: data['suffix'] as String?,
      fullName: data['fullName'] as String? ?? '',
      role: data['role'] as String? ?? 'Member',
      birthDate: _parseDate(data['birthDate']),
      birthPlace: data['birthPlace'] as String?,
      gender: data['gender'] as String? ?? 'Male',
      civilStatus: data['civilStatus'] as String? ?? 'Single',
      occupation: data['occupation'] as String?,
      contactNumber: data['contactNumber'] as String?,
      email: data['email'] as String?,
      dateAdded: _parseDate(data['dateAdded']) ?? DateTime.now(),
      updatedAt: _parseDate(data['updatedAt']),
      isActive: data['isActive'] == null ? true : data['isActive'] == true,
      baptismRecordId: data['baptismRecordId'] as String?,
      confirmationRecordId: data['confirmationRecordId'] as String?,
      marriageRecordId: data['marriageRecordId'] as String?,
      deathRecordId: data['deathRecordId'] as String?,
      metadata: (data['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw Exception('Not authenticated');
    return uid;
  }

  /// Generate unique household ID (e.g., HH-2024-001)
  Future<String> generateHouseholdId() async {
    final now = DateTime.now();
    final year = now.year;
    final random = now.millisecondsSinceEpoch % 1000;
    return 'HH-$year-${random.toString().padLeft(3, '0')}';
  }

  // ==================== HOUSEHOLD OPERATIONS ====================

  /// Create a new household
  Future<Household> createHousehold(Household household) async {
    _requireUid();

    final householdId = await generateHouseholdId();
    final data = {
      'householdId': householdId,
      'familyName': household.familyName,
      'headOfFamilyId': household.headOfFamilyId,
      'address': household.address,
      'barangay': household.barangay,
      'city': household.city,
      'province': household.province,
      'zipCode': household.zipCode,
      'contactNumber': household.contactNumber,
      'email': household.email,
      'notes': household.notes,
      'metadata': household.metadata,
      'isArchived': false,
      'registeredAt': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
      'created_by': FirebaseAuth.instance.currentUser?.uid,
    };

    final docRef = await _firestore.collection('households').add(data);
    final doc = await docRef.get();
    return _householdFromFirestore(doc);
  }

  /// Update an existing household
  Future<void> updateHousehold(Household household) async {
    _requireUid();

    final data = {
      'familyName': household.familyName,
      'headOfFamilyId': household.headOfFamilyId,
      'address': household.address,
      'barangay': household.barangay,
      'city': household.city,
      'province': household.province,
      'zipCode': household.zipCode,
      'contactNumber': household.contactNumber,
      'email': household.email,
      'notes': household.notes,
      'metadata': household.metadata,
      'isArchived': household.isArchived,
      'updatedAt': FieldValue.serverTimestamp(),
      'updated_by': FirebaseAuth.instance.currentUser?.uid,
    };

    await _firestore.collection('households').doc(household.id).update(data);
  }

  /// Get a single household by ID
  Future<Household?> getHousehold(String householdId) async {
    final doc = await _firestore
        .collection('households')
        .doc(householdId)
        .get();
    if (!doc.exists) return null;
    return _householdFromFirestore(doc);
  }

  /// List all households (optionally filtered)
  Future<List<Household>> listHouseholds({
    String? search,
    bool includeArchived = false,
  }) async {
    Query<Map<String, dynamic>> query = _firestore.collection('households');

    if (!includeArchived) {
      query = query.where('isArchived', isEqualTo: false);
    }

    final snap = await query.get();
    return snap.docs.map(_householdFromFirestore).toList();
  }

  /// Delete a household by ID
  Future<void> deleteHousehold(String householdId) async {
    _requireUid();
    await _firestore.collection('households').doc(householdId).delete();
  }

  /// Archive/Unarchive a household
  Future<void> setHouseholdArchiveStatus(
    String householdId,
    bool isArchived,
  ) async {
    _requireUid();
    await _firestore.collection('households').doc(householdId).update({
      'isArchived': isArchived,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==================== HOUSEHOLD MEMBER OPERATIONS ====================

  /// Add a member to a household
  Future<HouseholdMember> addHouseholdMember(HouseholdMember member) async {
    _requireUid();

    final data = {
      'householdId': member.householdId,
      'firstName': member.firstName,
      'middleName': member.middleName,
      'lastName': member.lastName,
      'suffix': member.suffix,
      'fullName': member.fullName.isNotEmpty
          ? member.fullName
          : '${member.firstName} ${member.lastName}',
      'role': member.role,
      'birthDate': member.birthDate != null
          ? Timestamp.fromDate(member.birthDate!)
          : null,
      'birthPlace': member.birthPlace,
      'gender': member.gender,
      'civilStatus': member.civilStatus,
      'occupation': member.occupation,
      'contactNumber': member.contactNumber,
      'email': member.email,
      'isActive': member.isActive,
      'baptismRecordId': member.baptismRecordId,
      'confirmationRecordId': member.confirmationRecordId,
      'marriageRecordId': member.marriageRecordId,
      'deathRecordId': member.deathRecordId,
      'metadata': member.metadata,
      'dateAdded': FieldValue.serverTimestamp(),
      'created_by': FirebaseAuth.instance.currentUser?.uid,
    };

    final docRef = await _firestore.collection('household_members').add(data);
    final doc = await docRef.get();
    return _memberFromFirestore(doc);
  }

  /// Update a household member
  Future<void> updateHouseholdMember(HouseholdMember member) async {
    _requireUid();

    final data = {
      'firstName': member.firstName,
      'middleName': member.middleName,
      'lastName': member.lastName,
      'suffix': member.suffix,
      'fullName': member.fullName.isNotEmpty
          ? member.fullName
          : '${member.firstName} ${member.lastName}',
      'role': member.role,
      'birthDate': member.birthDate != null
          ? Timestamp.fromDate(member.birthDate!)
          : null,
      'birthPlace': member.birthPlace,
      'gender': member.gender,
      'civilStatus': member.civilStatus,
      'occupation': member.occupation,
      'contactNumber': member.contactNumber,
      'email': member.email,
      'isActive': member.isActive,
      'baptismRecordId': member.baptismRecordId,
      'confirmationRecordId': member.confirmationRecordId,
      'marriageRecordId': member.marriageRecordId,
      'deathRecordId': member.deathRecordId,
      'metadata': member.metadata,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _firestore
        .collection('household_members')
        .doc(member.id)
        .update(data);
  }

  /// Get a single household member by ID
  Future<HouseholdMember?> getHouseholdMember(String memberId) async {
    final doc = await _firestore
        .collection('household_members')
        .doc(memberId)
        .get();
    if (!doc.exists) return null;
    return _memberFromFirestore(doc);
  }

  /// List members of a specific household
  Future<List<HouseholdMember>> listHouseholdMembers(String householdId) async {
    final snap = await _firestore
        .collection('household_members')
        .where('householdId', isEqualTo: householdId)
        .where('isActive', isEqualTo: true)
        .get();
    return snap.docs.map(_memberFromFirestore).toList();
  }

  /// Remove a household member (soft delete by setting inactive)
  Future<void> removeHouseholdMember(String memberId) async {
    _requireUid();
    await _firestore.collection('household_members').doc(memberId).update({
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Permanently delete a household member
  Future<void> permanentlyDeleteHouseholdMember(String memberId) async {
    _requireUid();
    await _firestore.collection('household_members').doc(memberId).delete();
  }

  // ==================== STREAMS ====================

  /// Stream of households for real-time updates
  Stream<List<Household>> streamHouseholds({bool includeArchived = false}) {
    Query<Map<String, dynamic>> query = _firestore.collection('households');
    if (!includeArchived) {
      query = query.where('isArchived', isEqualTo: false);
    }
    return query.snapshots().map(
      (snap) => snap.docs.map(_householdFromFirestore).toList(),
    );
  }

  /// Stream of household members
  Stream<List<HouseholdMember>> streamHouseholdMembers(String householdId) {
    return _firestore
        .collection('household_members')
        .where('householdId', isEqualTo: householdId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map(_memberFromFirestore).toList());
  }

  /// Search households by family name or member name
  Future<List<Household>> searchHouseholds(String query) async {
    // Firestore doesn't support full text search natively
    // This is a simple prefix search on family name
    final snap = await _firestore
        .collection('households')
        .where('familyName', isGreaterThanOrEqualTo: query)
        .where('familyName', isLessThanOrEqualTo: '$query\uf8ff')
        .get();

    return snap.docs.map(_householdFromFirestore).toList();
  }

  // ==================== ALIASES FOR API COMPATIBILITY ====================

  /// Alias for streamHouseholds with filter support
  Stream<List<Household>> watchHouseholds({
    bool includeArchived = false,
    String? barangay,
    String? searchQuery,
  }) {
    Query<Map<String, dynamic>> query = _firestore.collection('households');

    if (!includeArchived) {
      query = query.where('isArchived', isEqualTo: false);
    }

    if (barangay != null && barangay.isNotEmpty) {
      query = query.where('barangay', isEqualTo: barangay);
    }

    // Note: searchQuery filtering is done client-side as Firestore doesn't support full-text search
    return query.snapshots().map((snap) {
      var households = snap.docs.map(_householdFromFirestore).toList();
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final lowerQuery = searchQuery.toLowerCase();
        households = households.where((h) {
          return h.familyName.toLowerCase().contains(lowerQuery) ||
              h.address.toLowerCase().contains(lowerQuery);
        }).toList();
      }
      return households;
    });
  }

  /// Alias for streamHouseholdMembers
  Stream<List<HouseholdMember>> watchHouseholdMembers(String householdId) {
    return streamHouseholdMembers(householdId);
  }

  /// Stream all members globally (for admin view) with optional filters
  Stream<List<HouseholdMember>> watchMembersGlobal({
    String? searchQuery,
    String? sacramentStatus,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('household_members')
        .where('isActive', isEqualTo: true);

    return query.snapshots().map((snap) {
      var members = snap.docs.map(_memberFromFirestore).toList();

      // Client-side filtering for search query
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final lowerQuery = searchQuery.toLowerCase();
        members = members.where((m) {
          return m.fullName.toLowerCase().contains(lowerQuery) ||
              m.firstName.toLowerCase().contains(lowerQuery) ||
              m.lastName.toLowerCase().contains(lowerQuery);
        }).toList();
      }

      // Filter by sacrament status if specified
      if (sacramentStatus != null && sacramentStatus.isNotEmpty) {
        members = members.where((m) {
          switch (sacramentStatus) {
            case 'baptized':
              return m.baptismRecordId != null;
            case 'confirmed':
              return m.confirmationRecordId != null;
            case 'married':
              return m.marriageRecordId != null;
            case 'deceased':
              return m.deathRecordId != null;
            default:
              return true;
          }
        }).toList();
      }

      return members;
    });
  }

  /// Alias for listHouseholdMembers
  Future<List<HouseholdMember>> getHouseholdMembers(String householdId) async {
    return listHouseholdMembers(householdId);
  }

  /// Alias for getHouseholdMember
  Future<HouseholdMember?> getMember(String memberId) async {
    return getHouseholdMember(memberId);
  }

  /// Alias for addHouseholdMember
  Future<HouseholdMember> addMember(HouseholdMember member) async {
    return addHouseholdMember(member);
  }

  /// Alias for updateHouseholdMember
  Future<void> updateMember(HouseholdMember member) async {
    return updateHouseholdMember(member);
  }

  /// Alias for removeHouseholdMember (soft delete)
  Future<void> deleteMember(String memberId) async {
    return removeHouseholdMember(memberId);
  }

  /// Set head of family for a household
  Future<void> setHeadOfFamily(String householdId, String memberId) async {
    _requireUid();
    await _firestore.collection('households').doc(householdId).update({
      'headOfFamilyId': memberId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get households for current user
  Future<List<Household>> getMyHouseholds() async {
    final uid = _requireUid();
    final snap = await _firestore
        .collection('households')
        .where('created_by', isEqualTo: uid)
        .where('isArchived', isEqualTo: false)
        .get();
    return snap.docs.map(_householdFromFirestore).toList();
  }

  /// Get unique barangays from all households
  Future<List<String>> getBarangays() async {
    final snap = await _firestore.collection('households').get();
    final barangays = <String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final barangay = data['barangay'] as String?;
      if (barangay != null && barangay.isNotEmpty) {
        barangays.add(barangay);
      }
    }
    return barangays.toList()..sort();
  }

  /// Get household statistics (global or specific)
  Future<Map<String, dynamic>> getHouseholdStats([String? householdId]) async {
    if (householdId != null) {
      // Get stats for specific household
      final membersSnap = await _firestore
          .collection('household_members')
          .where('householdId', isEqualTo: householdId)
          .where('isActive', isEqualTo: true)
          .count()
          .get();

      return {
        'memberCount': membersSnap.count ?? 0,
        'householdId': householdId,
      };
    } else {
      // Get global stats
      final householdsSnap = await _firestore
          .collection('households')
          .count()
          .get();
      final membersSnap = await _firestore
          .collection('household_members')
          .count()
          .get();

      return {
        'totalHouseholds': householdsSnap.count ?? 0,
        'totalMembers': membersSnap.count ?? 0,
      };
    }
  }

  /// Link sacrament record to a household member
  /// Can be called with named parameters or with just memberId for placeholder linking
  Future<void> linkSacramentRecord({
    required String memberId,
    String? recordType,
    String? recordId,
  }) async {
    _requireUid();

    final data = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};

    if (recordType != null && recordId != null) {
      final fieldName = '${recordType}RecordId';
      data[fieldName] = recordId;
    }

    await _firestore.collection('household_members').doc(memberId).update(data);
  }
}
