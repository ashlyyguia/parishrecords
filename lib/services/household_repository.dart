// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/household.dart';
import '../config/backend.dart';

/// Repository for Household and HouseholdMember CRUD operations
class HouseholdRepository {
  HouseholdRepository();

  String get _base => BackendConfig.baseUrl;

  Future<Map<String, String>> _authHeader() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  Household _householdFromApi(Map<String, dynamic> data) {
    return Household(
      id: (data['id'] as String?) ?? '',
      householdId: (data['householdId'] as String?) ?? '',
      familyName: (data['familyName'] as String?) ?? '',
      headOfFamilyId: (data['headOfFamilyId'] as String?) ?? '',
      address: (data['address'] as String?) ?? '',
      barangay: (data['barangay'] as String?) ?? '',
      city: (data['city'] as String?) ?? '',
      province: (data['province'] as String?) ?? '',
      zipCode: (data['zipCode'] as String?) ?? '',
      contactNumber: (data['contactNumber'] as String?) ?? '',
      email: (data['email'] as String?) ?? '',
      registeredAt: _parseDate(data['registeredAt']) ?? DateTime.now(),
      updatedAt: _parseDate(data['updatedAt']),
      isArchived: data['isArchived'] == true,
      notes: data['notes'] as String?,
      metadata: (data['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  HouseholdMember _memberFromApi(Map<String, dynamic> data) {
    return HouseholdMember(
      id: (data['id'] as String?) ?? '',
      householdId: (data['householdId'] as String?) ?? '',
      firstName: (data['firstName'] as String?) ?? '',
      middleName: (data['middleName'] as String?) ?? '',
      lastName: (data['lastName'] as String?) ?? '',
      suffix: data['suffix'] as String?,
      fullName: (data['fullName'] as String?) ?? '',
      role: (data['role'] as String?) ?? 'Member',
      birthDate: _parseDate(data['birthDate']),
      birthPlace: data['birthPlace'] as String?,
      gender: (data['gender'] as String?) ?? 'Male',
      civilStatus: (data['civilStatus'] as String?) ?? 'Single',
      occupation: data['occupation'] as String?,
      contactNumber: data['contactNumber'] as String?,
      email: data['email'] as String?,
      dateAdded: _parseDate(data['dateAdded']),
      updatedAt: _parseDate(data['updatedAt']),
      isActive: data['isActive'] == null ? true : data['isActive'] == true,
      baptismRecordId: data['baptismRecordId'] as String?,
      confirmationRecordId: data['confirmationRecordId'] as String?,
      marriageRecordId: data['marriageRecordId'] as String?,
      deathRecordId: data['deathRecordId'] as String?,
      metadata: (data['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  /// Generate unique household ID (e.g., HH-2024-001)
  Future<String> generateHouseholdId() async {
    // The backend generates the household ID.
    // This method is kept only for API compatibility.
    return 'HH-${DateTime.now().year}-000';
  }

  // ==================== HOUSEHOLD OPERATIONS ====================

  /// Create a new household
  Future<Household> createHousehold(Household household) async {
    final headers = await _authHeader();
    final payload = {
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
    };

    final resp = await http.post(
      Uri.parse('$_base/api/households'),
      headers: headers,
      body: json.encode(payload),
    );
    if (resp.statusCode != 201) {
      throw Exception(
        'Create household failed: ${resp.statusCode} ${resp.body}',
      );
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final data =
        (body['household'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    return _householdFromApi(data);
  }

  /// Update an existing household
  Future<void> updateHousehold(Household household) async {
    final headers = await _authHeader();
    final payload = {
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
    };
    final resp = await http.put(
      Uri.parse('$_base/api/households/${household.id}'),
      headers: headers,
      body: json.encode(payload),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Update household failed: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  /// Get a household by ID
  Future<Household?> getHousehold(String id) async {
    final headers = await _authHeader();
    final resp = await http.get(
      Uri.parse('$_base/api/households/$id'),
      headers: headers,
    );
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw Exception('Get household failed: ${resp.statusCode} ${resp.body}');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final data =
        (body['household'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    return _householdFromApi(data);
  }

  /// Get a household by householdId (e.g., HH-2024-001)
  Future<Household?> getHouseholdByHouseholdId(String householdId) async {
    final headers = await _authHeader();
    final resp = await http.get(
      Uri.parse('$_base/api/households?search=$householdId&limit=50'),
      headers: headers,
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Search households failed: ${resp.statusCode} ${resp.body}',
      );
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final rows = (body['households'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final match = rows.firstWhere(
      (h) => (h['householdId'] as String?) == householdId,
      orElse: () => <String, dynamic>{},
    );
    if (match.isEmpty) return null;
    return _householdFromApi(match);
  }

  /// Archive/Unarchive a household
  Future<void> setHouseholdArchiveStatus(String id, bool archived) async {
    final headers = await _authHeader();
    final resp = await http.patch(
      Uri.parse('$_base/api/households/$id/archive'),
      headers: headers,
      body: json.encode({'archived': archived}),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Archive household failed: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  /// Delete a household (and all its members)
  Future<void> deleteHousehold(String id) async {
    final headers = await _authHeader();
    final resp = await http.delete(
      Uri.parse('$_base/api/households/$id'),
      headers: headers,
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Delete household failed: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  /// Stream of households with optional filters
  Stream<List<Household>> watchHouseholds({
    String? barangay,
    bool includeArchived = false,
    String? searchQuery,
  }) {
    // Firestore snapshots were replaced by backend polling.
    // This provides a Stream API compatible with existing UI/providers.
    final controller = StreamController<List<Household>>();
    Timer? timer;

    Future<void> tick() async {
      try {
        final headers = await _authHeader();
        final params = <String, String>{'limit': '200'};
        if (barangay != null && barangay.isNotEmpty)
          params['barangay'] = barangay;
        if (includeArchived) params['includeArchived'] = 'true';
        if (searchQuery != null && searchQuery.isNotEmpty)
          params['search'] = searchQuery;

        final uri = Uri.parse(
          '$_base/api/households',
        ).replace(queryParameters: params);
        debugPrint('[Households Repo] Fetching from: $uri');
        final resp = await http.get(uri, headers: headers);
        debugPrint('[Households Repo] Response: ${resp.statusCode}');
        if (resp.statusCode != 200) {
          throw Exception(
            'Watch households failed: ${resp.statusCode} ${resp.body}',
          );
        }
        final body = json.decode(resp.body) as Map<String, dynamic>;
        final rows = (body['households'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        debugPrint('[Households Repo] Parsed ${rows.length} households');
        final households = rows.map(_householdFromApi).toList();
        controller.add(households);
      } catch (e, st) {
        debugPrint('[Households Repo] Error: $e');
        controller.addError(e, st);
      }
    }

    controller.onListen = () {
      tick();
      timer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => tick(),
      ); // 60s — avoids 429 rate limit
    };
    controller.onCancel = () {
      timer?.cancel();
      timer = null;
    };

    return controller.stream;
  }

  /// Get all barangays (for filter dropdown)
  Future<List<String>> getBarangays() async {
    final headers = await _authHeader();
    final resp = await http.get(
      Uri.parse('$_base/api/households/meta/barangays'),
      headers: headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('Get barangays failed: ${resp.statusCode} ${resp.body}');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final rows = (body['barangays'] as List<dynamic>? ?? []).cast<String>();
    return rows;
  }

  // ==================== MEMBER OPERATIONS ====================

  /// Add a member to a household
  Future<HouseholdMember> addMember(HouseholdMember member) async {
    final headers = await _authHeader();
    final payload = {
      'firstName': member.firstName,
      'middleName': member.middleName,
      'lastName': member.lastName,
      'suffix': member.suffix,
      'fullName': HouseholdMember.generateFullName(
        member.firstName,
        member.middleName,
        member.lastName,
        member.suffix,
      ),
      'role': member.role,
      'birthDate': member.birthDate?.toIso8601String(),
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
    };

    final resp = await http.post(
      Uri.parse('$_base/api/households/${member.householdId}/members'),
      headers: headers,
      body: json.encode(payload),
    );
    if (resp.statusCode != 201) {
      throw Exception('Add member failed: ${resp.statusCode} ${resp.body}');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final data =
        (body['member'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    return _memberFromApi(data);
  }

  /// Update a member
  Future<void> updateMember(HouseholdMember member) async {
    final headers = await _authHeader();
    final payload = {
      'firstName': member.firstName,
      'middleName': member.middleName,
      'lastName': member.lastName,
      'suffix': member.suffix,
      'fullName': HouseholdMember.generateFullName(
        member.firstName,
        member.middleName,
        member.lastName,
        member.suffix,
      ),
      'role': member.role,
      'birthDate': member.birthDate?.toIso8601String(),
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
    };
    final resp = await http.put(
      Uri.parse(
        '$_base/api/households/${member.householdId}/members/${member.id}',
      ),
      headers: headers,
      body: json.encode(payload),
    );
    if (resp.statusCode != 200) {
      throw Exception('Update member failed: ${resp.statusCode} ${resp.body}');
    }
  }

  /// Delete a member
  Future<void> deleteMember(String memberId) async {
    final headers = await _authHeader();
    final resp = await http.delete(
      Uri.parse('$_base/api/households/members/$memberId'),
      headers: headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('Delete member failed: ${resp.statusCode} ${resp.body}');
    }
  }

  /// Get a member by ID
  Future<HouseholdMember?> getMember(String id) async {
    final headers = await _authHeader();
    final resp = await http.get(
      Uri.parse('$_base/api/households/members/$id'),
      headers: headers,
    );
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw Exception('Get member failed: ${resp.statusCode} ${resp.body}');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final data =
        (body['member'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    return _memberFromApi(data);
  }

  /// Get all members of a household
  Future<List<HouseholdMember>> getHouseholdMembers(String householdId) async {
    final headers = await _authHeader();
    final resp = await http.get(
      Uri.parse('$_base/api/households/$householdId/members'),
      headers: headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('Get members failed: ${resp.statusCode} ${resp.body}');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final rows = (body['members'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return rows.map(_memberFromApi).toList();
  }

  /// Stream of household members
  Stream<List<HouseholdMember>> watchHouseholdMembers(String householdId) {
    final controller = StreamController<List<HouseholdMember>>();
    Timer? timer;

    Future<void> tick() async {
      try {
        final rows = await getHouseholdMembers(householdId);
        controller.add(rows);
      } catch (e, st) {
        controller.addError(e, st);
      }
    }

    controller.onListen = () {
      tick();
      timer = Timer.periodic(
        const Duration(seconds: 45),
        (_) => tick(),
      ); // 45s — reduces N concurrent polls
    };
    controller.onCancel = () {
      timer?.cancel();
      timer = null;
    };

    return controller.stream;
  }

  /// Set head of family
  Future<void> setHeadOfFamily(String householdId, String memberId) async {
    final headers = await _authHeader();
    final resp = await http.patch(
      Uri.parse('$_base/api/households/$householdId/head-of-family'),
      headers: headers,
      body: json.encode({'memberId': memberId}),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Set head-of-family failed: ${resp.statusCode} ${resp.body}',
      );
    }
  }

  /// Link sacrament record to member
  Future<void> linkSacramentRecord({
    required String memberId,
    String? baptismRecordId,
    String? confirmationRecordId,
    String? marriageRecordId,
    String? deathRecordId,
  }) async {
    final headers = await _authHeader();
    final payload = <String, dynamic>{};
    if (baptismRecordId != null) payload['baptismRecordId'] = baptismRecordId;
    if (confirmationRecordId != null) {
      payload['confirmationRecordId'] = confirmationRecordId;
    }
    if (marriageRecordId != null)
      payload['marriageRecordId'] = marriageRecordId;
    if (deathRecordId != null) payload['deathRecordId'] = deathRecordId;

    final resp = await http.post(
      Uri.parse('$_base/api/households/members/$memberId/sacraments'),
      headers: headers,
      body: json.encode(payload),
    );
    if (resp.statusCode != 200) {
      throw Exception('Link sacrament failed: ${resp.statusCode} ${resp.body}');
    }
  }

  /// Search members across all households
  Future<List<HouseholdMember>> searchMembers(String query) async {
    final headers = await _authHeader();
    final uri = Uri.parse(
      '$_base/api/households/members?search=${Uri.encodeQueryComponent(query)}',
    );
    final resp = await http.get(uri, headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Search members failed: ${resp.statusCode} ${resp.body}');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final rows = (body['rows'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return rows.map(_memberFromApi).toList(growable: false);
  }

  /// Stream global members list (admin parishioners) via polling.
  Stream<List<HouseholdMember>> watchMembersGlobal({
    String? searchQuery,
    String? sacramentStatus,
    Duration interval = const Duration(seconds: 5),
    int limit = 200,
  }) {
    final controller = StreamController<List<HouseholdMember>>();
    Timer? timer;

    Future<void> tick() async {
      try {
        final headers = await _authHeader();
        final params = <String, String>{'limit': '$limit'};
        if (searchQuery != null && searchQuery.trim().isNotEmpty) {
          params['search'] = searchQuery.trim();
        }
        if (sacramentStatus != null && sacramentStatus.trim().isNotEmpty) {
          params['sacramentStatus'] = sacramentStatus.trim();
        }
        final uri = Uri.parse(
          '$_base/api/households/members',
        ).replace(queryParameters: params);
        final resp = await http.get(uri, headers: headers);
        if (resp.statusCode != 200) {
          throw Exception(
            'List members failed: ${resp.statusCode} ${resp.body}',
          );
        }
        final body = json.decode(resp.body) as Map<String, dynamic>;
        final rows = (body['rows'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        final members = rows.map(_memberFromApi).toList(growable: false);
        if (!controller.isClosed) controller.add(members);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller.onListen = () {
      tick();
      timer = Timer.periodic(interval, (_) => tick());
    };
    controller.onCancel = () {
      timer?.cancel();
      timer = null;
    };

    return controller.stream;
  }

  /// Get member count for a household
  Future<int> getMemberCount(String householdId) async {
    final members = await getHouseholdMembers(householdId);
    return members.length;
  }

  /// Get household statistics
  Future<Map<String, dynamic>> getHouseholdStats(String householdId) async {
    final headers = await _authHeader();
    final resp = await http.get(
      Uri.parse('$_base/api/households/$householdId/stats'),
      headers: headers,
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'Get household stats failed: ${resp.statusCode} ${resp.body}',
      );
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final stats =
        (body['stats'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return stats;
  }

  /// Get current user's households
  Future<List<Household>> getMyHouseholds() async {
    // Backend households API does not support userId filter.
    // For now, return all households and let UI filter by ownership if present.
    final headers = await _authHeader();
    final resp = await http.get(
      Uri.parse('$_base/api/households?limit=200'),
      headers: headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('Get households failed: ${resp.statusCode} ${resp.body}');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final rows = (body['households'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return rows.map(_householdFromApi).toList();
  }
}
