import 'dart:convert';
import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../config/backend.dart';
import '../models/record.dart';

class RecordsRepository {
  String get _base => BackendConfig.baseUrl;

  ParishRecord _fromBackend(Map<String, dynamic> r) {
    final createdAt = r['created_at'];
    DateTime date;
    if (createdAt is String) {
      date = DateTime.tryParse(createdAt) ?? DateTime.now();
    } else if (createdAt is DateTime) {
      date = createdAt;
    } else {
      date = DateTime.now();
    }
    final name =
        (r['text'] as String?) ?? (r['name'] as String?) ?? 'Unnamed Record';
    final typeStr = (r['type'] as String?)?.toLowerCase() ?? 'baptism';
    final type = () {
      switch (typeStr) {
        case 'marriage':
          return RecordType.marriage;
        case 'funeral':
        case 'death':
          return RecordType.funeral;
        case 'confirmation':
          return RecordType.confirmation;
        case 'baptism':
        default:
          return RecordType.baptism;
      }
    }();
    CertificateStatus certificateStatus = CertificateStatus.pending;
    final rawStatus = r['certificate_status'] ?? r['certificateStatus'];
    if (rawStatus is String) {
      certificateStatus = CertificateStatusExtension.fromString(rawStatus);
    } else if (rawStatus is int &&
        rawStatus < CertificateStatus.values.length) {
      certificateStatus = CertificateStatus.values[rawStatus];
    }
    final notes = (r['notes'] as String?) ?? (r['source'] as String?);

    return ParishRecord(
      id: (r['id'] as String?) ?? (r['record_id'] as String?) ?? '',
      type: type,
      name: name,
      date: date,
      imagePath: r['image_ref'] as String?,
      parish: r['parish'] as String?,
      notes: notes,
      certificateStatus: certificateStatus,
    );
  }

  Map<String, dynamic>? _buildBaptismData(String? notesJson) {
    if (notesJson == null || notesJson.isEmpty) return null;
    try {
      final decoded = json.decode(notesJson) as Map<String, dynamic>;
      final registry = (decoded['registry'] as Map<String, dynamic>?) ?? {};
      final child = (decoded['child'] as Map<String, dynamic>?) ?? {};
      final parents = (decoded['parents'] as Map<String, dynamic>?) ?? {};
      final godparents = (decoded['godparents'] as Map<String, dynamic>?) ?? {};
      final baptism = (decoded['baptism'] as Map<String, dynamic>?) ?? {};
      final metadata = (decoded['metadata'] as Map<String, dynamic>?) ?? {};

      return {
        'registryNo': registry['registryNo']?.toString(),
        'bookNo': registry['bookNo']?.toString(),
        'pageNo': registry['pageNo']?.toString(),
        'lineNo': registry['lineNo']?.toString(),
        'childName': child['fullName']?.toString(),
        'childGender': child['gender']?.toString(),
        'dateOfBirth': child['dateOfBirth']?.toString(),
        'placeOfBirth': child['placeOfBirth']?.toString(),
        'fatherName': parents['father']?.toString(),
        'motherName': parents['mother']?.toString(),
        'godfatherName': godparents['godfather1']?.toString(),
        'godmotherName': godparents['godmother1']?.toString(),
        'ministerName': baptism['minister']?.toString(),
        'dateOfBaptism': baptism['date']?.toString(),
        'placeOfBaptism': baptism['place']?.toString(),
        'certificateIssued': metadata['certificateIssued'] == true,
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _buildMarriageData(String? notesJson) {
    if (notesJson == null || notesJson.isEmpty) return null;
    try {
      final decoded = json.decode(notesJson) as Map<String, dynamic>;
      final marriage = (decoded['marriage'] as Map<String, dynamic>?) ?? {};
      final groom = (decoded['groom'] as Map<String, dynamic>?) ?? {};
      final bride = (decoded['bride'] as Map<String, dynamic>?) ?? {};
      final witnesses = (decoded['witnesses'] as Map<String, dynamic>?) ?? {};

      return {
        'registryNo': null,
        'groomName': groom['fullName']?.toString(),
        'brideName': bride['fullName']?.toString(),
        'dateOfMarriage': marriage['date']?.toString(),
        'placeOfMarriage': marriage['place']?.toString(),
        'witness1Name': witnesses['witness1']?.toString(),
        'witness2Name': witnesses['witness2']?.toString(),
        'ministerName': marriage['officiant']?.toString(),
        'certificateIssued': false,
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _buildConfirmationData(String? notesJson) {
    if (notesJson == null || notesJson.isEmpty) return null;
    try {
      final decoded = json.decode(notesJson) as Map<String, dynamic>;
      final confirmand = (decoded['confirmand'] as Map<String, dynamic>?) ?? {};
      final sponsor = (decoded['sponsor'] as Map<String, dynamic>?) ?? {};
      final confirmation =
          (decoded['confirmation'] as Map<String, dynamic>?) ?? {};

      return {
        'registryNo': null,
        'confirmedName': confirmand['fullName']?.toString(),
        'dateOfConfirmation': confirmation['date']?.toString(),
        'placeOfConfirmation': confirmation['place']?.toString(),
        'sponsorName': sponsor['fullName']?.toString(),
        'ministerName': confirmation['officiant']?.toString(),
        'certificateIssued': false,
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _buildDeathData(String? notesJson) {
    if (notesJson == null || notesJson.isEmpty) return null;
    try {
      final decoded = json.decode(notesJson) as Map<String, dynamic>;
      final deceased = (decoded['deceased'] as Map<String, dynamic>?) ?? {};
      final burial = (decoded['burial'] as Map<String, dynamic>?) ?? {};

      return {
        'registryNo': null,
        'deceasedName': deceased['fullName']?.toString(),
        'dateOfDeath': deceased['dateOfDeath']?.toString(),
        'placeOfDeath': deceased['placeOfDeath']?.toString(),
        'causeOfDeath': deceased['causeOfDeath']?.toString(),
        'ageAtDeath': deceased['age']?.toString(),
        'burialDate': burial['date']?.toString(),
        'burialPlace': burial['place']?.toString(),
        'certificateIssued': false,
      };
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> _authHeader() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<List<ParishRecord>> list() async {
    try {
      final headers = await _authHeader();
      final resp = await http.get(
        Uri.parse('$_base/api/records'),
        headers: headers,
      );
      if (resp.statusCode != 200) {
        throw Exception(
          'Failed to load records: ${resp.statusCode} ${resp.body}',
        );
      }
      final body = json.decode(resp.body) as Map<String, dynamic>;
      final rows = (body['rows'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final records = rows.map(_fromBackend).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return records;
    } catch (e) {
      developer.log('Backend load failed: $e', name: 'RecordsRepository');
      rethrow;
    }
  }

  Stream<List<ParishRecord>> watch({
    Duration interval = const Duration(seconds: 5),
  }) {
    return Stream.periodic(
      interval,
    ).asyncMap((_) => list()).distinct((a, b) => a.length == b.length);
  }

  Future<void> add(
    RecordType type,
    String name,
    DateTime date, {
    String? imagePath,
    String? parish,
    String? notes,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Record name cannot be empty');
    }

    final payload = <String, dynamic>{
      'type': type.name,
      'text': trimmedName,
      'source': parish ?? 'app',
      'image_ref': imagePath,
    };
    if (notes != null) {
      payload['notes'] = notes;
      Map<String, dynamic>? extra;
      switch (type) {
        case RecordType.baptism:
          extra = _buildBaptismData(notes);
          if (extra != null) payload['baptismData'] = extra;
          break;
        case RecordType.marriage:
          extra = _buildMarriageData(notes);
          if (extra != null) payload['marriageData'] = extra;
          break;
        case RecordType.confirmation:
          extra = _buildConfirmationData(notes);
          if (extra != null) payload['confirmationData'] = extra;
          break;
        case RecordType.funeral:
          extra = _buildDeathData(notes);
          if (extra != null) payload['deathData'] = extra;
          break;
      }
    }

    final headers = await _authHeader();
    final response = await http.post(
      Uri.parse('$_base/api/records'),
      headers: headers,
      body: json.encode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      developer.log(
        'Backend add failed: ${response.statusCode} ${response.body}',
        name: 'RecordsRepository',
      );
      throw Exception('Failed to save record: ${response.statusCode}');
    }
  }

  Future<void> update(
    String id, {
    RecordType? type,
    String? name,
    DateTime? date,
    String? imagePath,
    String? parish,
    String? notes,
  }) async {
    final data = <String, dynamic>{};
    if (type != null) data['type'] = type.name;
    if (name != null) data['text'] = name;
    if (imagePath != null) data['image_ref'] = imagePath;
    if (parish != null) data['source'] = parish;
    if (notes != null) data['notes'] = notes;
    if (data.isEmpty) return;

    final headers = await _authHeader();
    final response = await http.put(
      Uri.parse('$_base/api/records/$id'),
      headers: headers,
      body: json.encode(data),
    );
    if (response.statusCode != 200) {
      developer.log(
        'Backend update failed: ${response.statusCode} ${response.body}',
        name: 'RecordsRepository',
      );
      throw Exception('Failed to update record: ${response.statusCode}');
    }
  }

  Future<void> updateCertificateStatus(
    String id,
    CertificateStatus status,
  ) async {
    final headers = await _authHeader();
    final response = await http.put(
      Uri.parse('$_base/api/records/$id/certificate-status'),
      headers: headers,
      body: json.encode({'status': status.name}),
    );
    if (response.statusCode != 200) {
      developer.log(
        'Backend certificate status update failed: ${response.statusCode}',
        name: 'RecordsRepository',
      );
      throw Exception(
        'Failed to update certificate status: ${response.statusCode}',
      );
    }
  }

  Future<void> delete(String id) async {
    final headers = await _authHeader();
    final response = await http.delete(
      Uri.parse('$_base/api/records/$id'),
      headers: headers,
    );
    if (response.statusCode != 200) {
      developer.log(
        'Backend delete failed: ${response.statusCode} ${response.body}',
        name: 'RecordsRepository',
      );
      throw Exception('Failed to delete record: ${response.statusCode}');
    }
  }
}
