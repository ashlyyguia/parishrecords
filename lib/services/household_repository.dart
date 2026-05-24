// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/household.dart';

/// Result of server-side sacrament record auto-linking.
class SacramentAutoLinkResult {
  const SacramentAutoLinkResult({
    required this.linkedCount,
    this.linked = const {},
  });

  final int linkedCount;
  final Map<String, String> linked;
}

class _Candidate {
  final String fullName;
  final DateTime? dateOfBirth;

  const _Candidate({required this.fullName, required this.dateOfBirth});
}

class _Match {
  final String recordId;
  final int score;
  final String matchedName;

  const _Match({
    required this.recordId,
    required this.score,
    required this.matchedName,
  });

  Map<String, dynamic> toJson() {
    return {'recordId': recordId, 'score': score, 'matchedName': matchedName};
  }
}

/// Repository for Household and HouseholdMember CRUD operations
class HouseholdRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _memberDisplayName(HouseholdMember member) {
    final full = member.fullName.trim();
    if (full.isNotEmpty) return full;
    return [
      member.firstName,
      member.middleName,
      member.lastName,
    ].where((p) => p.trim().isNotEmpty).join(' ').trim();
  }

  String _normalizeName(String raw) {
    final s = raw.toLowerCase().trim();
    final cleaned = s.replaceAll(RegExp(r"[^a-z0-9\s]"), ' ');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _nameVariants(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    final variants = <String>{trimmed};
    if (trimmed.contains(',')) {
      final parts = trimmed
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.length == 2) {
        variants.add('${parts[1]} ${parts[0]}');
        variants.add('${parts[0]} ${parts[1]}');
      }
    }
    return variants.toList();
  }

  bool _sameYmd(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  int _nameMatchScore(String memberName, String recordName) {
    var best = 0;
    for (final m in _nameVariants(memberName)) {
      for (final r in _nameVariants(recordName)) {
        best = best < _nameMatchScoreSingle(m, r) ? _nameMatchScoreSingle(m, r) : best;
      }
    }
    return best;
  }

  int _nameMatchScoreSingle(String memberName, String recordName) {
    final a = _normalizeName(memberName);
    final b = _normalizeName(recordName);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 100;
    if (a.contains(b) || b.contains(a)) return 88;

    final aTokens = a.split(' ').where((t) => t.isNotEmpty).toList();
    final bTokens = b.split(' ').where((t) => t.isNotEmpty).toList();
    if (aTokens.isEmpty || bTokens.isEmpty) return 0;

    final aSorted = List<String>.from(aTokens)..sort();
    final bSorted = List<String>.from(bTokens)..sort();
    if (aSorted.join(' ') == bSorted.join(' ')) return 92;

    final aSet = aTokens.toSet();
    final bSet = bTokens.toSet();
    final common = aSet.intersection(bSet).length;
    if (common == 0) return 0;

    final union = aSet.union(bSet).length;
    final jaccard = union == 0 ? 0.0 : common / union;
    if (jaccard >= 0.66) return 85;
    if (jaccard >= 0.5) return 78;

    final minLen = aSet.length < bSet.length ? aSet.length : bSet.length;
    final overlap = common / minLen;
    if (overlap >= 0.75) return 80;
    if (overlap >= 0.5) return 72;

    if (aTokens.length >= 2 && bTokens.length >= 2) {
      final aFirst = aTokens.first;
      final aLast = aTokens.last;
      final bFirst = bTokens.first;
      final bLast = bTokens.last;
      if ((aFirst == bFirst && aLast == bLast) ||
          (aFirst == bLast && aLast == bFirst)) {
        return 82;
      }
    }

    if (overlap >= 0.34) return 58;
    return 0;
  }

  void _collectNamesFromMap(Map<String, dynamic> map, List<String> out) {
    final full = map['fullName']?.toString().trim();
    if (full != null && full.isNotEmpty) out.add(full);

    final name = map['name']?.toString().trim();
    if (name != null && name.isNotEmpty) out.add(name);

    final first = map['firstName']?.toString().trim() ?? '';
    final middle = map['middleName']?.toString().trim() ?? '';
    final last = map['lastName']?.toString().trim() ?? '';
    final combined = [first, middle, last]
        .where((p) => p.isNotEmpty)
        .join(' ')
        .trim();
    if (combined.isNotEmpty) out.add(combined);

    for (final key in ['child', 'confirmand', 'groom', 'bride', 'deceased', 'person']) {
      final nested = map[key];
      if (nested is Map<String, dynamic>) {
        _collectNamesFromMap(nested, out);
      } else if (nested is String && nested.trim().isNotEmpty) {
        out.add(nested.trim());
      }
    }
  }

  void _addCoupleNameParts(String text, List<String> names) {
    final t = text.trim();
    if (t.isEmpty) return;
    names.add(t);
    for (final sep in [' & ', ' and ', ' AND ']) {
      if (t.contains(sep)) {
        for (final part in t.split(sep)) {
          final p = part.trim();
          if (p.length >= 2) names.add(p);
        }
        break;
      }
    }
  }

  List<_Candidate> _candidatesFromRecordData(Map<String, dynamic> data) {
    final names = <String>[];
    final text = (data['text'] ?? data['name'] ?? '').toString().trim();
    if (text.isNotEmpty) _addCoupleNameParts(text, names);

    final notes = data['notes'];
    if (notes is String && notes.trim().isNotEmpty) {
      try {
        final decoded = json.decode(notes);
        if (decoded is Map<String, dynamic>) {
          _collectNamesFromMap(decoded, names);
        }
      } catch (_) {
        if (notes.trim().length >= 2) names.add(notes.trim());
      }
    } else if (notes is Map<String, dynamic>) {
      _collectNamesFromMap(notes, names);
    }

    DateTime? dob;
    if (notes is String && notes.trim().isNotEmpty) {
      try {
        final decoded = json.decode(notes);
        if (decoded is Map<String, dynamic>) {
          for (final key in ['child', 'confirmand', 'deceased', 'person']) {
            final nested = decoded[key];
            if (nested is Map<String, dynamic>) {
              dob ??= _tryParseIsoDate(nested['dateOfBirth']);
            }
          }
        }
      } catch (_) {}
    }

    final unique = <String>{};
    final candidates = <_Candidate>[];
    for (final n in names) {
      final t = n.trim();
      if (t.length < 2 || unique.contains(t)) continue;
      unique.add(t);
      candidates.add(_Candidate(fullName: t, dateOfBirth: dob));
    }
    if (candidates.isEmpty && text.isNotEmpty) {
      candidates.add(_Candidate(fullName: text, dateOfBirth: dob));
    }
    return candidates;
  }

  DateTime? _tryParseIsoDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  Future<void> _autoLinkSacramentRecordsForMember({
    required String memberId,
    required HouseholdMember member,
  }) async {
    const limit = 400;
    final memberName = _memberDisplayName(member);
    if (memberName.isEmpty) return;

    final memberDob = member.birthDate;

    _Match? scoreCandidates(
      Iterable<_Candidate> candidates,
      String recordId,
      _Match? currentBest,
    ) {
      _Match? best = currentBest;
      for (final c in candidates) {
        final baseScore = _nameMatchScore(memberName, c.fullName);
        if (baseScore == 0) continue;

        var score = baseScore;
        final cDob = c.dateOfBirth;
        if (memberDob != null && cDob != null) {
          if (_sameYmd(memberDob, cDob)) {
            score += 15;
          } else {
            score -= 15;
          }
        }

        if (best == null || score > best.score) {
          best = _Match(
            recordId: recordId,
            score: score,
            matchedName: c.fullName,
          );
        }
      }
      return best;
    }

    Future<_Match?> findBestMatchForCollection(String collection) async {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        try {
          snap = await _firestore
              .collection(collection)
              .orderBy('created_at', descending: true)
              .limit(limit)
              .get();
        } catch (_) {
          snap = await _firestore.collection(collection).limit(limit).get();
        }
      } catch (_) {
        return null;
      }

      _Match? best;
      for (final doc in snap.docs) {
        final candidates = _candidatesFromRecordData(doc.data());
        best = scoreCandidates(candidates, doc.id, best);
      }
      return best;
    }

    Future<_Match?> findBestInLegacyRecords(String type) async {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _firestore
            .collection('records')
            .where('type', isEqualTo: type)
            .limit(limit)
            .get();
      } catch (_) {
        try {
          snap = await _firestore.collection('records').limit(limit).get();
        } catch (_) {
          return null;
        }
      }

      _Match? best;
      for (final doc in snap.docs) {
        final data = doc.data();
        final docType = (data['type'] ?? '').toString().toLowerCase();
        if (docType.isNotEmpty && docType != type) continue;
        final candidates = _candidatesFromRecordData(data);
        best = scoreCandidates(candidates, doc.id, best);
      }
      return best;
    }

    Future<_Match?> bestForSacrament(
      String typedCollection,
      String legacyType,
    ) async {
      final typed = await findBestMatchForCollection(typedCollection);
      final legacy = await findBestInLegacyRecords(legacyType);
      if (typed == null) return legacy;
      if (legacy == null) return typed;
      return typed.score >= legacy.score ? typed : legacy;
    }

    final baptismMatch = await bestForSacrament('baptism_records', 'baptism');
    final confirmationMatch =
        await bestForSacrament('confirmation_records', 'confirmation');
    final marriageMatch = await bestForSacrament('marriage_records', 'marriage');
    final funeralTyped = await bestForSacrament('funeral_records', 'funeral');
    final funeralDeath = await findBestInLegacyRecords('death');
    _Match? funeralMatch = funeralTyped;
    if (funeralDeath != null) {
      if (funeralMatch == null || funeralDeath.score > funeralMatch.score) {
        funeralMatch = funeralDeath;
      }
    }

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    const minScore = 58;
    if (baptismMatch != null && baptismMatch.score >= minScore) {
      updates['baptismRecordId'] = baptismMatch.recordId;
    }
    if (confirmationMatch != null && confirmationMatch.score >= minScore) {
      updates['confirmationRecordId'] = confirmationMatch.recordId;
    }
    if (marriageMatch != null && marriageMatch.score >= minScore) {
      updates['marriageRecordId'] = marriageMatch.recordId;
    }
    if (funeralMatch != null && funeralMatch.score >= minScore) {
      updates['deathRecordId'] = funeralMatch.recordId;
    }

    final linkedSacraments = <Map<String, dynamic>>[];
    Future<void> addSummary(
      String type,
      String collection,
      _Match? match,
    ) async {
      if (match == null || match.score < minScore) return;
      var title = match.matchedName;
      String? dateIso;
      try {
        final rec = await _firestore.collection(collection).doc(match.recordId).get();
        final data = rec.data();
        if (data != null) {
          title = (data['text'] ?? data['name'] ?? title).toString();
          final raw = data['created_at'] ?? data['createdAt'];
          final dt = _tryParseIsoDate(raw);
          if (dt != null) dateIso = dt.toIso8601String();
        }
      } catch (_) {}
      linkedSacraments.add({
        'type': type,
        'recordId': match.recordId,
        'title': title,
        'date': dateIso,
        'memberName': memberName,
      });
    }

    await addSummary('baptism', 'baptism_records', baptismMatch);
    await addSummary('confirmation', 'confirmation_records', confirmationMatch);
    await addSummary('marriage', 'marriage_records', marriageMatch);
    await addSummary('death', 'funeral_records', funeralMatch);
    updates['linkedSacraments'] = linkedSacraments;

    // Always store what we detected, even if not linked (for troubleshooting).
    final autoLinkMeta = <String, dynamic>{
      'ranAt': DateTime.now().toIso8601String(),
      'threshold': minScore,
      'baptism': baptismMatch?.toJson(),
      'confirmation': confirmationMatch?.toJson(),
      'marriage': marriageMatch?.toJson(),
      'funeral': funeralMatch?.toJson(),
    };
    updates['metadata'] = {
      ...member.metadata,
      'autoLinkedSacraments': autoLinkMeta,
    };

    await _firestore
        .collection('household_members')
        .doc(memberId)
        .update(updates);
  }

  /// Links parish sacrament records to a member (client-side; no paid Cloud Functions).
  Future<SacramentAutoLinkResult> autoLinkSacramentRecords(
    String memberId,
  ) async {
    _requireUid();
    final member = await getHouseholdMember(memberId);
    if (member == null) {
      return const SacramentAutoLinkResult(linkedCount: 0);
    }
    try {
      await _autoLinkSacramentRecordsForMember(
        memberId: memberId,
        member: member,
      );
      final refreshed = await getHouseholdMember(memberId);
      if (refreshed == null) {
        return const SacramentAutoLinkResult(linkedCount: 0);
      }
      return SacramentAutoLinkResult(
        linkedCount: _countLinkedSacraments(refreshed),
        linked: _linkedSacramentMap(refreshed),
      );
    } catch (_) {
      return const SacramentAutoLinkResult(linkedCount: 0);
    }
  }

  static int _countLinkedSacraments(HouseholdMember m) {
    var n = 0;
    if (m.baptismRecordId != null && m.baptismRecordId!.isNotEmpty) n++;
    if (m.confirmationRecordId != null &&
        m.confirmationRecordId!.isNotEmpty) {
      n++;
    }
    if (m.marriageRecordId != null && m.marriageRecordId!.isNotEmpty) n++;
    if (m.deathRecordId != null && m.deathRecordId!.isNotEmpty) n++;
    return n;
  }

  static Map<String, String> _linkedSacramentMap(HouseholdMember m) {
    final out = <String, String>{};
    if (m.baptismRecordId != null && m.baptismRecordId!.isNotEmpty) {
      out['baptism'] = m.baptismRecordId!;
    }
    if (m.confirmationRecordId != null &&
        m.confirmationRecordId!.isNotEmpty) {
      out['confirmation'] = m.confirmationRecordId!;
    }
    if (m.marriageRecordId != null && m.marriageRecordId!.isNotEmpty) {
      out['marriage'] = m.marriageRecordId!;
    }
    if (m.deathRecordId != null && m.deathRecordId!.isNotEmpty) {
      out['death'] = m.deathRecordId!;
    }
    return out;
  }

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
    final uid = _requireUid();

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
      'created_by': uid,
      'userId': uid,
    };

    final docRef = await _firestore.collection('households').add(data);
    // Return household with ID without re-fetching to avoid permission issues
    return household.copyWith(
      id: docRef.id,
      householdId: householdId,
      registeredAt: DateTime.now(),
    );
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
    final uid = _requireUid();

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
      'created_by': uid,
      'userId': uid,
    };

    final docRef = await _firestore.collection('household_members').add(data);
    final created = member.copyWith(id: docRef.id, dateAdded: DateTime.now());

    // Best-effort auto-link via Cloud Function (parishioners cannot read records).
    try {
      await autoLinkSacramentRecords(docRef.id);
    } catch (_) {}

    final refreshed = await getHouseholdMember(docRef.id);
    return refreshed ?? created;
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

    try {
      await autoLinkSacramentRecords(member.id);
    } catch (_) {}
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
  Future<void> setHeadOfFamily(
    String householdId,
    String memberId, {
    String? headName,
  }) async {
    _requireUid();
    final patch = <String, dynamic>{
      'headOfFamilyId': memberId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (headName != null && headName.trim().isNotEmpty) {
      final doc = await _firestore.collection('households').doc(householdId).get();
      final meta = Map<String, dynamic>.from(
        (doc.data()?['metadata'] as Map<String, dynamic>?) ?? {},
      );
      meta['headOfFamilyName'] = headName.trim();
      patch['metadata'] = meta;
    }
    await _firestore.collection('households').doc(householdId).update(patch);
  }

  /// Display name for admin/staff lists (metadata, linked member, or role).
  Future<String> resolveHeadOfFamilyDisplayName(Household household) async {
    final metaName = household.metadata['headOfFamilyName']?.toString().trim();
    if (metaName != null && metaName.isNotEmpty) return metaName;

    if (household.headOfFamilyId.isNotEmpty && household.id.isNotEmpty) {
      final member = await getHouseholdMember(household.headOfFamilyId);
      final name = member?.fullName.trim() ?? '';
      if (name.isNotEmpty) return name;
    }

    if (household.id.isEmpty) return '';

    try {
      final members = await listHouseholdMembers(household.id);
      if (members.isEmpty) return '';

      for (final m in members) {
        final role = m.role.trim().toLowerCase();
        if (role.contains('head') ||
            role == 'father' ||
            role == 'mother' ||
            role == 'parent') {
          final name = m.fullName.trim();
          if (name.isNotEmpty) return name;
        }
      }

      final first = members.first.fullName.trim();
      if (first.isNotEmpty) return first;
    } catch (_) {}

    // Parishioner-created households often use the head's name as family name.
    if (household.familyName.trim().isNotEmpty) {
      return household.familyName.trim();
    }

    return '';
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
