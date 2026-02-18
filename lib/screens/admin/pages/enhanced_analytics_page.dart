import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/records_provider.dart';
import '../../../providers/admin_providers.dart';
import '../../../models/record.dart';

class EnhancedAnalyticsPage extends ConsumerStatefulWidget {
  const EnhancedAnalyticsPage({super.key});

  @override
  ConsumerState<EnhancedAnalyticsPage> createState() =>
      _EnhancedAnalyticsPageState();
}

class _EnhancedAnalyticsPageState extends ConsumerState<EnhancedAnalyticsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  String _selectedPeriod = '30 Days';
  final List<String> _periods = ['7 Days', '30 Days', '90 Days', '1 Year'];
  String _selectedRecordTypeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  List<dynamic> _filterRecords(List<dynamic> records) {
    final days = _mapPeriodToDays(_selectedPeriod);
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));

    return records.where((r) {
      DateTime? recordDate;
      String? type;

      if (r is ParishRecord) {
        recordDate = r.date;
        type = r.type.value;
      } else if (r is Map) {
        final date = r['date'];
        if (date != null) {
          recordDate = DateTime.tryParse(date.toString());
        }
        type = r['type']?.toString();
      }

      if (recordDate == null) return false;
      if (recordDate.isBefore(start) || recordDate.isAfter(now)) {
        return false;
      }

      if (_selectedRecordTypeFilter != 'all') {
        if (type == null) return false;
        if (type.toLowerCase() != _selectedRecordTypeFilter.toLowerCase()) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Widget _buildBackendAnalyticsSummary(
    AsyncValue<List<Map<String, dynamic>>> analyticsAsync,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return analyticsAsync.when(
      data: (rows) {
        if (rows.isEmpty) {
          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No analytics data recorded yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          );
        }

        int recordsCreated = 0;
        int requestsCreated = 0;
        int requestsApproved = 0;

        for (final m in rows) {
          final type = (m['metric_type'] ?? '').toString();
          final name = (m['metric_name'] ?? '').toString();
          final value = m['value'] is int
              ? m['value'] as int
              : int.tryParse(m['value']?.toString() ?? '') ?? 0;

          if (type == 'records' && name.endsWith('_created')) {
            recordsCreated += value;
          }
          if (type == 'requests' &&
              name.startsWith('certificate_') &&
              name.endsWith('_created')) {
            requestsCreated += value;
          }
          if (type == 'requests' && name == 'certificate_status_approved') {
            requestsApproved += value;
          }
        }

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Backend Analytics (last 30 days)',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _buildSmallMetricChip(
                      'Records Created',
                      recordsCreated.toString(),
                      Icons.folder_copy_outlined,
                      colorScheme.primary,
                    ),
                    _buildSmallMetricChip(
                      'Certificate Requests',
                      requestsCreated.toString(),
                      Icons.request_page_outlined,
                      colorScheme.secondary,
                    ),
                    _buildSmallMetricChip(
                      'Requests Approved',
                      requestsApproved.toString(),
                      Icons.verified_outlined,
                      Colors.green,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      loading: () => Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (e, _) => Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Failed to load backend analytics: $e',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.redAccent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallMetricChip(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$value $label',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final records = ref.watch(recordsProvider);
    final analyticsAsync = ref.watch(
      adminAnalyticsProvider(_mapPeriodToDays(_selectedPeriod)),
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Header with Period Selector
            _buildHeader(theme, colorScheme),

            // Tab Bar
            _buildTabBar(colorScheme),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(
                    records,
                    analyticsAsync,
                    theme,
                    colorScheme,
                  ),
                  _buildRecordsTab(records, theme, colorScheme),
                  _buildCertificatesTab(records, theme, colorScheme),
                  _buildTrendsTab(records, theme, colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: 0.1),
            colorScheme.secondary.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.analytics_outlined,
                  color: colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Analytics Dashboard',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Comprehensive insights and statistics',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Period Selector
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _periods.map((period) {
                  final isSelected = period == _selectedPeriod;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedPeriod = period),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        period,
                        style: TextStyle(
                          color: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Record type filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTypeFilterChip('all', 'All types', colorScheme),
                _buildTypeFilterChip('baptism', 'Baptism', colorScheme),
                _buildTypeFilterChip('marriage', 'Marriage', colorScheme),
                _buildTypeFilterChip(
                  'confirmation',
                  'Confirmation',
                  colorScheme,
                ),
                _buildTypeFilterChip('funeral', 'Death / Burial', colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeFilterChip(
    String value,
    String label,
    ColorScheme colorScheme,
  ) {
    final isSelected = _selectedRecordTypeFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: isSelected,
        label: Text(label),
        onSelected: (_) {
          setState(() {
            _selectedRecordTypeFilter = value;
          });
        },
        selectedColor: colorScheme.primary.withValues(alpha: 0.15),
        labelStyle: TextStyle(
          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  int _mapPeriodToDays(String period) {
    switch (period) {
      case '7 Days':
        return 7;
      case '30 Days':
        return 30;
      case '90 Days':
        return 90;
      case '1 Year':
        return 365;
      default:
        return 30;
    }
  }

  Widget _buildTabBar(ColorScheme colorScheme) {
    final isNarrow = MediaQuery.of(context).size.width < 720;
    return Container(
      color: colorScheme.surface,
      child: TabBar(
        controller: _tabController,
        isScrollable: isNarrow,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurface.withValues(alpha: 0.6),
        indicatorColor: colorScheme.primary,
        indicatorWeight: 3,
        tabs: const [
          Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
          Tab(icon: Icon(Icons.folder_outlined), text: 'Records'),
          Tab(icon: Icon(Icons.verified_outlined), text: 'Certificates'),
          Tab(icon: Icon(Icons.trending_up_outlined), text: 'Trends'),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(
    List<dynamic> records,
    AsyncValue<List<Map<String, dynamic>>> analyticsAsync,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final filteredRecords = _filterRecords(records);
    final totalRecords = filteredRecords.length;

    int pendingCertificates = 0;
    int approvedCertificates = 0;
    for (final r in filteredRecords) {
      if (r is ParishRecord) {
        switch (r.certificateStatus) {
          case CertificateStatus.pending:
            pendingCertificates++;
            break;
          case CertificateStatus.approved:
            approvedCertificates++;
            break;
          case CertificateStatus.rejected:
            // ignore here; only pending/approved shown in overview metrics
            break;
        }
      } else if (r is Map) {
        final status = r['certificateStatus'];
        if (status == 0 || status == 'pending') {
          pendingCertificates++;
        } else if (status == 1 || status == 'approved') {
          approvedCertificates++;
        }
      }
    }
    final thisMonth = filteredRecords.where((r) {
      DateTime? recordDate;
      if (r is ParishRecord) {
        recordDate = r.date;
      } else if (r is Map) {
        final date = r['date'];
        if (date == null) return false;
        recordDate = DateTime.tryParse(date.toString());
      } else {
        return false;
      }
      if (recordDate == null) return false;
      final now = DateTime.now();
      return recordDate.year == now.year && recordDate.month == now.month;
    }).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Key Metrics Cards
          _buildMetricsGrid([
            _MetricData(
              'Total Records',
              totalRecords.toString(),
              Icons.folder_copy,
              Colors.blue,
            ),
            _MetricData(
              'This Month',
              thisMonth.toString(),
              Icons.calendar_today,
              Colors.green,
            ),
            _MetricData(
              'Pending Certificates',
              pendingCertificates.toString(),
              Icons.pending,
              Colors.orange,
            ),
            _MetricData(
              'Approved Certificates',
              approvedCertificates.toString(),
              Icons.verified,
              Colors.teal,
            ),
          ], colorScheme),

          const SizedBox(height: 24),

          // Backend analytics summary (from analytics table)
          _buildBackendAnalyticsSummary(analyticsAsync, theme, colorScheme),

          const SizedBox(height: 24),

          // Record Types Distribution
          _buildRecordTypesChart(filteredRecords, theme, colorScheme),

          const SizedBox(height: 24),

          // Recent Activity
          _buildRecentActivity(filteredRecords, theme, colorScheme),
        ],
      ),
    );
  }

  Widget _buildRecordsTab(
    List<dynamic> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final filteredRecords = _filterRecords(records);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Records by Type
          _buildRecordsByTypeChart(
            context,
            filteredRecords,
            theme,
            colorScheme,
          ),

          const SizedBox(height: 24),

          // Monthly Records Trend
          _buildMonthlyTrendChart(filteredRecords, theme, colorScheme),

          const SizedBox(height: 24),

          // Records Summary Table
          _buildRecordsSummaryTable(filteredRecords, theme, colorScheme),
        ],
      ),
    );
  }

  Widget _buildCertificatesTab(
    List<dynamic> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final filteredRecords = _filterRecords(records);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Certificate Status Distribution
          _buildCertificateStatusChart(filteredRecords, theme, colorScheme),

          const SizedBox(height: 24),

          // Certificate Metrics
          _buildCertificateMetrics(filteredRecords, theme, colorScheme),
        ],
      ),
    );
  }

  Widget _buildTrendsTab(
    List<dynamic> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final filteredRecords = _filterRecords(records);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Growth Trend
          _buildGrowthTrendChart(filteredRecords, theme, colorScheme),

          const SizedBox(height: 24),

          // Seasonal Analysis
          _buildSeasonalAnalysis(filteredRecords, theme, colorScheme),

          const SizedBox(height: 24),

          // Performance Insights
          _buildPerformanceInsights(records, theme, colorScheme),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(List<_MetricData> metrics, ColorScheme colorScheme) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        // Slightly taller cards to prevent vertical overflow on small screens
        childAspectRatio: 1.25,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, index) {
        final metric = metrics[index];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  metric.color.withValues(alpha: 0.1),
                  metric.color.withValues(alpha: 0.05),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(metric.icon, color: metric.color, size: 24),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: metric.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.trending_up,
                        color: metric.color,
                        size: 16,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.value,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      metric.title,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecordTypesChart(
    List<dynamic> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final recordTypes = <String, int>{};
    for (final record in records) {
      if (record is ParishRecord) {
        final type = record.type.value;
        recordTypes[type] = (recordTypes[type] ?? 0) + 1;
      } else if (record is Map) {
        final type = record['type']?.toString() ?? 'Unknown';
        recordTypes[type] = (recordTypes[type] ?? 0) + 1;
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Record Types Distribution',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: recordTypes.isEmpty
                  ? Center(
                      child: Text(
                        'No data available',
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  : PieChart(
                      PieChartData(
                        sections: recordTypes.entries.map((entry) {
                          final colors = [
                            Colors.blue,
                            Colors.green,
                            Colors.orange,
                            Colors.purple,
                            Colors.red,
                          ];
                          final colorIndex = recordTypes.keys.toList().indexOf(
                            entry.key,
                          );
                          return PieChartSectionData(
                            value: entry.value.toDouble(),
                            title: '${entry.key}\n${entry.value}',
                            color: colors[colorIndex % colors.length],
                            radius: 80,
                            titleStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }).toList(),
                        centerSpaceRadius: 40,
                        sectionsSpace: 2,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity(
    List<dynamic> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final recentRecords = records.whereType<ParishRecord>().toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Activity',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...recentRecords.take(5).map<Widget>((record) {
              final name = record.name;
              final type = record.type.value;
              final formattedDate = DateFormat(
                'MMM dd, yyyy',
              ).format(record.date);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getRecordTypeIcon(type),
                        color: colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$type • $formattedDate',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // Additional chart building methods would go here...
  // For brevity, I'll include placeholder methods

  Widget _buildRecordsByTypeChart(
    BuildContext context,
    List<dynamic> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final recordTypes = <String, int>{};
    for (final record in records) {
      if (record is ParishRecord) {
        final type = record.type.name;
        recordTypes[type] = (recordTypes[type] ?? 0) + 1;
      } else if (record is Map) {
        final type = record['type']?.toString() ?? 'Unknown';
        recordTypes[type] = (recordTypes[type] ?? 0) + 1;
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Records by Type',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: recordTypes.isEmpty
                  ? Center(
                      child: Text(
                        'No data available',
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: recordTypes.values.isNotEmpty
                            ? recordTypes.values
                                      .reduce((a, b) => a > b ? a : b)
                                      .toDouble() *
                                  1.2
                            : 10,
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchCallback: (event, response) {
                            if (!event.isInterestedForInteractions ||
                                response == null ||
                                response.spot == null) {
                              return;
                            }
                            final index = response.spot!.touchedBarGroup.x;
                            final types = recordTypes.keys.toList();
                            if (index < 0 || index >= types.length) return;
                            final type = types[index];

                            final days = _mapPeriodToDays(_selectedPeriod);
                            final now = DateTime.now();
                            final from = DateTime(
                              now.year,
                              now.month,
                              now.day,
                            ).subtract(Duration(days: days - 1));

                            final df = DateFormat('yyyy-MM-dd');
                            final params = {
                              'type': type,
                              'from': df.format(from),
                              'to': df.format(now),
                            };

                            if (context.mounted) {
                              context.push('/admin/records', extra: params);
                            }
                          },
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final types = recordTypes.keys.toList();
                                if (value.toInt() >= 0 &&
                                    value.toInt() < types.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      types[value.toInt()],
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                            ),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: recordTypes.entries.map((entry) {
                          final index = recordTypes.keys.toList().indexOf(
                            entry.key,
                          );
                          final colors = [
                            Colors.blue,
                            Colors.green,
                            Colors.orange,
                            Colors.purple,
                            Colors.red,
                          ];
                          return BarChartGroupData(
                            x: index,
                            barRods: [
                              BarChartRodData(
                                toY: entry.value.toDouble(),
                                color: colors[index % colors.length],
                                width: 20,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyTrendChart(
    List<dynamic> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final monthlyData = <String, int>{};
    final now = DateTime.now();

    // Initialize last 6 months
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey = DateFormat('MMM yyyy').format(month);
      monthlyData[monthKey] = 0;
    }

    // Count records by month
    for (final record in records) {
      DateTime? date;
      if (record is ParishRecord) {
        date = record.date;
      } else if (record is Map && record['date'] != null) {
        date = DateTime.tryParse(record['date'].toString());
      }
      if (date != null && date.isAfter(DateTime(now.year, now.month - 5, 1))) {
        final monthKey = DateFormat('MMM yyyy').format(date);
        monthlyData[monthKey] = (monthlyData[monthKey] ?? 0) + 1;
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly Trend (Last 6 Months)',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 1,
                    verticalInterval: 1,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: colorScheme.outline.withValues(alpha: 0.2),
                        strokeWidth: 1,
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: colorScheme.outline.withValues(alpha: 0.2),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final months = monthlyData.keys.toList();
                          if (value.toInt() >= 0 &&
                              value.toInt() < months.length) {
                            final month = months[value.toInt()];
                            return SideTitleWidget(
                              meta: meta,
                              child: Text(
                                month.split(
                                  ' ',
                                )[0], // Show only month abbreviation
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                        reservedSize: 42,
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  minX: 0,
                  maxX: (monthlyData.length - 1).toDouble(),
                  minY: 0,
                  maxY: monthlyData.values.isNotEmpty
                      ? monthlyData.values
                                .reduce((a, b) => a > b ? a : b)
                                .toDouble() *
                            1.2
                      : 10,
                  lineBarsData: [
                    LineChartBarData(
                      spots: monthlyData.entries.map((entry) {
                        final index = monthlyData.keys.toList().indexOf(
                          entry.key,
                        );
                        return FlSpot(index.toDouble(), entry.value.toDouble());
                      }).toList(),
                      isCurved: true,
                      gradient: LinearGradient(
                        colors: [colorScheme.primary, colorScheme.secondary],
                      ),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: colorScheme.primary,
                            strokeWidth: 2,
                            strokeColor: colorScheme.surface,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primary.withValues(alpha: 0.3),
                            colorScheme.primary.withValues(alpha: 0.1),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordsSummaryTable(
    List<dynamic> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Records Summary',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Detailed breakdown of all record types and their statistics',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCertificateStatusChart(
    List<dynamic> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final statusCounts = <String, int>{
      'Pending': 0,
      'Approved': 0,
      'Rejected': 0,
    };

    for (final record in records) {
      if (record is ParishRecord) {
        switch (record.certificateStatus) {
          case CertificateStatus.pending:
            statusCounts['Pending'] = statusCounts['Pending']! + 1;
            break;
          case CertificateStatus.approved:
            statusCounts['Approved'] = statusCounts['Approved']! + 1;
            break;
          case CertificateStatus.rejected:
            statusCounts['Rejected'] = statusCounts['Rejected']! + 1;
            break;
        }
      } else if (record is Map) {
        final status = record['certificateStatus'];
        if (status == 0 || status == 'pending') {
          statusCounts['Pending'] = statusCounts['Pending']! + 1;
        } else if (status == 1 || status == 'approved') {
          statusCounts['Approved'] = statusCounts['Approved']! + 1;
        } else if (status == 2 || status == 'rejected') {
          statusCounts['Rejected'] = statusCounts['Rejected']! + 1;
        }
      }
    }

    final total = statusCounts.values.reduce((a, b) => a + b);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Certificate Status Distribution',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 720;

                final chart = SizedBox(
                  height: 200,
                  child: total == 0
                      ? Center(
                          child: Text(
                            'No certificates found',
                            style: TextStyle(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        )
                      : PieChart(
                          PieChartData(
                            sections: [
                              PieChartSectionData(
                                value: statusCounts['Pending']!.toDouble(),
                                title:
                                    '${((statusCounts['Pending']! / total) * 100).toInt()}%',
                                color: Colors.orange,
                                radius: 60,
                                titleStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              PieChartSectionData(
                                value: statusCounts['Approved']!.toDouble(),
                                title:
                                    '${((statusCounts['Approved']! / total) * 100).toInt()}%',
                                color: Colors.green,
                                radius: 60,
                                titleStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              PieChartSectionData(
                                value: statusCounts['Rejected']!.toDouble(),
                                title:
                                    '${((statusCounts['Rejected']! / total) * 100).toInt()}%',
                                color: Colors.red,
                                radius: 60,
                                titleStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                            centerSpaceRadius: 50,
                            sectionsSpace: 2,
                          ),
                        ),
                );

                final legend = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLegendItem(
                      'Pending',
                      Colors.orange,
                      statusCounts['Pending']!,
                      theme,
                    ),
                    const SizedBox(height: 8),
                    _buildLegendItem(
                      'Approved',
                      Colors.green,
                      statusCounts['Approved']!,
                      theme,
                    ),
                    const SizedBox(height: 8),
                    _buildLegendItem(
                      'Rejected',
                      Colors.red,
                      statusCounts['Rejected']!,
                      theme,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          Text(
                            total.toString(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [chart, const SizedBox(height: 16), legend],
                  );
                }

                return Row(
                  children: [
                    Expanded(flex: 2, child: chart),
                    Expanded(child: legend),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(
    String label,
    Color color,
    int count,
    ThemeData theme,
  ) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              Text(
                count.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCertificateMetrics(
    List<dynamic> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Certificate Metrics',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Key performance indicators for certificate processing',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrowthTrendChart(
    List<dynamic> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    // Reuse the same logic as the Monthly Trend chart to show
    // a real growth trend line over the last 6 months.
    final monthlyData = <String, int>{};
    final now = DateTime.now();

    // Initialize last 6 months
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey = DateFormat('MMM yyyy').format(month);
      monthlyData[monthKey] = 0;
    }

    // Count records by month
    for (final record in records) {
      DateTime? date;
      if (record is ParishRecord) {
        date = record.date;
      } else if (record is Map && record['date'] != null) {
        date = DateTime.tryParse(record['date'].toString());
      }
      if (date != null && date.isAfter(DateTime(now.year, now.month - 5, 1))) {
        final monthKey = DateFormat('MMM yyyy').format(date);
        monthlyData[monthKey] = (monthlyData[monthKey] ?? 0) + 1;
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Growth Trend Analysis (Last 6 Months)',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 1,
                    verticalInterval: 1,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: colorScheme.outline.withValues(alpha: 0.2),
                        strokeWidth: 1,
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: colorScheme.outline.withValues(alpha: 0.2),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final months = monthlyData.keys.toList();
                          if (value.toInt() >= 0 &&
                              value.toInt() < months.length) {
                            final month = months[value.toInt()];
                            return SideTitleWidget(
                              meta: meta,
                              child: Text(
                                month.split(' ')[0],
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                        reservedSize: 42,
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  minX: 0,
                  maxX: (monthlyData.length - 1).toDouble(),
                  minY: 0,
                  maxY: monthlyData.values.isNotEmpty
                      ? monthlyData.values
                                .reduce((a, b) => a > b ? a : b)
                                .toDouble() *
                            1.2
                      : 10,
                  lineBarsData: [
                    LineChartBarData(
                      spots: monthlyData.entries.map((entry) {
                        final index = monthlyData.keys.toList().indexOf(
                          entry.key,
                        );
                        return FlSpot(index.toDouble(), entry.value.toDouble());
                      }).toList(),
                      isCurved: true,
                      gradient: LinearGradient(
                        colors: [colorScheme.primary, colorScheme.secondary],
                      ),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: colorScheme.primary,
                            strokeWidth: 2,
                            strokeColor: colorScheme.surface,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primary.withValues(alpha: 0.3),
                            colorScheme.primary.withValues(alpha: 0.1),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeasonalAnalysis(
    List<dynamic> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seasonal Analysis',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Patterns and trends by season and month',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceInsights(
    List<dynamic> records,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Insights',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'AI-powered insights and recommendations',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getRecordTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'baptism':
        return Icons.water_drop;
      case 'marriage':
        return Icons.favorite;
      case 'funeral':
        return Icons.local_florist;
      case 'confirmation':
        return Icons.verified_user;
      default:
        return Icons.description;
    }
  }
}

class _MetricData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  _MetricData(this.title, this.value, this.icon, this.color);
}
