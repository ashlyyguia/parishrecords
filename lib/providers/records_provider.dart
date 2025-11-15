import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../models/record.dart';
import '../services/local_storage.dart';
import '../services/records_repository.dart';

class RecordsNotifier extends StateNotifier<List<ParishRecord>> {
  RecordsNotifier() : super(const []) {
    _warmStartFromHive();
    // Explicit loads are used instead of Firestore snapshots
  }

  final _repo = RecordsRepository();
  StreamSubscription<List<ParishRecord>>? _sub;

  Future<void> _warmStartFromHive() async {
    final box = Hive.box(LocalStorageService.recordsBox);
    final list = <ParishRecord>[];
    for (final key in box.keys) {
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
      
      // Handle certificate status
      final dynamic statusField = m['certificateStatusIndex'] ?? m['certificateStatus'];
      CertificateStatus certificateStatus;
      if (statusField is int) {
        certificateStatus = CertificateStatus.values[statusField];
      } else if (statusField is String) {
        certificateStatus = CertificateStatusExtension.fromString(statusField);
      } else {
        certificateStatus = CertificateStatus.pending;
      }
      
      list.add(
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
    }
    if (list.isNotEmpty) {
      state = list;
    }
  }

  Future<void> _cacheToHive(List<ParishRecord> list) async {
    final box = Hive.box(LocalStorageService.recordsBox);
    // Simple strategy: clear and repopulate
    await box.clear();
    for (final r in list) {
      await box.put(r.id, {
        'id': r.id,
        'typeIndex': r.type.index,
        'name': r.name,
        'date': r.date.toIso8601String(),
        'imagePath': r.imagePath,
        'parish': r.parish,
        'notes': r.notes,
        'certificateStatusIndex': r.certificateStatus.index,
      });
    }
  }

  Future<void> load() async {
    // Explicit refresh from backend
    final list = await _repo.list();
    state = list;
    await _cacheToHive(list);
  }

  Future<void> addRecord(
    RecordType type,
    String name,
    DateTime date, {
    String? imagePath,
    String? notes,
  }) async {
    // Add the record
    await _repo.add(type, name, date, imagePath: imagePath, notes: notes);
    
    // Force immediate UI update by reloading
    await load();
    
    // Also trigger a state change to ensure UI rebuilds
    state = [...state];
  }

  Future<void> updateRecord(
    String id, {
    RecordType? type,
    String? name,
    DateTime? date,
    String? imagePath,
    String? notes,
  }) async {
    // Update the record
    await _repo.update(
      id,
      type: type,
      name: name,
      date: date,
      imagePath: imagePath,
      notes: notes,
    );
    
    // Force immediate UI update by reloading
    await load();
    
    // Also trigger a state change to ensure UI rebuilds
    state = [...state];
  }

  Future<void> updateCertificateStatus(String id, CertificateStatus status) async {
    await _repo.updateCertificateStatus(id, status);
    await load();
    state = [...state];
  }

  Future<void> deleteRecord(String id) async {
    // Delete the record
    await _repo.delete(id);
    
    // Force immediate UI update by reloading
    await load();
    
    // Also trigger a state change to ensure UI rebuilds
    state = [...state];
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final recordsProvider =
    StateNotifierProvider<RecordsNotifier, List<ParishRecord>>((ref) {
      final n = RecordsNotifier();
      n.load();
      return n;
    });
