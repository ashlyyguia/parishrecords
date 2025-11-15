import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/record.dart';
import 'records_provider.dart';

class AnalyticsState {
  final int total;
  final Map<RecordType, int> byType;
  final int lastMonthTotal;
  final Map<RecordType, int> lastMonthByType;
  final int pendingRequests;
  final int totalRequests;
  final int activeUsers;
  
  const AnalyticsState({
    required this.total,
    required this.byType,
    required this.lastMonthTotal,
    required this.lastMonthByType,
    this.pendingRequests = 0,
    this.totalRequests = 0,
    this.activeUsers = 1,
  });
}

final analyticsProvider = Provider<AnalyticsState>((ref) {
  final records = ref.watch(recordsProvider);

  // Previous calendar month range
  final now = DateTime.now();
  final firstOfThisMonth = DateTime(now.year, now.month, 1);
  final end = firstOfThisMonth; // exclusive
  final prevMonth = DateTime(firstOfThisMonth.year, firstOfThisMonth.month - 1, 1);
  final start = prevMonth; // inclusive

  bool inLastMonth(DateTime d) => d.isAfter(start.subtract(const Duration(milliseconds: 1))) && d.isBefore(end);

  final byType = <RecordType, int>{};
  final lastByType = <RecordType, int>{};
  for (final t in RecordType.values) {
    final listForType = records.where((r) => r.type == t);
    byType[t] = listForType.length;
    lastByType[t] = listForType.where((r) => inLastMonth(r.date)).length;
  }

  final lastTotal = records.where((r) => inLastMonth(r.date)).length;

  return AnalyticsState(
    total: records.length,
    byType: byType,
    lastMonthTotal: lastTotal,
    lastMonthByType: lastByType,
  );
});
