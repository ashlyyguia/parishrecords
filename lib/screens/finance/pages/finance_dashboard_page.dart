import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/finance_providers.dart';

class FinanceDashboardPage extends ConsumerStatefulWidget {
  const FinanceDashboardPage({super.key});

  @override
  ConsumerState<FinanceDashboardPage> createState() =>
      _FinanceDashboardPageState();
}

class _FinanceDashboardPageState extends ConsumerState<FinanceDashboardPage> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final overviewAsync = ref.watch(financeOverviewProvider(_days));
    final recentAsync = ref.watch(donationsListProvider(10));

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Finance Snapshot',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7d')),
                    ButtonSegment(value: 30, label: Text('30d')),
                    ButtonSegment(value: 90, label: Text('90d')),
                  ],
                  selected: {_days},
                  onSelectionChanged: (s) => setState(() => _days = s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            overviewAsync.when(
              data: (m) {
                final spark = (m['sparkline'] is List)
                    ? (m['sparkline'] as List)
                    : const [];
                final points = <FlSpot>[];
                double minY = 0;
                double maxY = 0;

                for (int i = 0; i < spark.length; i++) {
                  final row = spark[i];
                  if (row is! Map) continue;
                  final amt = (row['amount'] is num)
                      ? (row['amount'] as num).toDouble()
                      : double.tryParse(row['amount']?.toString() ?? '') ?? 0;
                  points.add(FlSpot(i.toDouble(), amt));
                  if (i == 0) {
                    minY = amt;
                    maxY = amt;
                  } else {
                    if (amt < minY) minY = amt;
                    if (amt > maxY) maxY = amt;
                  }
                }

                final pad = (maxY - minY).abs() * 0.15;
                final chartMin = points.isEmpty ? 0.0 : (minY - pad);
                final chartMax = points.isEmpty ? 1.0 : (maxY + pad);

                final monthlyTotals = m['monthly_totals'] is Map
                    ? (m['monthly_totals'] as Map)
                    : const {};
                final monthTotal = (monthlyTotals['total_amount'] is num)
                    ? (monthlyTotals['total_amount'] as num).toDouble()
                    : double.tryParse(
                            monthlyTotals['total_amount']?.toString() ?? '',
                          ) ??
                          0;

                final outstanding = (m['outstanding_pledges'] is num)
                    ? (m['outstanding_pledges'] as num).toInt()
                    : int.tryParse(
                            m['outstanding_pledges']?.toString() ?? '',
                          ) ??
                          0;

                final alerts = (m['quick_reconcile_alerts'] is num)
                    ? (m['quick_reconcile_alerts'] as num).toInt()
                    : int.tryParse(
                            m['quick_reconcile_alerts']?.toString() ?? '',
                          ) ??
                          0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _MetricCard(
                          title: 'Monthly Total',
                          value: monthTotal.toStringAsFixed(2),
                          icon: Icons.payments_outlined,
                        ),
                        _MetricCard(
                          title: 'Outstanding Pledges',
                          value: outstanding.toString(),
                          icon: Icons.assignment_late_outlined,
                        ),
                        _MetricCard(
                          title: 'Reconcile Alerts',
                          value: alerts.toString(),
                          icon: Icons.warning_amber_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cashflow Sparkline ($_days days)',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 140,
                              child: LineChart(
                                LineChartData(
                                  minY: chartMin,
                                  maxY: chartMax,
                                  titlesData: const FlTitlesData(show: false),
                                  borderData: FlBorderData(show: false),
                                  gridData: FlGridData(show: false),
                                  lineBarsData: [
                                    LineChartBarData(
                                      isCurved: true,
                                      color: colorScheme.primary,
                                      barWidth: 3,
                                      dotData: const FlDotData(show: false),
                                      spots: points.isEmpty
                                          ? const [FlSpot(0, 0)]
                                          : points,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    height: 120,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
              error: (e, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Failed to load overview: $e'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Recent Donations',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            recentAsync.when(
              data: (rows) {
                if (rows.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No donations found.'),
                    ),
                  );
                }

                return Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final donor = (r['anonymous'] == true)
                          ? 'Anonymous'
                          : (r['donor_name']?.toString().trim().isNotEmpty ==
                                    true
                                ? r['donor_name'].toString()
                                : '—');
                      final amount = (r['amount'] is num)
                          ? (r['amount'] as num).toDouble()
                          : double.tryParse(r['amount']?.toString() ?? '') ?? 0;
                      final reconciled = r['reconciled'] == true;

                      return ListTile(
                        title: Text(donor, overflow: TextOverflow.ellipsis),
                        subtitle: Text((r['method'] ?? '—').toString()),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              amount.toStringAsFixed(2),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              reconciled ? 'Reconciled' : 'Unreconciled',
                              style: TextStyle(
                                color: reconciled
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (e, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Failed to load donations: $e'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
