import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Keeps OCR register saves safe across dropped connections:
///
/// * [ocrRecordDocId] gives every reviewed row a fixed Firestore id, so a
///   retried save can't create duplicates.
/// * [OcrPendingSaveStore] keeps the reviewed rows on the device until the
///   server confirms the save, so a closed tab or crash doesn't lose them.
/// * [guardedOcrSave] stops waiting after a timeout instead of hanging, while
///   still letting the queued write finish when the connection returns.

/// Fixed document id for one reviewed row of one scan.
String ocrRecordDocId(String kind, String scanId, String rowKey) {
  String clean(String v) => v.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  return 'ocr_${clean(kind)}_${clean(scanId)}_${clean(rowKey)}';
}

enum OcrSaveOutcome {
  /// The server confirmed the save.
  saved,

  /// No answer within the timeout. The write is still queued and will
  /// finish by itself when the connection returns (see [guardedOcrSave]).
  waitingForConnection,

  /// The write was rejected or failed.
  failed,
}

class OcrSaveResult {
  const OcrSaveResult(this.outcome, {this.count = 0, this.error});

  final OcrSaveOutcome outcome;
  final int count;
  final Object? error;
}

/// Runs [write] but gives up waiting after [timeout].
///
/// On a timeout the write keeps running: when it later completes,
/// [onLateSuccess] / [onLateFailure] are called, so the screen can confirm
/// the save (or show the error) once the connection is back.
Future<OcrSaveResult> guardedOcrSave({
  required Future<int> Function() write,
  Duration timeout = const Duration(seconds: 30),
  void Function(int count)? onLateSuccess,
  void Function(Object error)? onLateFailure,
}) async {
  final Future<int> pending;
  try {
    pending = write();
  } catch (e) {
    return OcrSaveResult(OcrSaveOutcome.failed, error: e);
  }
  try {
    final count = await pending.timeout(timeout);
    return OcrSaveResult(OcrSaveOutcome.saved, count: count);
  } on TimeoutException {
    unawaited(
      pending.then(
        (count) => onLateSuccess?.call(count),
        onError: (Object e) => onLateFailure?.call(e),
      ),
    );
    return const OcrSaveResult(OcrSaveOutcome.waitingForConnection);
  } catch (e) {
    return OcrSaveResult(OcrSaveOutcome.failed, error: e);
  }
}

/// Reviewed rows of one scan, kept on the device until the save is confirmed.
class OcrPendingSave {
  const OcrPendingSave({
    required this.kind,
    required this.scanId,
    required this.savedAt,
    required this.rowCount,
    required this.state,
    this.ownerUid,
  });

  /// `baptism` or `marriage`.
  final String kind;
  final String scanId;
  final DateTime savedAt;

  /// Number of rows selected for saving.
  final int rowCount;

  /// Page-specific review state (rows, Vol./Series, warnings, ...).
  final Map<String, dynamic> state;

  /// Signed-in user who reviewed the rows. Other users on the same browser
  /// don't see it.
  final String? ownerUid;

  String get storageKey => '$kind:$scanId';

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'scanId': scanId,
    'savedAt': savedAt.toIso8601String(),
    'rowCount': rowCount,
    'ownerUid': ownerUid,
    'state': state,
  };

  static OcrPendingSave? tryParse(Object? raw) {
    try {
      final m = raw is String
          ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
          : Map<String, dynamic>.from(raw as Map);
      final state = m['state'];
      return OcrPendingSave(
        kind: (m['kind'] ?? '').toString(),
        scanId: (m['scanId'] ?? '').toString(),
        savedAt: DateTime.tryParse((m['savedAt'] ?? '').toString()) ??
            DateTime.now(),
        rowCount: m['rowCount'] is num ? (m['rowCount'] as num).toInt() : 0,
        ownerUid: m['ownerUid']?.toString(),
        state: state is Map ? Map<String, dynamic>.from(state) : const {},
      );
    } catch (_) {
      return null;
    }
  }
}

/// Where pending saves live. Every method is best effort and never throws:
/// losing the safety copy must never block the actual save.
abstract class OcrPendingSaveStore {
  Future<void> put(OcrPendingSave save);
  Future<List<OcrPendingSave>> list(String kind, {String? ownerUid});
  Future<void> remove(String kind, String scanId);
}

/// Hive (IndexedDB on the web, a file on phones) — survives a closed tab,
/// a refresh or an app restart.
class HiveOcrPendingSaveStore implements OcrPendingSaveStore {
  HiveOcrPendingSaveStore({this.boxName = 'ocr_pending_saves'});

  final String boxName;

  /// Set by main() once `Hive.initFlutter()` has run. Until then (e.g. in
  /// widget tests) the store is a no-op: opening a box before Hive is
  /// initialised fails inside Hive in a way that can't be caught here.
  static bool hiveReady = false;

  Future<Box<String>?> _box() async {
    if (!hiveReady) return null;
    try {
      if (Hive.isBoxOpen(boxName)) return Hive.box<String>(boxName);
      return await Hive.openBox<String>(boxName);
    } catch (e) {
      debugPrint('OCR pending saves unavailable: $e');
      return null;
    }
  }

  @override
  Future<void> put(OcrPendingSave save) async {
    try {
      final box = await _box();
      await box?.put(save.storageKey, jsonEncode(save.toJson()));
    } catch (e) {
      debugPrint('Could not keep OCR rows on this device: $e');
    }
  }

  @override
  Future<List<OcrPendingSave>> list(String kind, {String? ownerUid}) async {
    try {
      final box = await _box();
      if (box == null) return const [];
      return _filter(box.values.map(OcrPendingSave.tryParse), kind, ownerUid);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> remove(String kind, String scanId) async {
    try {
      final box = await _box();
      await box?.delete('$kind:$scanId');
    } catch (_) {}
  }
}

/// In-memory store, for tests.
class MemoryOcrPendingSaveStore implements OcrPendingSaveStore {
  final Map<String, OcrPendingSave> saves = {};

  @override
  Future<void> put(OcrPendingSave save) async => saves[save.storageKey] = save;

  @override
  Future<List<OcrPendingSave>> list(String kind, {String? ownerUid}) async =>
      _filter(saves.values, kind, ownerUid);

  @override
  Future<void> remove(String kind, String scanId) async =>
      saves.remove('$kind:$scanId');
}

List<OcrPendingSave> _filter(
  Iterable<OcrPendingSave?> all,
  String kind,
  String? ownerUid,
) {
  final out = all
      .whereType<OcrPendingSave>()
      .where((s) => s.kind == kind && s.scanId.isNotEmpty)
      .where((s) => ownerUid == null || s.ownerUid == null || s.ownerUid == ownerUid)
      .toList()
    ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  return out;
}
