import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../config/backend.dart';
import '../models/record.dart';
import 'local_storage.dart';
import 'sync_service.dart';

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
    final name = (r['text'] as String?) ?? 'Unnamed Record';
    final typeStr = (r['type'] as String?)?.toLowerCase() ?? 'baptism';
    final type = RecordType.values.firstWhere(
      (e) => e.name.toLowerCase() == typeStr,
      orElse: () => RecordType.baptism,
    );
    return ParishRecord(
      id: (r['id'] as String?) ?? (r['record_id'] as String?) ?? '',
      type: type,
      name: name,
      date: date,
      imagePath: r['image_ref'] as String?,
      parish: null,
      notes: r['source'] as String?,
    );
  }

  Future<Map<String, String>> _authHeader() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    final token = await user.getIdToken();
    return { 'Authorization': 'Bearer $token', 'Content-Type': 'application/json' };
  }

  Future<List<ParishRecord>> list() async {
    List<ParishRecord> records = [];
    
    // First, try to load from backend
    try {
      final headers = await _authHeader();
      final resp = await http.get(Uri.parse('$_base/api/records'), headers: headers);
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        final rows = (body['rows'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        records = rows.map(_fromBackend).toList();
      }
    } catch (e) {
      developer.log('Backend load failed: $e', name: 'RecordsRepository');
    }
    
    // Also load from local storage and merge
    final box = Hive.box(LocalStorageService.recordsBox);
    final localRecords = <ParishRecord>[];
    
    for (final key in box.keys) {
      try {
        final m = box.get(key) as Map;
        final dynamic typeField = m['typeIndex'] ?? m['type'];
        RecordType type;
        if (typeField is int) {
          type = RecordType.values[typeField];
        } else if (typeField is String) {
          type = RecordType.values.firstWhere(
            (e) => e.name.toLowerCase() == typeField.toLowerCase(),
            orElse: () => RecordType.baptism,
          );
        } else {
          type = RecordType.baptism;
        }
        
        // Parse certificate status
        CertificateStatus certificateStatus = CertificateStatus.pending;
        final statusField = m['certificateStatus'];
        if (statusField is int && statusField < CertificateStatus.values.length) {
          certificateStatus = CertificateStatus.values[statusField];
        } else if (statusField is String) {
          certificateStatus = CertificateStatus.values.firstWhere(
            (e) => e.name.toLowerCase() == statusField.toLowerCase(),
            orElse: () => CertificateStatus.pending,
          );
        }
        
        localRecords.add(
          ParishRecord(
            id: m['id'],
            type: type,
            name: m['name'],
            date: DateTime.parse(m['date']),
            imagePath: m['imagePath'],
            parish: m['parish'] as String?,
            notes: m['notes'] as String?,
            certificateStatus: certificateStatus,
          ),
        );
      } catch (e) {
        developer.log('Error loading local record: $e', name: 'RecordsRepository');
      }
    }
    
    // Merge records (backend takes precedence, but include local-only records)
    final allRecords = <String, ParishRecord>{};
    
    // Add local records first
    for (final record in localRecords) {
      allRecords[record.id] = record;
    }
    
    // Add/override with backend records
    for (final record in records) {
      allRecords[record.id] = record;
    }
    
    return allRecords.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  Stream<List<ParishRecord>> watch({Duration interval = const Duration(seconds: 5)}) {
    return Stream.periodic(interval).asyncMap((_) => list()).distinct((a, b) => a.length == b.length);
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
    // Optimistic local write
    final box = Hive.box(LocalStorageService.recordsBox);
    final localId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
    await box.put(localId, {
      'id': localId,
      'typeIndex': type.index,
      'name': trimmedName,
      'date': date.toIso8601String(),
      'imagePath': imagePath,
      'parish': parish,
      'notes': notes,
      'certificateStatus': CertificateStatus.pending.index,
    });

    // Enqueue sync op
    await SyncService.enqueue('create_record', {
      'type': type.name,
      'text': trimmedName,
      'source': parish ?? 'app',
      'image_ref': imagePath,
      'client_id': localId,
    });

    // Best-effort remote try (non-fatal)
    try {
      final headers = await _authHeader();
      final payload = {
        'type': type.name,
        'text': trimmedName,
        'source': parish ?? 'app',
        'image_ref': imagePath,
      };
      final response = await http.post(Uri.parse('$_base/api/records'), headers: headers, body: json.encode(payload));
      if (response.statusCode == 200) {
        developer.log('Record saved to backend successfully', name: 'RecordsRepository');
      } else {
        developer.log('Backend add failed: ${response.statusCode} ${response.body}', name: 'RecordsRepository');
      }
    } catch (e) {
      developer.log('Backend save error: $e', name: 'RecordsRepository');
      // ignore; will be synced later
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
    // Optimistic local update
    final box = Hive.box(LocalStorageService.recordsBox);
    final existing = box.get(id) as Map?;
    if (existing != null) {
      existing['typeIndex'] = type?.index ?? existing['typeIndex'];
      existing['name'] = name ?? existing['name'];
      existing['date'] = (date ?? DateTime.parse(existing['date'])).toIso8601String();
      existing['imagePath'] = imagePath ?? existing['imagePath'];
      existing['parish'] = parish ?? existing['parish'];
      existing['notes'] = notes ?? existing['notes'];
      await box.put(id, existing);
    }

    // Enqueue sync op
    final data = <String, dynamic>{};
    if (type != null) data['type'] = type.name;
    if (name != null) data['text'] = name;
    if (imagePath != null) data['image_ref'] = imagePath;
    if (parish != null) data['source'] = parish;
    if (data.isNotEmpty) {
      await SyncService.enqueue('update_record', {
        'id': id,
        ...data,
      });
    }

    // Best-effort remote update with logging
    try {
      final headers = await _authHeader();
      if (data.isNotEmpty) {
        final response = await http.put(Uri.parse('$_base/api/records/$id'), headers: headers, body: json.encode(data));
        if (response.statusCode == 200) {
          developer.log('Record updated in backend successfully', name: 'RecordsRepository');
        } else {
          developer.log('Backend update failed: ${response.statusCode} ${response.body}', name: 'RecordsRepository');
        }
      }
    } catch (e) {
      developer.log('Backend update error: $e', name: 'RecordsRepository');
      // Will be synced later
    }
  }

  Future<void> updateCertificateStatus(String id, CertificateStatus status) async {
    // Update local storage
    final box = Hive.box(LocalStorageService.recordsBox);
    final existing = box.get(id) as Map?;
    if (existing != null) {
      existing['certificateStatus'] = status.index;
      await box.put(id, existing);
    }

    // Enqueue sync operation (if backend supports it)
    await SyncService.enqueue('update_certificate_status', {
      'id': id,
      'status': status.name,
    });

    // Best-effort remote update
    try {
      final headers = await _authHeader();
      final response = await http.put(
        Uri.parse('$_base/api/records/$id/certificate-status'),
        headers: headers,
        body: json.encode({'status': status.name}),
      );
      if (response.statusCode == 200) {
        developer.log('Certificate status updated in backend', name: 'RecordsRepository');
      } else {
        developer.log('Backend certificate status update failed: ${response.statusCode}', name: 'RecordsRepository');
      }
    } catch (e) {
      developer.log('Backend certificate status update error: $e', name: 'RecordsRepository');
    }
  }

  Future<void> delete(String id) async {
    // Optimistic local delete
    final box = Hive.box(LocalStorageService.recordsBox);
    await box.delete(id);

    // Enqueue sync operation
    await SyncService.enqueue('delete_record', { 'id': id });

    // Best-effort remote delete with logging
    try {
      final headers = await _authHeader();
      final response = await http.delete(Uri.parse('$_base/api/records/$id'), headers: headers);
      if (response.statusCode == 200) {
        developer.log('Record deleted from backend successfully', name: 'RecordsRepository');
      } else {
        developer.log('Backend delete failed: ${response.statusCode} ${response.body}', name: 'RecordsRepository');
      }
    } catch (e) {
      developer.log('Backend delete error: $e', name: 'RecordsRepository');
      // Will be synced later
    }
  }
}
