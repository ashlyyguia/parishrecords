import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/record.dart';
import '../services/records_repository.dart';
import 'auth_provider.dart';

class RecordsNotifier extends Notifier<List<ParishRecord>> {
  final _repo = RecordsRepository();
  StreamSubscription<List<ParishRecord>>? _sub;
  Timer? _retryTimer;

  bool _isLoading = false;
  bool _hasLoadedOnce = false;
  Object? _lastError;

  bool get isLoading => _isLoading;
  bool get hasLoadedOnce => _hasLoadedOnce;
  Object? get lastError => _lastError;

  @override
  List<ParishRecord> build() {
    ref.onDispose(() {
      _sub?.cancel();
      _retryTimer?.cancel();
    });

    // Mirror the old provider behavior: when auth changes, reload.
    ref.listen<AuthState>(authProvider, (prev, next) {
      final prevId = prev?.user?.id;
      final nextId = next.user?.id;

      if (nextId == null) {
        clear();
        return;
      }

      if (prevId != nextId) {
        unawaited(load().catchError((_) {}));
      }
    });

    final auth = ref.read(authProvider);
    if (auth.initialized && auth.user != null) {
      unawaited(load().catchError((_) {}));
    }

    return const [];
  }

  Future<void> load() async {
    _retryTimer?.cancel();
    _isLoading = true;
    _lastError = null;
    state = [...state];
    try {
      final list = await _repo.list();
      state = list;
    } catch (e) {
      _lastError = e;
      _retryTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
        if (_isLoading) return;
        await load();
      });
    } finally {
      _isLoading = false;
      _hasLoadedOnce = true;
      state = [...state];
    }
  }

  void clear() {
    _retryTimer?.cancel();
    _isLoading = false;
    _hasLoadedOnce = false;
    _lastError = null;
    state = const [];
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
    final rec = state
        .where((r) => r.id == id)
        .cast<ParishRecord?>()
        .firstOrNull;
    if (rec == null) {
      throw Exception('Record not found');
    }
    await _repo.updateCertificateStatusForType(id, rec.type, status);
    await load();
    state = [...state];
  }

  Future<void> deleteRecord(String id) async {
    final rec = state
        .where((r) => r.id == id)
        .cast<ParishRecord?>()
        .firstOrNull;
    if (rec == null) {
      throw Exception('Record not found');
    }
    await _repo.deleteForType(id, rec.type);

    // Force immediate UI update by reloading
    await load();

    // Also trigger a state change to ensure UI rebuilds
    state = [...state];
  }
}

final recordsProvider = NotifierProvider<RecordsNotifier, List<ParishRecord>>(
  RecordsNotifier.new,
);

class RecordsMeta {
  final bool isLoading;
  final bool hasLoadedOnce;
  final Object? lastError;

  const RecordsMeta({
    required this.isLoading,
    required this.hasLoadedOnce,
    this.lastError,
  });
}

final recordsMetaProvider = Provider<RecordsMeta>((ref) {
  ref.watch(recordsProvider);
  final n = ref.read(recordsProvider.notifier);
  return RecordsMeta(
    isLoading: n.isLoading,
    hasLoadedOnce: n.hasLoadedOnce,
    lastError: n.lastError,
  );
});

final recordsRepositoryProvider = Provider<RecordsRepository>((ref) {
  return RecordsRepository();
});
