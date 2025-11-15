import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminActivityPage extends StatefulWidget {
  const AdminActivityPage({super.key});

  @override
  State<AdminActivityPage> createState() => _AdminActivityPageState();
}

class _AdminActivityPageState extends State<AdminActivityPage> {
  String _filter = 'all'; // all | logs | notifications
  String _search = '';
  final Set<String> _selected = {}; // keys formatted as '<collection>|<docId>'
  List<String> _visibleKeys = const [];

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final key in _selected) {
      final parts = key.split('|');
      if (parts.length != 2) continue;
      final col = parts[0];
      final id = parts[1];
      if (col == 'notifications' || col == 'logs') {
        final ref = FirebaseFirestore.instance.collection(col).doc(id);
        batch.delete(ref);
      }
    }
    await batch.commit();
    if (mounted) setState(() => _selected.clear());
  }

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
                      ButtonSegment(value: 'notifications', label: Text('Notifications')),
                      ButtonSegment(value: 'logs', label: Text('Logs')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) => setState(() => _filter = s.first),
                  ),
                  SizedBox(
                    width: isNarrow ? constraints.maxWidth : 360,
                    child: TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search'),
                      onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _visibleKeys.isNotEmpty && _selected.length == _visibleKeys.length,
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
                        onPressed: _selected.isEmpty ? null : _deleteSelected,
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
          )
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
    final notifStream = FirebaseFirestore.instance
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
    final logStream = FirebaseFirestore.instance
        .collection('logs')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: (filter == 'logs') ? null : notifStream,
      builder: (context, notifSnap) {
        final notifItems = (notifSnap.data?.docs ?? const [])
            .map((d) {
              final m = d.data();
              final ts = m['createdAt'];
              DateTime when;
              if (ts is Timestamp) {
                when = ts.toDate();
              } else if (ts is String) {
                when = DateTime.tryParse(ts) ?? DateTime.now();
              } else {
                when = DateTime.now();
              }
              return {
                'type': 'notification',
                'key': 'notifications|${d.id}',
                'when': when,
                'icon': Icons.notifications_outlined,
                'title': (m['title'] ?? '').toString(),
                'subtitle': (m['body'] ?? '').toString(),
              };
            })
            .toList();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: (filter == 'notifications') ? null : logStream,
          builder: (context, logSnap) {
            final logItems = (logSnap.data?.docs ?? const [])
                .map((d) {
                  final m = d.data();
                  final ts = m['timestamp'];
                  DateTime when;
                  if (ts is Timestamp) {
                    when = ts.toDate();
                  } else if (ts is String) {
                    when = DateTime.tryParse(ts) ?? DateTime.now();
                  } else {
                    when = DateTime.now();
                  }
                  IconData icon;
                  switch ((m['action'] ?? '').toString()) {
                    case 'record_create':
                      icon = Icons.add_circle_outline; break;
                    case 'record_update':
                      icon = Icons.edit_outlined; break;
                    case 'record_delete':
                      icon = Icons.delete_outline; break;
                    case 'user_role_change':
                      icon = Icons.admin_panel_settings_outlined; break;
                    default:
                      icon = Icons.event_note_outlined;
                  }
                  return {
                    'type': 'log',
                    'key': 'logs|${d.id}',
                    'when': when,
                    'icon': icon,
                    'title': (m['action'] ?? '').toString().replaceAll('_', ' '),
                    'subtitle': (m['details'] ?? '').toString(),
                  };
                })
                .toList();

            // Merge according to filter
            List<Map<String, dynamic>> items;
            if (filter == 'notifications') {
              items = notifItems;
            } else if (filter == 'logs') {
              items = logItems;
            } else {
              items = <Map<String, dynamic>>[...notifItems, ...logItems];
            }
            items.sort((a, b) => (b['when'] as DateTime).compareTo(a['when'] as DateTime));

            // Report visible keys to parent for select-all
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onVisibleKeys(items.map((e) => e['key'] as String).toList());
            });

            // Search filter
            if (search.isNotEmpty) {
              items = items.where((m) =>
                (m['title']?.toString().toLowerCase().contains(search) ?? false) ||
                (m['subtitle']?.toString().toLowerCase().contains(search) ?? false)
              ).toList();
            }

            if (items.isEmpty) {
              if ((notifSnap.connectionState == ConnectionState.waiting && filter != 'logs') ||
                  (logSnap.connectionState == ConnectionState.waiting && filter != 'notifications')) {
                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              }
              return const Center(child: Text('No activity'));
            }

            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (_, i) {
                final m = items[i];
                final key = m['key'] as String;
                final isSelected = selected.contains(key);
                return ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: isSelected,
                        onChanged: (v) => onToggle(key, v == true),
                      ),
                      Icon(m['icon'] as IconData),
                    ],
                  ),
                  title: Text(m['title']?.toString() ?? ''),
                  subtitle: Text(m['subtitle']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Text(_timeAgo(m['when'] as DateTime), style: Theme.of(context).textTheme.bodySmall),
                );
              },
            );
          },
        );
      },
    );
  }
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  if (diff.inDays == 1) return 'Yesterday';
  return '${diff.inDays} days ago';
}
