import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/donations_repository.dart';
import '../../widgets/app_loading.dart';

final _myDonationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return DonationsRepository().listMine(limit: 100);
});

class UserDonationsScreen extends ConsumerWidget {
  const UserDonationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final donationsAsync = ref.watch(_myDonationsProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('My Donations'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_myDonationsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final recorded = await context.push<bool>('/donate');
          if (recorded == true) ref.invalidate(_myDonationsProvider);
        },
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Donate Now'),
      ),
      body: donationsAsync.when(
        loading: () => const AppLoading(message: 'Loading donations...'),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: cs.error, size: 48),
                const SizedBox(height: 16),
                Text('Failed to load donations', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(e.toString(), style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(_myDonationsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.volunteer_activism_outlined, size: 64,
                        color: cs.primary.withValues(alpha: 0.4)),
                    const SizedBox(height: 16),
                    Text('No donations yet', style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      'Your donation history will appear here.\nClick "Donate Now" to get started.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }

          final totalAmount = rows.fold<double>(0, (sum, d) {
            final a = d['amount'];
            return sum + (a is num ? a.toDouble() : 0.0);
          });

          return Column(
            children: [
              // Summary card
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Card(
                  elevation: 0,
                  color: cs.primaryContainer,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.volunteer_activism, color: cs.onPrimary, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Donated', style: theme.textTheme.labelLarge
                                  ?.copyWith(color: cs.onPrimaryContainer)),
                              Text(
                                '₱${totalAmount.toStringAsFixed(2)}',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${rows.length}', style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
                            Text('donations', style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onPrimaryContainer)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(_myDonationsProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final d = rows[i];
                      final amount = (d['amount'] is num) ? (d['amount'] as num).toDouble() : 0.0;
                      final method = (d['payment_method'] ?? d['method'] ?? 'cash').toString();
                      final date = (d['created_at'] ?? d['date'] ?? '').toString();
                      final campaign = (d['campaign'] ?? '').toString();
                      final isReconciled = d['reconciled'] == true;

                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.pink.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.favorite, color: Colors.pink, size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      campaign.isNotEmpty ? campaign : 'General Donation',
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.credit_card_outlined, size: 14,
                                            color: cs.onSurfaceVariant),
                                        const SizedBox(width: 4),
                                        Text(method.toUpperCase(),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(color: cs.onSurfaceVariant)),
                                        if (date.isNotEmpty) ...[ 
                                          const SizedBox(width: 10),
                                          Icon(Icons.calendar_today_outlined, size: 14,
                                              color: cs.onSurfaceVariant),
                                          const SizedBox(width: 4),
                                          Text(date.length > 10 ? date.substring(0, 10) : date,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(color: cs.onSurfaceVariant)),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '₱${amount.toStringAsFixed(2)}',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: (isReconciled ? Colors.green : Colors.orange)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      isReconciled ? 'Reconciled' : 'Pending',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: isReconciled ? Colors.green : Colors.orange,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

}
