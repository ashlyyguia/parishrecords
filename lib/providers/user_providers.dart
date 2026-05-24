import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final myDashboardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  // Keep dashboard stats cached while navigating within the user shell.
  ref.keepAlive();
  return ref.read(userDashboardRepositoryProvider).getMyDashboard();
});

final myProfileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.read(userProfileRepositoryProvider).getMyProfile();
});

final myRequestsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.read(userRequestsRepositoryProvider).listMyRequests();
});

final requestDetailProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  return ref.read(userRequestsRepositoryProvider).getRequestDetail(id);
});

final mySacramentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.read(userSacramentsRepositoryProvider).listMine();
});
