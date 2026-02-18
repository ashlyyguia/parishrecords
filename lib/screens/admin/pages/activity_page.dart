import 'package:flutter/material.dart';
import '../../../services/admin_repository.dart';

class AdminActivityPage extends StatefulWidget {
  const AdminActivityPage({super.key});

  @override
  State<AdminActivityPage> createState() => _AdminActivityPageState();
}

class _AdminActivityPageState extends State<AdminActivityPage> {
  String _filter = 'all'; // all | logs
  String _search = '';
  final Set<String> _selected = {}; // keys formatted as '<collection>|<docId>'
  List<String> _visibleKeys = const [];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 700;
              final gap = isNarrow ? 8.0 : 12.0;
              return Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: gap,
                runSpacing: gap,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('All')),
                      ButtonSegment(value: 'logs', label: Text('Logs')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) =>
                        setState(() => _filter = s.first),
                  ),
                  SizedBox(
                    width: isNarrow ? constraints.maxWidth : 360,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search',
                      ),
                      onChanged: (v) =>
                          setState(() => _search = v.trim().toLowerCase()),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value:
                            _visibleKeys.isNotEmpty &&
                            _selected.length == _visibleKeys.length,
                        tristate: true,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected
                                ..clear()
                                ..addAll(_visibleKeys);
                            } else {
                              _selected.clear();
                            }
                          });
                        },
                      ),
                      const Text('Select all'),
                      SizedBox(width: gap),
                      OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: _ActivityList(
                filter: _filter,
                search: _search,
                selected: _selected,
                onToggle: (key, value) {
                  setState(() {
                    if (value) {
                      _selected.add(key);
                    } else {
                      _selected.remove(key);
                    }
                  });
                },
                onVisibleKeys: (keys) {
                  _visibleKeys = keys;
                  // keep selection in sync with filter changes (no heavy setState)
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityList extends StatelessWidget {
  final String filter;
  final String search;
  final Set<String> selected;
  final void Function(String key, bool value) onToggle;
  final void Function(List<String> keys) onVisibleKeys;
  const _ActivityList({
    required this.filter,
    required this.search,
    required this.selected,
    required this.onToggle,
    required this.onVisibleKeys,
  });

  @override
  Widget build(BuildContext context) {
    return _ActivityListInner(
      filter: filter,
      search: search,
      selected: selected,
      onToggle: onToggle,
      onVisibleKeys: onVisibleKeys,
    );
  }
}

class _ActivityListInner extends StatefulWidget {
  final String filter;
  final String search;
  final Set<String> selected;
  final void Function(String key, bool value) onToggle;
  final void Function(List<String> keys) onVisibleKeys;

  const _ActivityListInner({
    required this.filter,
    required this.search,
    required this.selected,
    required this.onToggle,
    required this.onVisibleKeys,
  });

  @override
  State<_ActivityListInner> createState() => _ActivityListInnerState();
}

class _ActivityListInnerState extends State<_ActivityListInner> {
  int _reloadTick = 0;

  @override
  Widget build(BuildContext context) {
    final adminRepo = AdminRepository();
    final future = adminRepo.getLogs(limit: 200, days: 30);

    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(_reloadTick),
      future: future,
      builder: (context, logSnap) {
        if (logSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (logSnap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline),
                  const SizedBox(height: 8),
                  const Text('Failed to load activity'),
                  const SizedBox(height: 6),
                  Text(
                    'Details: ${logSnap.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _reloadTick++),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        var rawLogs = logSnap.data ?? const <Map<String, dynamic>>[];
        var logItems = rawLogs.map((m) {
          final ts = m['action_time'] ?? m['timestamp'];
          DateTime when;
          if (ts is String) {
            when = DateTime.tryParse(ts) ?? DateTime.now();
          } else {
            when = DateTime.now();
          }
          IconData icon;
          switch ((m['action'] ?? '').toString()) {
            case 'record_create':
              icon = Icons.add_circle_outline;
              break;
            case 'record_update':
              icon = Icons.edit_outlined;
              break;
            case 'record_delete':
              icon = Icons.delete_outline;
              break;
            case 'user_role_change':
              icon = Icons.admin_panel_settings_outlined;
              break;
            default:
              icon = Icons.event_note_outlined;
          }
          return {
            'type': 'log',
            'key':
                'logs|${m['user_id'] ?? ''}|${m['target_record_id'] ?? ''}|${ts ?? ''}',
            'when': when,
            'icon': icon,
            'title': (m['action'] ?? '').toString().replaceAll('_', ' '),
            'subtitle': (m['details'] ?? '').toString(),
          };
        }).toList();

        // Only logs are shown now; notifications have been removed
        List<Map<String, dynamic>> items = logItems;
        items.sort(
          (a, b) => (b['when'] as DateTime).compareTo(a['when'] as DateTime),
        );

        // Report visible keys to parent for select-all
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onVisibleKeys(items.map((e) => e['key'] as String).toList());
        });

        // Search filter
        if (widget.search.isNotEmpty) {
          items = items
              .where(
                (m) =>
                    (m['title'] as String).toLowerCase().contains(
                      widget.search,
                    ) ||
                    (m['subtitle'] as String).toLowerCase().contains(
                      widget.search,
                    ),
              )
              .toList();
        }

        if (items.isEmpty) {
          return const Center(child: Text('No activity'));
        }

        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 0),
          itemBuilder: (_, i) {
            final m = items[i];
            final key = m['key'] as String;
            final when = m['when'] as DateTime;
            final icon = m['icon'] as IconData;
            final title = m['title'] as String;
            final subtitle = m['subtitle'] as String;

            final isSelected = widget.selected.contains(key);
            return CheckboxListTile(
              value: isSelected,
              onChanged: (v) => widget.onToggle(key, v == true),
              title: Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                _timeAgo(when),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          },
        );
      },
    );
  }
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) {
    return 'just now';
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} min ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }
  if (diff.inDays == 1) {
    return 'Yesterday';
  }
  return '${diff.inDays} days ago';
}
