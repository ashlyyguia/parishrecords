import 'dart:convert';

import '../models/record.dart';
import '../models/register_marriage_entry.dart';
import '../models/register_ocr_entry.dart';
import '../services/register_ocr_parser.dart';

/// JSON notes from manual baptism / marriage register pages.
class ManualRegisterNotes {
  ManualRegisterNotes._();

  static Map<String, dynamic>? tryDecode(String? notes) {
    if (notes == null || notes.trim().isEmpty) return null;
    if (!notes.trim().startsWith('{')) return null;
    try {
      final decoded = json.decode(notes);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  static bool isManualBaptismMap(Map<String, dynamic> data) {
    if (data['source'] == 'manual_marriage_register') return false;
    return data['source'] == 'manual_baptism_register' ||
        data.containsKey('nameOfChild') ||
        data.containsKey('placeAndBirthDate');
  }

  static bool isManualMarriageMap(Map<String, dynamic> data) {
    return data['source'] == 'manual_marriage_register' ||
        data.containsKey('groom') ||
        data.containsKey('contractingParties');
  }

  /// @deprecated Use [isManualBaptismMap] or [isManualMarriageMap].
  static bool isManualMap(Map<String, dynamic> data) => isManualBaptismMap(data);

  static bool isManualRecord(ParishRecord record) {
    final data = tryDecode(record.notes);
    if (data == null) return false;
    return isManualBaptismMap(data) || isManualMarriageMap(data);
  }

  static bool isManualBaptismRecord(ParishRecord record) {
    final data = tryDecode(record.notes);
    return data != null && isManualBaptismMap(data);
  }

  static bool isManualMarriageRecord(ParishRecord record) {
    final data = tryDecode(record.notes);
    return data != null && isManualMarriageMap(data);
  }

  static bool isRegisterOcrBulk(Map<String, dynamic> data) {
    return data['source'] == 'register_ocr_bulk';
  }

  /// Flat baptism register (manual or OCR bulk), not the full baptism form JSON.
  static bool usesFlatRegisterLayout(Map<String, dynamic> data) {
    return isManualBaptismMap(data) || isRegisterOcrBulk(data);
  }

  /// Flat marriage register from [StaffManualMarriagePage].
  static bool usesFlatMarriageRegisterLayout(Map<String, dynamic> data) {
    return isManualMarriageMap(data);
  }

  static String field(Map<String, dynamic> data, String key) {
    final v = data[key];
    if (v == null) return '';
    return v.toString().trim();
  }

  /// Reads the first non-empty value among [keys] (handles OCR/manual variants).
  static String fieldAny(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final v = field(data, key);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static Map<String, dynamic>? _partyMap(Map<String, dynamic> data, String key) {
    final v = data[key];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static MarriagePartyInfo _partyFromMap(
    Map<String, dynamic>? map, {
    Map<String, dynamic>? legacy,
    required bool isGroom,
  }) {
    if (map != null) {
      return MarriagePartyInfo(
        name: fieldAny(map, ['name', 'contractingParties']),
        legalStatus: field(map, 'legalStatus'),
        actualAddress: fieldAny(map, ['actualAddress', 'address']),
        datesPlaceOfBirth: fieldAny(map, [
          'datesPlaceOfBirth',
          'datesAndPlaceOfBirth',
        ]),
        datesPlaceOfBaptism: fieldAny(map, [
          'datesPlaceOfBaptism',
          'datesAndPlaceOfBaptism',
        ]),
        parents: field(map, 'parents'),
        sponsors: fieldAny(map, ['sponsors', 'sponsorsOfMarriage']),
      );
    }

    if (legacy == null) return MarriagePartyInfo();

    // Old single-row saves: put combined text on groom only.
    if (isGroom) {
      return MarriagePartyInfo(
        name: field(legacy, 'contractingParties'),
        legalStatus: field(legacy, 'legalStatus'),
        actualAddress: field(legacy, 'actualAddress'),
        datesPlaceOfBirth: fieldAny(legacy, [
          'datesPlaceOfBirth',
          'datesAndPlaceOfBirth',
        ]),
        datesPlaceOfBaptism: fieldAny(legacy, [
          'datesPlaceOfBaptism',
          'datesAndPlaceOfBaptism',
        ]),
        parents: field(legacy, 'parents'),
        sponsors: fieldAny(legacy, ['sponsors', 'sponsorsOfMarriage']),
      );
    }
    return MarriagePartyInfo();
  }

  static Map<String, dynamic> _partyToMap(MarriagePartyInfo party) {
    return {
      'name': party.name.trim(),
      'legalStatus': party.legalStatus,
      'actualAddress': party.actualAddress,
      'datesPlaceOfBirth': party.datesPlaceOfBirth,
      'datesPlaceOfBaptism': party.datesPlaceOfBaptism,
      'parents': party.parents,
      'sponsors': party.sponsors,
    };
  }

  static RegisterOcrEntry entryFromMap(
    Map<String, dynamic> data, {
    String? id,
  }) {
    return RegisterOcrEntry(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: field(data, 'nameOfChild'),
      lineNo: field(data, 'lineNo').isEmpty ? null : field(data, 'lineNo'),
      placeAndBirthDate: field(data, 'placeAndBirthDate'),
      parents: parentsText(data),
      residentsOf: field(data, 'residentsOf'),
      baptismDateText: field(data, 'dateOfBaptism'),
      minister: field(data, 'minister'),
      sponsors: field(data, 'sponsors'),
      rawLine: field(data, 'rawLine'),
      selected: true,
    );
  }

  static String parentsText(Map<String, dynamic> data) {
    return _parentsValue(data['parents']);
  }

  static String _parentsValue(dynamic parents) {
    if (parents is String) return parents.trim();
    if (parents is Map) {
      final father = parents['father']?.toString().trim() ?? '';
      final mother = parents['mother']?.toString().trim() ?? '';
      if (father.isNotEmpty && mother.isNotEmpty) {
        return '$father / $mother';
      }
      return father.isNotEmpty ? father : mother;
    }
    return '';
  }

  static Map<String, dynamic> toNotesMap({
    required String volNo,
    required String seriesNo,
    required RegisterOcrEntry entry,
    String status = 'temporary',
  }) {
    return {
      'source': 'manual_baptism_register',
      'status': status,
      'sacramentType': 'baptism',
      'volNo': volNo,
      'seriesNo': seriesNo,
      'lineNo': entry.lineNo,
      'nameOfChild': entry.name.trim(),
      'placeAndBirthDate': entry.placeAndBirthDate,
      'parents': entry.parents,
      'residentsOf': entry.residentsOf,
      'dateOfBaptism': entry.baptismDateText,
      'minister': entry.minister,
      'sponsors': entry.sponsors,
      'rawLine': entry.rawLine,
    };
  }

  static RegisterMarriageEntry marriageEntryFromMap(
    Map<String, dynamic> data, {
    String? id,
  }) {
    return RegisterMarriageEntry(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      lineNo: field(data, 'lineNo').isEmpty ? null : field(data, 'lineNo'),
      groom: _partyFromMap(_partyMap(data, 'groom'), legacy: data, isGroom: true),
      bride: _partyFromMap(_partyMap(data, 'bride'), legacy: data, isGroom: false),
      dateOfMarriage: field(data, 'dateOfMarriage'),
      minister: field(data, 'minister'),
      licenseNumber: fieldAny(data, ['licenseNumber', 'licenceNumber']),
      observations: field(data, 'observations'),
      selected: true,
    );
  }

  static Map<String, dynamic> toMarriageNotesMap({
    required String volNo,
    required String seriesNo,
    required RegisterMarriageEntry entry,
    String status = 'temporary',
  }) {
    return {
      'source': 'manual_marriage_register',
      'status': status,
      'sacramentType': 'marriage',
      'volNo': volNo,
      'seriesNo': seriesNo,
      'lineNo': entry.lineNo,
      'groom': _partyToMap(entry.groom),
      'bride': _partyToMap(entry.bride),
      'dateOfMarriage': entry.dateOfMarriage,
      'minister': entry.minister,
      'licenseNumber': entry.licenseNumber,
      'observations': entry.observations,
      // Summary for search / list display
      'contractingParties': entry.recordDisplayName,
    };
  }

  static DateTime marriageDateForEntry(RegisterMarriageEntry entry) {
    final parsed = RegisterOcrParser.parseDate(entry.dateOfMarriage);
    return parsed ?? DateTime.now();
  }
}
