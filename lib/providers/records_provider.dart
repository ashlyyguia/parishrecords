import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/record.dart';
import '../services/records_repository.dart';
import '../services/offline_cache.dart';
import 'auth_provider.dart';

Map<String, dynamic> _recordToJson(ParishRecord r) {
  return {
    'id': r.id,
    'type': r.type.name,
    'name': r.name,
    'date': r.date.toIso8601String(),
    'imagePath': r.imagePath,
    'parish': r.parish,
    'notes': r.notes,
    'certificateStatus': r.certificateStatus.name,
  };
}

ParishRecord? _recordFromJson(dynamic raw) {
  if (raw is! Map) return null;
  final m = raw.cast<String, dynamic>();
  final id = (m['id'] ?? '').toString();
  if (id.isEmpty) return null;
  final type = RecordTypeExtension.fromString((m['type'] ?? '').toString());
  final name = (m['name'] ?? '').toString();
  final date =
      DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now();
  final cs = CertificateStatusExtension.fromString(
    (m['certificateStatus'] ?? '').toString(),
  );
  return ParishRecord(
    id: id,
    type: type,
    name: name,
    date: date,
    imagePath: m['imagePath']?.toString(),
    parish: m['parish']?.toString(),
    notes: m['notes']?.toString(),
    certificateStatus: cs,
  );
}

class RecordsNotifier extends Notifier<List<ParishRecord>> {
  final _repo = RecordsRepository();
  StreamSubscription<List<ParishRecord>>? _sub;
  Timer? _retryTimer;

  bool _isLoading = false;
  bool _hasLoadedOnce = false;
  Object? _lastError;
  bool _isOffline = false;
  String? _cacheKey;

  bool get isLoading => _isLoading;
  bool get hasLoadedOnce => _hasLoadedOnce;
  Object? get lastError => _lastError;
  bool get isOffline => _isOffline;

  @override
  List<ParishRecord> build() {
    ref.onDispose(() {
      _sub?.cancel();
      _retryTimer?.cancel();
    });

    // Mirror the old provider behavior: when auth changes, update cache key and reload.
    ref.listen<AuthState>(authProvider, (prev, next) {
      final prevId = prev?.user?.id;
      final nextId = next.user?.id;

      if (nextId == null) {
        setUser(null);
        clear();
        return;
      }

      if (prevId != nextId) {
        setUser(nextId);
        unawaited(loadCached().catchError((_) {}));
        unawaited(load().catchError((_) {}));
      }
    });

    final auth = ref.read(authProvider);
    if (auth.initialized && auth.user != null) {
      setUser(auth.user!.id);
      unawaited(loadCached().catchError((_) {}));
      unawaited(load().catchError((_) {}));
    }

    return const [];
  }

  void setUser(String? uid) {
    _cacheKey = uid == null ? null : 'records_$uid';
  }

  Future<void> loadCached() async {
    final key = _cacheKey;
    if (key == null) return;

    final raw = await OfflineCache.readJson(key);
    if (raw is! List) return;
    final list = raw.map(_recordFromJson).whereType<ParishRecord>().toList();
    if (list.isEmpty) return;

    state = list;
    _hasLoadedOnce = true;
    state = [...state];
  }

  Future<void> load() async {
    _retryTimer?.cancel();
    _isLoading = true;
    _lastError = null;
    state = [...state];
    try {
      // Explicit refresh from backend only
      final list = await _repo.list();
      state = list;
      _isOffline = false;
      final key = _cacheKey;
      if (key != null) {
        await OfflineCache.writeJson(key, list.map(_recordToJson).toList());
      }
    } catch (e) {
      _lastError = e;
      _isOffline = true;
      if (state.isEmpty) {
        await loadCached();
      }
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
    _isOffline = false;
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
  final bool isOffline;

  const RecordsMeta({
    required this.isLoading,
    required this.hasLoadedOnce,
    this.lastError,
    required this.isOffline,
  });
}

final recordsMetaProvider = Provider<RecordsMeta>((ref) {
  ref.watch(recordsProvider);
  final n = ref.read(recordsProvider.notifier);
  return RecordsMeta(
    isLoading: n.isLoading,
    hasLoadedOnce: n.hasLoadedOnce,
    lastError: n.lastError,
    isOffline: n.isOffline,
  );
});
