import 'dart:convert';
import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/backend.dart';

/// Admin analytics data model
class AdminAnalytics {
  final int households;
  final int parishioners;
  final int records;
  final int requests;
  final int donations;
  final int ocrPending;

  AdminAnalytics({
    required this.households,
    required this.parishioners,
    required this.records,
    required this.requests,
    required this.donations,
    required this.ocrPending,
  });

  factory AdminAnalytics.fromJson(Map<String, dynamic> json) {
    return AdminAnalytics(
      households: json['households'] ?? 0,
      parishioners: json['parishioners'] ?? 0,
      records: json['records'] ?? 0,
      requests: json['requests'] ?? 0,
      donations: json['donations'] ?? 0,
      ocrPending: json['ocrPending'] ?? 0,
    );
  }
}

/// Provider for admin analytics
final adminAnalyticsProvider = FutureProvider<AdminAnalytics>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Not authenticated');
  final token = await user.getIdToken();

  final url = '${BackendConfig.baseUrl}/api/admin/analytics';
  developer.log('[Analytics] Calling: $url', name: 'AdminAnalytics');

  final response = await http.get(
    Uri.parse(url),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
  );

  developer.log(
    '[Analytics] Response: ${response.statusCode} - ${response.body}',
    name: 'AdminAnalytics',
  );

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    return AdminAnalytics.fromJson(data);
  }

  throw Exception(
    'Failed to load analytics: ${response.statusCode} - ${response.body}',
  );
});
