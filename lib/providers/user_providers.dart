import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

import '../services/user_dashboard_repository.dart';
import '../services/user_profile_repository.dart';
import '../services/user_requests_repository.dart';
import '../services/user_sacraments_repository.dart';

final userDashboardRepositoryProvider = Provider<UserDashboardRepository>((ref) {
  return UserDashboardRepository();
});

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileRepository();
});

final userRequestsRepositoryProvider = Provider<UserRequestsRepository>((ref) {
  return UserRequestsRepository();
});

final userSacramentsRepositoryProvider = Provider<UserSacramentsRepository>((ref) {
  return UserSacramentsRepository();
});

/// The signed-in user's uid. Every per-user provider below watches this so
/// its cached data is thrown away and refetched when a different account
/// signs in (otherwise the previous account's profile could still show).
final currentUidProvider = Provider<String?>((ref) {
  return ref.watch(authProvider.select((s) => s.user?.id));
});

final myDashboardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(currentUidProvider);
  // Keep dashboard stats cached while navigating within the user shell.
  ref.keepAlive();
  return ref.read(userDashboardRepositoryProvider).getMyDashboard();
});

final myProfileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(currentUidProvider);
  return ref.read(userProfileRepositoryProvider).getMyProfile();
});

final myRequestsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUidProvider);
  return ref.read(userRequestsRepositoryProvider).listMyRequests();
});

final requestDetailProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  ref.watch(currentUidProvider);
  return ref.read(userRequestsRepositoryProvider).getRequestDetail(id);
});

final mySacramentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUidProvider);
  return ref.read(userSacramentsRepositoryProvider).listMine();
});

final hasLinkedSacramentsProvider = FutureProvider<bool>((ref) async {
  ref.watch(currentUidProvider);
  return ref.read(userSacramentsRepositoryProvider).hasLinkedSacramentRecords();
});

final householdLinkedSacramentStubsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUidProvider);
  return ref.read(userSacramentsRepositoryProvider).listHouseholdLinkedStubs();
});
