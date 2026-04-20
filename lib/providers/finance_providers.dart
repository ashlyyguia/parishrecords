import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/donations_repository.dart';
import '../services/finance_repository.dart';
import '../services/financial_reports_repository.dart';

final financeRepositoryProvider = Provider<FinanceRepository>((ref) {
  return FinanceRepository();
});

final donationsRepositoryProvider = Provider<DonationsRepository>((ref) {
  return DonationsRepository();
});

final financialReportsRepositoryProvider = Provider<FinancialReportsRepository>(
  (ref) {
    return FinancialReportsRepository();
  },
);

final financeOverviewProvider =
    FutureProvider.family<Map<String, dynamic>, int>((ref, days) async {
      try {
        final result = await ref
            .read(financeRepositoryProvider)
            .getOverview(days: days)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                debugPrint('financeOverviewProvider: Timeout after 10s');
                return <String, dynamic>{};
              },
            );
        return result;
      } catch (e) {
        debugPrint('financeOverviewProvider error: $e');
        return <String, dynamic>{};
      }
    });

final donationsListProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>((ref, limit) async {
      try {
        final result = await ref
            .read(donationsRepositoryProvider)
            .list(limit: limit)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                debugPrint('donationsListProvider: Timeout after 10s');
                return <Map<String, dynamic>>[];
              },
            );
        return result;
      } catch (e) {
        debugPrint('donationsListProvider error: $e');
        return <Map<String, dynamic>>[];
      }
    });
