import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/finance_providers.dart';
import '../../../providers/notification_provider.dart';
import '../../../utils/donation_display.dart';
import '../../../utils/firestore_date.dart';
import '../widgets/finance_dashboard_design.dart';

class FinanceDashboardPage extends ConsumerStatefulWidget {
  const FinanceDashboardPage({super.key});

  @override
  ConsumerState<FinanceDashboardPage> createState() =>
      _FinanceDashboardPageState();
}

class _FinanceDashboardPageState extends ConsumerState<FinanceDashboardPage> {
  int _days = 30;

  static final _currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  static final _shortDate = DateFormat('MMM d, yyyy');

  DateTime? _donationDate(Map<String, dynamic> row) {
    return parseFirestoreDate(row['created_at'] ?? row['createdAt']);
  }

  bool _inPeriod(Map<String, dynamic> row) {
    final dt = _donationDate(row);
    if (dt == null) return false;
    final since = DateTime.now().subtract(Duration(days: _days));
    return !dt.isBefore(since);
  }

  List<Map<String, dynamic>> _periodRows(List<Map<String, dynamic>> rows) {
    return rows.where(_inPeriod).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider).user;
    final displayName = (user?.displayName ?? '').trim();
    final greeting = displayName.isNotEmpty
        ? 'Welcome back, $displayName'
        : 'Track parish giving, fees, and pending transfers';

    final overviewAsync = ref.watch(financeOverviewProvider(_days));
    final donationsAsync = ref.watch(donationsStreamProvider(120));
    final unread = ref.watch(unreadNotificationsCountStreamProvider).maybeWhen(
          data: (n) => n,
          orElse: () => 0,
        );

    return Scaffold(
      backgroundColor: FinanceDashboardDesign.background,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(financeOverviewProvider(_days));
          ref.invalidate(donationsStreamProvider(120));
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  FinanceDashboardHero(
                    greeting: greeting,
                    periodDays: _days,
                    onPeriodChanged: (d) => setState(() => _days = d),
                  ),
                  const SizedBox(height: 20),
                  donationsAsync.when(
                    data: (allRows) {
                      final periodRows = _periodRows(allRows);
                      final overview = overviewAsync.maybeWhen(
                        data: (m) => m,
                        orElse: () => const <String, dynamic>{},
                      );

                      final periodTotal = _sumAmount(periodRows);
                      final donationCount = periodRows
                          .where((r) => !_isCertificate(r))
                          .length;
                      final pendingGcash = allRows.where(_isPendingGcash).length;
                      final unreconciled = allRows.where(_needsReview).length;
                      final certFees = allRows.where(_isCertificate).length;

                      final byMethod = _aggregateByMethod(
                        periodRows,
                        overview['by_method'],
                      );
                      final byCampaign = _aggregateByCampaign(
                        periodRows,
                        overview['by_campaign'],
                      );
                      final sparkline = _buildSparkline(periodRows);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildStatsGrid(
                            periodTotal: periodTotal,
                            donationCount: donationCount,
                            pendingGcash: pendingGcash,
                            unreconciled: unreconciled,
                            certFees: certFees,
                          ),
                          const SizedBox(height: 20),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final wide = constraints.maxWidth >= 900;
                              if (wide) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _buildTrendPanel(sparkline),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _buildMethodsPanel(byMethod),
                                    ),
                                  ],
                                );
                              }
                              return Column(
                                children: [
                                  _buildTrendPanel(sparkline),
                                  const SizedBox(height: 16),
                                  _buildMethodsPanel(byMethod),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final wide = constraints.maxWidth >= 900;
                              if (wide) {
                                return IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: _buildCampaignPanel(byCampaign),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: _buildQuickActions(unread),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return Column(
                                children: [
                                  _buildCampaignPanel(byCampaign),
                                  const SizedBox(height: 16),
                                  _buildQuickActions(unread),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          _buildRecentActivity(allRows),
                        ],
                      );
                    },
                    loading: () => Column(
                      children: [
                        _buildStatsGridLoading(),
                        const SizedBox(height: 20),
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ],
                    ),
                    error: (e, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStatsGridLoading(),
                        const SizedBox(height: 16),
                        FinancePanel(
                          title: 'Could not load donations',
                          icon: Icons.error_outline,
                          child: Text(
                            '$e',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _sumAmount(List<Map<String, dynamic>> rows) {
    var total = 0.0;
    for (final r in rows) {
      if (_isPendingGcash(r)) continue;
      total += (r['amount'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  bool _isCertificate(Map<String, dynamic> r) =>
      (r['campaign'] ?? '').toString().trim().toLowerCase() == 'certificate';

  bool _isPendingGcash(Map<String, dynamic> r) =>
      r['amount_pending'] == true ||
      (r['status'] ?? '').toString() == 'awaiting_gcash_amount';

  bool _needsReview(Map<String, dynamic> r) {
    if (_isPendingGcash(r)) return true;
    if (r['reconciled'] == true) return false;
    final amount = (r['amount'] as num?)?.toDouble() ?? 0;
    return amount > 0;
  }

  Map<String, double> _aggregateByMethod(
    List<Map<String, dynamic>> rows,
    dynamic overviewMethods,
  ) {
    final map = <String, double>{};
    for (final r in rows) {
      if (_isPendingGcash(r)) continue;
      final method = donationPaymentMethodId(r);
      final amount = (r['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) continue;
      map[method] = (map[method] ?? 0) + amount;
    }
    if (map.isEmpty && overviewMethods is Map) {
      for (final e in overviewMethods.entries) {
        final v = (e.value as num?)?.toDouble() ?? 0;
        if (v > 0) map[e.key.toString()] = v;
      }
    }
    return map;
  }

  Map<String, double> _aggregateByCampaign(
    List<Map<String, dynamic>> rows,
    dynamic overviewCampaigns,
  ) {
    final map = <String, double>{};
    for (final r in rows) {
      if (_isPendingGcash(r) || _isCertificate(r)) continue;
      final amount = (r['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) continue;
      final label = donationTypeLabel(r);
      map[label] = (map[label] ?? 0) + amount;
    }
    if (map.isEmpty && overviewCampaigns is Map) {
      for (final e in overviewCampaigns.entries) {
        if (e.key.toString().trim().toLowerCase() == 'certificate') continue;
        final v = (e.value as num?)?.toDouble() ?? 0;
        if (v > 0) {
          map[formatDonationTypeLabel(e.key.toString())] = v;
        }
      }
    }
    return map;
  }

  List<FlSpot> _buildSparkline(List<Map<String, dynamic>> rows) {
    final since = DateTime.now().subtract(Duration(days: _days));
    final buckets = <DateTime, double>{};

    for (var i = 0; i <= _days; i++) {
      final day = DateTime(since.year, since.month, since.day + i);
      buckets[day] = 0;
    }

    for (final r in rows) {
      if (_isPendingGcash(r)) continue;
      final dt = _donationDate(r);
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      if (!buckets.containsKey(day)) continue;
      buckets[day] = (buckets[day] ?? 0) +
          ((r['amount'] as num?)?.toDouble() ?? 0);
    }

    final sorted = buckets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return [
      for (var i = 0; i < sorted.length; i++)
        FlSpot(i.toDouble(), sorted[i].value),
    ];
  }

  Widget _buildStatsGrid({
    required double periodTotal,
    required int donationCount,
    required int pendingGcash,
    required int unreconciled,
    required int certFees,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 640
                ? 2
                : 1;
        final cards = [
          FinanceStatCard(
            label: 'Period revenue',
            value: _currency.format(periodTotal),
            icon: Icons.payments_rounded,
            tint: FinanceDashboardDesign.accent,
            softTint: FinanceDashboardDesign.accentSoft,
            subtitle: 'Last $_days days',
          ),
          FinanceStatCard(
            label: 'Donations',
            value: '$donationCount',
            icon: Icons.volunteer_activism_rounded,
            tint: FinanceDashboardDesign.indigo,
            softTint: FinanceDashboardDesign.indigoSoft,
            subtitle: 'Excl. certificate fees',
          ),
          FinanceStatCard(
            label: 'Pending GCash',
            value: '$pendingGcash',
            icon: Icons.qr_code_scanner_rounded,
            tint: FinanceDashboardDesign.amber,
            softTint: FinanceDashboardDesign.amberSoft,
            subtitle: pendingGcash > 0 ? 'Needs amount match' : 'All matched',
          ),
          FinanceStatCard(
            label: 'Needs review',
            value: '$unreconciled',
            icon: Icons.rule_folder_outlined,
            tint: FinanceDashboardDesign.rose,
            softTint: FinanceDashboardDesign.roseSoft,
            subtitle: '$certFees certificate fees total',
          ),
        ];

        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: cols == 1 ? 2.6 : 2.1,
          children: cards,
        );
      },
    );
  }

  Widget _buildStatsGridLoading() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 640 ? 2 : 1;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.2,
          children: List.generate(
            4,
            (_) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrendPanel(List<FlSpot> points) {
    double minY = 0;
    double maxY = 0;
    for (var i = 0; i < points.length; i++) {
      final y = points[i].y;
      if (i == 0) {
        minY = y;
        maxY = y;
      } else {
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    final pad = (maxY - minY).abs() * 0.15;
    final chartMin = points.isEmpty ? 0.0 : (minY - pad).clamp(0.0, double.infinity);
    final chartMax = points.isEmpty ? 1.0 : maxY + pad;

    return FinancePanel(
      title: 'Daily giving ($_days days)',
      icon: Icons.show_chart_rounded,
      child: SizedBox(
        height: 180,
        child: points.every((p) => p.y == 0)
            ? Center(
                child: Text(
                  'No confirmed amounts in this period yet.',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            : LineChart(
                LineChartData(
                  minY: chartMin,
                  maxY: chartMax,
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: chartMax > 0 ? chartMax / 4 : 1,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: Colors.grey.shade200,
                      strokeWidth: 1,
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      color: FinanceDashboardDesign.accent,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: FinanceDashboardDesign.accentSoft.withValues(
                          alpha: 0.55,
                        ),
                      ),
                      spots: points.length < 2
                          ? const [FlSpot(0, 0), FlSpot(1, 0)]
                          : points,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildMethodsPanel(Map<String, double> byMethod) {
    final entries = byMethod.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (s, e) => s + e.value);
    const colors = [
      FinanceDashboardDesign.accent,
      FinanceDashboardDesign.indigo,
      FinanceDashboardDesign.amber,
      FinanceDashboardDesign.rose,
      Color(0xFF059669),
    ];

    return FinancePanel(
      title: 'By payment method',
      icon: Icons.account_balance_wallet_outlined,
      child: entries.isEmpty
          ? Text(
              'No confirmed payments in this period.',
              style: TextStyle(color: Colors.grey.shade600),
            )
          : Column(
              children: [
                SizedBox(
                  height: 160,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 36,
                      sections: [
                        for (var i = 0; i < entries.length; i++)
                          PieChartSectionData(
                            value: entries[i].value,
                            color: colors[i % colors.length],
                            radius: 42,
                            title: total > 0
                                ? '${((entries[i].value / total) * 100).round()}%'
                                : '',
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < entries.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colors[i % colors.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            formatPaymentMethod(entries[i].key),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          _currency.format(entries[i].value),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildCampaignPanel(Map<String, double> byCampaign) {
    final entries = byCampaign.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (s, e) => s + e.value);
    const colors = [
      FinanceDashboardDesign.accent,
      FinanceDashboardDesign.indigo,
      FinanceDashboardDesign.amber,
      FinanceDashboardDesign.rose,
      Color(0xFF059669),
    ];

    return FinancePanel(
      title: 'By donation type',
      icon: Icons.category_outlined,
      child: entries.isEmpty
          ? Text(
              'No gifts recorded for this period.',
              style: TextStyle(color: Colors.grey.shade600),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < entries.length && i < 6; i++)
                  FinanceBreakdownRow(
                    label: entries[i].key,
                    amountLabel: _currency.format(entries[i].value),
                    fraction: total > 0 ? entries[i].value / total : 0,
                    color: colors[i % colors.length],
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: FinanceDashboardDesign.accentSoft.withValues(
                      alpha: 0.45,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Total (donations only)',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        _currency.format(total),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildQuickActions(int unread) {
    return FinancePanel(
      title: 'Quick actions',
      icon: Icons.bolt_rounded,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FinanceQuickAction(
            label: 'Donations ledger',
            subtitle: 'Cash, GCash, and online gifts',
            icon: Icons.volunteer_activism_rounded,
            color: FinanceDashboardDesign.accent,
            softColor: FinanceDashboardDesign.accentSoft,
            onTap: () => context.go('/finance/donations'),
          ),
          const SizedBox(height: 10),
          FinanceQuickAction(
            label: 'Certificate fees',
            subtitle: 'Sacramental document payments',
            icon: Icons.verified_outlined,
            color: FinanceDashboardDesign.indigo,
            softColor: FinanceDashboardDesign.indigoSoft,
            onTap: () => context.go('/finance/certificate-fees'),
          ),
          const SizedBox(height: 10),
          FinanceQuickAction(
            label: 'Reports',
            subtitle: 'Export and period summaries',
            icon: Icons.summarize_outlined,
            color: const Color(0xFF059669),
            softColor: const Color(0xFFD1FAE5),
            onTap: () => context.go('/finance/reports'),
          ),
          const SizedBox(height: 10),
          FinanceQuickAction(
            label: 'Notifications',
            subtitle: unread > 0
                ? '$unread unread alert${unread == 1 ? '' : 's'}'
                : 'Payment and donation alerts',
            icon: Icons.notifications_outlined,
            color: FinanceDashboardDesign.rose,
            softColor: FinanceDashboardDesign.roseSoft,
            badgeCount: unread,
            onTap: () => context.go('/finance/notifications'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(List<Map<String, dynamic>> rows) {
    final recent = rows.take(8).toList();

    return FinancePanel(
      title: 'Recent activity',
      icon: Icons.history_rounded,
      trailing: TextButton(
        onPressed: () => context.go('/finance/donations'),
        child: const Text('View all'),
      ),
      child: recent.isEmpty
          ? Text(
              'No recent transactions yet.',
              style: TextStyle(color: Colors.grey.shade600),
            )
          : Column(
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: Colors.grey.shade200,
                    ),
                  _activityRow(recent[i]),
                ],
              ],
            ),
    );
  }

  Widget _activityRow(Map<String, dynamic> r) {
    final isCert = _isCertificate(r);
    final isPending = _isPendingGcash(r);
    final donor = r['anonymous'] == true
        ? 'Anonymous'
        : ((r['donor_name'] ?? '').toString().trim().isNotEmpty
            ? r['donor_name'].toString()
            : '—');
    final dt = _donationDate(r);
    final dateStr = dt != null ? _shortDate.format(dt) : '—';
    final method = formatPaymentMethod(donationPaymentMethodId(r));
    final campaign = donationTypeLabel(r);
    final amountLabel = donationAmountLabel(r);

    final color = isCert
        ? FinanceDashboardDesign.indigo
        : isPending
            ? FinanceDashboardDesign.amber
            : FinanceDashboardDesign.accent;
    final soft = isCert
        ? FinanceDashboardDesign.indigoSoft
        : isPending
            ? FinanceDashboardDesign.amberSoft
            : FinanceDashboardDesign.accentSoft;
    final icon = isCert
        ? Icons.description_outlined
        : isPending
            ? Icons.qr_code_2_outlined
            : Icons.volunteer_activism_outlined;

    return FinanceActivityRow(
      title: donor,
      subtitle: '$dateStr · $method · $campaign',
      amountLabel: amountLabel,
      icon: icon,
      color: color,
      softColor: soft,
    );
  }
}
