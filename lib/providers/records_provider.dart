import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/record.dart';
import '../services/records_repository.dart';

class RecordsNotifier extends StateNotifier<List<ParishRecord>> {
  RecordsNotifier() : super(const []);

  final _repo = RecordsRepository();
  StreamSubscription<List<ParishRecord>>? _sub;

  Future<void> load() async {
    // Explicit refresh from backend only
    final list = await _repo.list();
    state = list;
  }

  Future<void> addRecord(
    RecordType type,
    String name,
    DateTime date, {
    String? imagePath,
    String? parish,
    String? notes,
  }) async {
    // Add the record
    await _repo.add(
      type,
      name,
      date,
      imagePath: imagePath,
      parish: parish,
      notes: notes,
    );

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

  Future<void> updateCertificateStatus(
    String id,
    CertificateStatus status,
  ) async {
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
