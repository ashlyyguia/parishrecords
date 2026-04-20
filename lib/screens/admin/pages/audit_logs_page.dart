import 'package:flutter/material.dart';

import '../../../services/admin_repository.dart';

class AdminAuditLogsPage extends StatefulWidget {
  const AdminAuditLogsPage({super.key});

  @override
  State<AdminAuditLogsPage> createState() => _AdminAuditLogsPageState();
}

class _AdminAuditLogsPageState extends State<AdminAuditLogsPage> {
  final _repo = AdminRepository();
  final _searchCtrl = TextEditingController();

  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _repo.getLogs(limit: 200, days: 365);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 32,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Audit Logs',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reload'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search logs',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: colorScheme.error,
                                ),
                                const SizedBox(height: 8),
                                const Text('Failed to load audit logs'),
                                const SizedBox(height: 6),
                                Text(
                                  'Details: ${snap.error}',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: _reload,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final query = _searchCtrl.text.trim().toLowerCase();
                      final raw = snap.data ?? const <Map<String, dynamic>>[];
                      final rows = query.isEmpty
                          ? raw
                          : raw
                                .where(
                                  (m) =>
                                      (m['action'] ?? '')
                                          .toString()
                                          .toLowerCase()
                                          .contains(query) ||
                                      (m['details'] ?? '')
                                          .toString()
                                          .toLowerCase()
                                          .contains(query) ||
                                      (m['user_id'] ?? '')
                                          .toString()
                                          .toLowerCase()
                                          .contains(query),
                                )
                                .toList();

                      if (rows.isEmpty) {
                        return Center(
                          child: Text(
                            'No logs found.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 0,
                          color: colorScheme.outline.withValues(alpha: 0.2),
                        ),
                        itemBuilder: (context, i) {
                          final m = rows[i];
                          final action = (m['action'] ?? '').toString();
                          final details = (m['details'] ?? '').toString();
                          final userId = (m['user_id'] ?? '').toString();
                          final ts = (m['timestamp'] ?? m['action_time'] ?? '')
                              .toString();

                          return ListTile(
                            title: Text(action.isEmpty ? 'Activity' : action),
                            subtitle: Text(
                              [
                                if (details.isNotEmpty) details,
                                if (userId.isNotEmpty) 'User: $userId',
                                if (ts.isNotEmpty) ts,
                              ].join('\n'),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
