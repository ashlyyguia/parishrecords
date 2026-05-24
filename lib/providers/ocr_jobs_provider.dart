import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/ocr_jobs_repository.dart';

final ocrJobsRepositoryProvider = Provider<OcrJobsRepository>((ref) {
  return OcrJobsRepository();
});

final ocrJobsAssignedToMeProvider = FutureProvider.family
    .autoDispose<List<Map<String, dynamic>>, int>((ref, limit) async {
      final repo = ref.watch(ocrJobsRepositoryProvider);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        return const <Map<String, dynamic>>[];
      }
      try {
        final result = await repo
            .listAssignedTo(uid, limit: limit)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                debugPrint('ocrJobsAssignedToMeProvider: Timeout after 10s');
                return <Map<String, dynamic>>[];
              },
            );
        return result;
      } catch (e) {
        debugPrint('ocrJobsAssignedToMeProvider error: $e');
        return <Map<String, dynamic>>[];
      }
    });

final ocrJobsUnassignedProvider = FutureProvider.family
    .autoDispose<List<Map<String, dynamic>>, int>((ref, limit) async {
      final repo = ref.watch(ocrJobsRepositoryProvider);
      try {
        final result = await repo
            .listUnassigned(limit: limit)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                debugPrint('ocrJobsUnassignedProvider: Timeout after 10s');
                return <Map<String, dynamic>>[];
              },
            );
        return result;
      } catch (e) {
        debugPrint('ocrJobsUnassignedProvider error: $e');
        return <Map<String, dynamic>>[];
      }
    });

final ocrJobsAssignedProvider = FutureProvider.family
    .autoDispose<List<Map<String, dynamic>>, int>((ref, limit) async {
      final repo = ref.watch(ocrJobsRepositoryProvider);
      try {
        final result = await repo
            .listAssigned(limit: limit)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                debugPrint('ocrJobsAssignedProvider: Timeout after 10s');
                return <Map<String, dynamic>>[];
              },
            );
        return result;
      } catch (e) {
        debugPrint('ocrJobsAssignedProvider error: $e');
        return <Map<String, dynamic>>[];
      }
    });

final ocrJobsAllProvider = FutureProvider.family
    .autoDispose<List<Map<String, dynamic>>, int>((ref, limit) async {
      final repo = ref.watch(ocrJobsRepositoryProvider);
      try {
        final result = await repo
            .listAll(limit: limit)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                debugPrint('ocrJobsAllProvider: Timeout after 10s');
                return <Map<String, dynamic>>[];
              },
            );
        return result;
      } catch (e) {
        debugPrint('ocrJobsAllProvider error: $e');
        return <Map<String, dynamic>>[];
      }
    });
