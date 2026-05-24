import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/household.dart';
import '../services/household_repository.dart';
import '../utils/record_date_filter.dart';

/// Provider for household repository
final householdRepositoryProvider = Provider<HouseholdRepository>((ref) {
  return HouseholdRepository();
});

/// Provider for list of households with optional filters
final householdsStreamProvider =
    StreamProvider.family<List<Household>, HouseholdFilter>((ref, filter) {
      final repo = ref.watch(householdRepositoryProvider);
      return repo
          .watchHouseholds(
            barangay: filter.barangay,
            includeArchived: filter.includeArchived,
            searchQuery: filter.searchQuery,
          )
          .map((list) {
            if (filter.from == null && filter.to == null) return list;
            return list
                .where(
                  (h) => RecordDateFilter.matches(
                    h.registeredAt,
                    from: filter.from,
                    to: filter.to,
                  ),
                )
                .toList();
          })
          .handleError((error) {
            // ignore: avoid_print
            print('[householdsStreamProvider] ERROR: $error');
            throw error;
          });
    });

/// Provider for single household
final householdProvider = FutureProvider.family<Household?, String>((
  ref,
  id,
) async {
  final repo = ref.watch(householdRepositoryProvider);
  return repo.getHousehold(id);
});

/// Provider for household members stream
final householdMembersStreamProvider =
    StreamProvider.family<List<HouseholdMember>, String>((ref, householdId) {
      final repo = ref.watch(householdRepositoryProvider);
      return repo.watchHouseholdMembers(householdId);
    });

/// Provider for barangays list
final barangaysProvider = FutureProvider<List<String>>((ref) async {
  final repo = ref.watch(householdRepositoryProvider);
  return repo.getBarangays();
});

/// Provider for household statistics
final householdStatsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((
      ref,
      householdId,
    ) async {
      final repo = ref.watch(householdRepositoryProvider);
      return repo.getHouseholdStats(householdId);
    });

/// Filter class for households
class HouseholdFilter {
  final String? barangay;
  final bool includeArchived;
  final String? searchQuery;
  final DateTime? from;
  final DateTime? to;

  const HouseholdFilter({
    this.barangay,
    this.includeArchived = false,
    this.searchQuery,
    this.from,
    this.to,
  });

  HouseholdFilter copyWith({
    String? barangay,
    bool? includeArchived,
    String? searchQuery,
    DateTime? from,
    DateTime? to,
  }) {
    return HouseholdFilter(
      barangay: barangay ?? this.barangay,
      includeArchived: includeArchived ?? this.includeArchived,
      searchQuery: searchQuery ?? this.searchQuery,
      from: from ?? this.from,
      to: to ?? this.to,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HouseholdFilter &&
        other.barangay == barangay &&
        other.includeArchived == includeArchived &&
        other.searchQuery == searchQuery &&
        other.from == from &&
        other.to == to;
  }

  @override
  int get hashCode =>
      Object.hash(barangay, includeArchived, searchQuery, from, to);
}

/// State notifier for household operations
class HouseholdNotifier extends AsyncNotifier<void> {
  late final HouseholdRepository _repository;

  @override
  Future<void> build() async {
    _repository = ref.read(householdRepositoryProvider);
    // Ensure the future completes to avoid infinite loading
    return;
  }

  /// Create a new household
  Future<Household?> createHousehold(Household household) async {
    state = const AsyncValue.loading();
    try {
      final created = await _repository.createHousehold(household);
      state = const AsyncValue.data(null);
      return created;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Update household
  Future<bool> updateHousehold(Household household) async {
    state = const AsyncValue.loading();
    try {
      await _repository.updateHousehold(household);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Delete household
  Future<bool> deleteHousehold(String id) async {
    state = const AsyncValue.loading();
    try {
      await _repository.deleteHousehold(id);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Archive/Unarchive household
  Future<bool> setArchiveStatus(String id, bool archived) async {
    state = const AsyncValue.loading();
    try {
      await _repository.setHouseholdArchiveStatus(id, archived);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Add member to household
  Future<HouseholdMember?> addMember(HouseholdMember member) async {
    state = const AsyncValue.loading();
    try {
      final created = await _repository.addMember(member);
      state = const AsyncValue.data(null);
      return created;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Update member
  Future<bool> updateMember(HouseholdMember member) async {
    state = const AsyncValue.loading();
    try {
      await _repository.updateMember(member);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Delete member
  Future<bool> deleteMember(String memberId) async {
    state = const AsyncValue.loading();
    try {
      await _repository.deleteMember(memberId);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Set head of family
  Future<bool> setHeadOfFamily(String householdId, String memberId) async {
    state = const AsyncValue.loading();
    try {
      await _repository.setHeadOfFamily(householdId, memberId);
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

/// Provider for household operations notifier
final householdOperationsProvider =
    AsyncNotifierProvider<HouseholdNotifier, void>(() {
      return HouseholdNotifier();
    });

/// Provider for current user's households
final myHouseholdsProvider = FutureProvider<List<Household>>((ref) async {
  final repo = ref.watch(householdRepositoryProvider);
  // This fetches households for the currently authenticated user
  // The repository handles the user ID internally via auth state
  return repo.getMyHouseholds();
});
