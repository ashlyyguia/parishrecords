import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/requests_provider.dart';

class CertificateRequestsListScreen extends ConsumerStatefulWidget {
  const CertificateRequestsListScreen({super.key});

  @override
  ConsumerState<CertificateRequestsListScreen> createState() =>
      _CertificateRequestsListScreenState();
}

class _CertificateRequestsListScreenState
    extends ConsumerState<CertificateRequestsListScreen> {
  String _statusFilter =
      'all'; // all | pending | approved | rejected | completed
  final TextEditingController _searchCtrl = TextEditingController();
  DateTime? _fromDate;
  DateTime? _toDate;

  void _reload() {
    ref.invalidate(certificateRequestsProvider(100));
  }

  Future<void> _refresh() async {
    ref.invalidate(certificateRequestsProvider(100));
    try {
      await ref.read(certificateRequestsProvider(100).future);
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openNewRequest() async {
    final type = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => const _CertificateRequestTypeScreen(),
      ),
    );

    if (!mounted || type == null || type.isEmpty) return;

    await context.push('/records/certificate-request', extra: type);
    if (!mounted) return;
    ref.invalidate(certificateRequestsProvider(100));
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  String _buildDateRangeLabel(DateFormat df) {
    if (_fromDate == null && _toDate == null) return 'Filter by date';
    final from = _fromDate != null ? df.format(_fromDate!.toLocal()) : '...';
    final to = _toDate != null ? df.format(_toDate!.toLocal()) : '...';
    if (_fromDate != null &&
        _toDate != null &&
        df.format(_fromDate!.toLocal()) == df.format(_toDate!.toLocal())) {
      return from;
    }
    return '$from - $to';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final df = DateFormat.yMd();

    final requestsAsync = ref.watch(certificateRequestsProvider(100));
    final totalCount = requestsAsync.maybeWhen(
      data: (rows) => rows.length,
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Requests'),
            if (totalCount > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$totalCount',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'New request',
            onPressed: _openNewRequest,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: requestsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _buildErrorState(colorScheme, error: e),
          data: (allRows) {
            final safeAllRows = allRows;
            var rows = safeAllRows;

            // status filter
            if (_statusFilter != 'all') {
              final f = _statusFilter;
              rows = rows.where((r) {
                final status =
                    (r['status']?.toString().toLowerCase() ?? 'pending').trim();
                if (f == 'completed') {
                  // Completed = anything that is not pending
                  return status != 'pending';
                }
                return status == f;
              }).toList();
            }

            // date range filter on requested_at
            if (_fromDate != null || _toDate != null) {
              rows = rows.where((r) {
                final raw = r['requested_at'];
                DateTime? dt;
                if (raw is String) {
                  dt = DateTime.tryParse(raw);
                } else if (raw is DateTime) {
                  dt = raw;
                }
                if (dt == null) return false;
                final local = dt.toLocal();
                final dateOnly = DateTime(local.year, local.month, local.day);
                if (_fromDate != null) {
                  final from = DateTime(
                    _fromDate!.year,
                    _fromDate!.month,
                    _fromDate!.day,
                  );
                  if (dateOnly.isBefore(from)) return false;
                }
                if (_toDate != null) {
                  final to = DateTime(
                    _toDate!.year,
                    _toDate!.month,
                    _toDate!.day,
                  );
                  if (dateOnly.isAfter(to)) return false;
                }
                return true;
              }).toList();
            }

            // text search filter
            final q = _searchCtrl.text.trim().toLowerCase();
            if (q.isNotEmpty) {
              rows = rows.where((r) {
                final requester = (r['requester_name'] ?? '')
                    .toString()
                    .toLowerCase();
                final reqId = (r['request_id'] ?? '').toString().toLowerCase();
                final type = (r['request_type'] ?? '').toString().toLowerCase();
                return requester.contains(q) ||
                    reqId.contains(q) ||
                    type.contains(q);
              }).toList();
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorScheme.outline.withValues(alpha: 0.2),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.shadow.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (allRows.isNotEmpty) ...[
                            _buildSummaryRow(allRows, colorScheme),
                            const SizedBox(height: 12),
                          ],
                          TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              labelText: 'Search requests...',
                              hintText: 'Enter name, ID, or type',
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: colorScheme.primary,
                              ),
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() {});
                                      },
                                      icon: Icon(
                                        Icons.clear_rounded,
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: colorScheme.surface,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final now = DateTime.now();
                                    final initialStart =
                                        _fromDate ??
                                        DateTime(
                                          now.year,
                                          now.month,
                                          now.day - 30,
                                        );
                                    final initialEnd =
                                        _toDate ??
                                        DateTime(now.year, now.month, now.day);
                                    final range = await showDateRangePicker(
                                      context: context,
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                      initialDateRange: DateTimeRange(
                                        start: initialStart,
                                        end: initialEnd,
                                      ),
                                    );
                                    if (range != null) {
                                      setState(() {
                                        _fromDate = range.start;
                                        _toDate = range.end;
                                      });
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.calendar_today_outlined,
                                  ),
                                  label: Text(
                                    _fromDate == null && _toDate == null
                                        ? 'Filter by date'
                                        : _buildDateRangeLabel(df),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              if (_fromDate != null || _toDate != null) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Clear date filter',
                                  icon: Icon(
                                    Icons.clear,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _fromDate = null;
                                      _toDate = null;
                                    });
                                  },
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ChoiceChip(
                                  label: const Text('All'),
                                  selected: _statusFilter == 'all',
                                  onSelected: (_) {
                                    setState(() {
                                      _statusFilter = 'all';
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('Pending'),
                                  selected: _statusFilter == 'pending',
                                  onSelected: (_) {
                                    setState(() {
                                      _statusFilter = 'pending';
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('Approved'),
                                  selected: _statusFilter == 'approved',
                                  onSelected: (_) {
                                    setState(() {
                                      _statusFilter = 'approved';
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('Rejected'),
                                  selected: _statusFilter == 'rejected',
                                  onSelected: (_) {
                                    setState(() {
                                      _statusFilter = 'rejected';
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                ChoiceChip(
                                  label: const Text('Completed'),
                                  selected: _statusFilter == 'completed',
                                  onSelected: (_) {
                                    setState(() {
                                      _statusFilter = 'completed';
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(height: 0),
                Expanded(
                  child: rows.isEmpty
                      ? _buildEmptyState(colorScheme)
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final r = rows[index];
                            final status =
                                (r['status']?.toString() ?? 'pending');
                            final statusColor = _statusColor(status);
                            final type = (r['request_type']?.toString() ?? '')
                                .toUpperCase();
                            final requester =
                                (r['requester_name']?.toString() ?? '');
                            final requestedAt = r['requested_at'];

                            String dateLabel;
                            if (requestedAt is String) {
                              dateLabel = df.format(
                                DateTime.tryParse(requestedAt) ??
                                    DateTime.now(),
                              );
                            } else if (requestedAt is DateTime) {
                              dateLabel = df.format(requestedAt);
                            } else {
                              dateLabel = '';
                            }

                            final requestId =
                                (r['request_id']?.toString() ?? '').trim();
                            final recordId = r['record_id']?.toString();
                            final canOpen =
                                recordId != null && recordId.isNotEmpty;

                            final details = <String>[
                              if (type.isNotEmpty) type,
                              if (requestId.isNotEmpty) '#$requestId',
                              if (dateLabel.isNotEmpty) dateLabel,
                            ].join(' • ');

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: canOpen
                                  ? () => context.push('/records/$recordId')
                                  : null,
                              child: Opacity(
                                opacity: canOpen ? 1 : 0.75,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: colorScheme.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: colorScheme.outline.withValues(
                                        alpha: 0.14,
                                      ),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colorScheme.shadow.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.request_page_outlined,
                                          color: statusColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              requester.isEmpty
                                                  ? 'Certificate Request'
                                                  : requester,
                                              style: theme.textTheme.titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (details.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                details,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: colorScheme
                                                          .onSurface
                                                          .withValues(
                                                            alpha: 0.65,
                                                          ),
                                                    ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          status.toUpperCase(),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: statusColor,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                                      if (canOpen) ...[
                                        const SizedBox(width: 6),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          color: colorScheme.onSurface
                                              .withValues(alpha: 0.45),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme, {Object? error}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colorScheme.error.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.error_outline,
                      size: 40,
                      color: colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load requests',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check your connection and try again.',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Text(
                        'Details: $error',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.request_page_outlined,
                      size: 64,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No certificate requests',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the + button to create a new request.',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryRow(
    List<Map<String, dynamic>> allRows,
    ColorScheme colorScheme,
  ) {
    int pending = 0;
    int approved = 0;
    int rejected = 0;
    int completed = 0;

    for (final r in allRows) {
      final status = (r['status']?.toString().toLowerCase() ?? 'pending')
          .trim();
      if (status == 'approved') {
        approved++;
      } else if (status == 'rejected') {
        rejected++;
      } else {
        pending++;
      }
      if (status != 'pending') {
        completed++;
      }
    }

    final total = allRows.length;

    final items = <({String label, int count, Color color, String filter})>[
      (label: 'Total', count: total, color: colorScheme.primary, filter: 'all'),
      (
        label: 'Pending',
        count: pending,
        color: Colors.orange,
        filter: 'pending',
      ),
      (
        label: 'Approved',
        count: approved,
        color: Colors.green,
        filter: 'approved',
      ),
      (
        label: 'Rejected',
        count: rejected,
        color: Colors.red,
        filter: 'rejected',
      ),
      (
        label: 'Completed',
        count: completed,
        color: Colors.blueGrey,
        filter: 'completed',
      ),
    ];

    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final it = items[i];
          return _SummaryCard(
            label: it.label,
            count: it.count,
            color: it.color,
            selected: _statusFilter == it.filter,
            onTap: () {
              setState(() {
                _statusFilter = it.filter;
              });
            },
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SummaryCard({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 112,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CertificateRequestTypeScreen extends StatelessWidget {
  const _CertificateRequestTypeScreen();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New Certificate Request')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CertificateRequestTypeButton(
              label: 'Baptism',
              description: 'Request a baptism certificate',
              color: Colors.blue,
              icon: Icons.water_drop_outlined,
              onTap: () => Navigator.of(context).pop('Baptism'),
            ),
            const SizedBox(height: 12),
            _CertificateRequestTypeButton(
              label: 'Marriage',
              description: 'Request a marriage certificate',
              color: Colors.pink,
              icon: Icons.favorite_outline,
              onTap: () => Navigator.of(context).pop('Marriage'),
            ),
            const SizedBox(height: 12),
            _CertificateRequestTypeButton(
              label: 'Confirmation',
              description: 'Request a confirmation certificate',
              color: Colors.purple,
              icon: Icons.verified_outlined,
              onTap: () => Navigator.of(context).pop('Confirmation'),
            ),
            const SizedBox(height: 12),
            _CertificateRequestTypeButton(
              label: 'Death / Funeral',
              description: 'Request a death or funeral certificate',
              color: Colors.grey,
              icon: Icons.person_outline,
              onTap: () => Navigator.of(context).pop('Death'),
            ),
            const SizedBox(height: 12),
            _CertificateRequestTypeButton(
              label: 'Parish Certification',
              description: 'Request a parish certification letter',
              color: Colors.teal,
              icon: Icons.article_outlined,
              onTap: () => Navigator.of(context).pop('Parish Certification'),
            ),
            const Spacer(),
            Text(
              'Choose the type of certificate you need',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CertificateRequestTypeButton extends StatelessWidget {
  final String label;
  final String description;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _CertificateRequestTypeButton({
    required this.label,
    required this.description,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
