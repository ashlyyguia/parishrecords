import 'package:flutter/material.dart';
import '../../../services/notifications_repository.dart';

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({super.key});

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  final _searchCtrl = TextEditingController();
  final Set<String> _selected = {};
  final String _tab = 'all'; // all | unread | archived

  final NotificationsRepository _repo = NotificationsRepository();

  Future<List<Map<String, dynamic>>> _loadItems() async {
    final rows = await _repo.listRaw(limit: 200);
    return rows
        .map(
          (m) => {
            '_key': (m['id'] ?? '').toString(),
            'title': (m['title'] ?? '').toString(),
            'body': (m['body'] ?? '').toString(),
            'read': m['read'] == true,
            'archived': m['archived'] == true,
            'createdAt': m['createdAt'],
          },
        )
        .where((m) {
          final title = (m['title'] ?? '').toString().toLowerCase();
          final body = (m['body'] ?? '').toString().toLowerCase();
          final text = '$title $body';
          final isAddRecord =
              text.contains('add record') ||
              text.contains('new record') ||
              text.contains('new parish record') ||
              text.contains('record added');
          final isCertRequest =
              text.contains('certificate request') ||
              text.contains('cert request');
          final isApproval =
              text.contains('approve') ||
              text.contains('approved') ||
              text.contains('decline') ||
              text.contains('declined');
          return (isAddRecord || isCertRequest) && !isApproval;
        })
        .toList();
  }

  Future<void> _setRead(String id, bool read) async {
    await _repo.setRead(id, read);
    setState(() {});
  }

  Future<void> _archive(String id) async {
    await _repo.setArchived(id, true);
    setState(() {});
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notifications',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 720;
                  return Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 0,
                    runSpacing: 0,
                    children: [
                      SizedBox(
                        width: isNarrow ? constraints.maxWidth : 340,
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Search notifications',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _loadItems(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  if (snap.hasError) {
                    return const Center(
                      child: Text('Error loading notifications'),
                    );
                  }
                  final list = snap.data ?? const <Map<String, dynamic>>[];
                  // filter by tab and search
                  Iterable<Map<String, dynamic>> it = list;
                  if (_tab == 'unread') {
                    it = it.where(
                      (m) => !(m['read'] == true) && !(m['archived'] == true),
                    );
                  }
                  if (_tab == 'archived') {
                    it = it.where((m) => m['archived'] == true);
                  }
                  final q = _searchCtrl.text.trim().toLowerCase();
                  if (q.isNotEmpty) {
                    it = it.where(
                      (m) => m.values.any(
                        (v) => v?.toString().toLowerCase().contains(q) ?? false,
                      ),
                    );
                  }
                  final items = it.toList();
                  if (items.isEmpty) {
                    return const Center(child: Text('No notifications'));
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 0),
                    itemBuilder: (_, i) {
                      final m = items[i];
                      final key = (m['_key'] ?? '').toString();
                      final read = m['read'] == true;
                      final archived = m['archived'] == true;
                      final selected = _selected.contains(key);
                      return ListTile(
                        leading: Checkbox(
                          value: selected,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selected.add(key);
                              } else {
                                _selected.remove(key);
                              }
                            });
                          },
                        ),
                        title: Text(
                          m['title']?.toString() ?? 'Notification',
                          style: TextStyle(
                            fontWeight: read
                                ? FontWeight.normal
                                : FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(m['body']?.toString() ?? ''),
                        trailing: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (archived)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Chip(label: Text('Archived')),
                                ),
                              if (!read)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Chip(label: Text('Unread')),
                                ),
                              IconButton(
                                tooltip: read ? 'Mark unread' : 'Mark read',
                                onPressed: () => _setRead(key, !read),
                                icon: Icon(
                                  read
                                      ? Icons.mark_email_unread_outlined
                                      : Icons.mark_email_read_outlined,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Archive',
                                onPressed: archived
                                    ? null
                                    : () => _archive(key),
                                icon: const Icon(Icons.archive_outlined),
                              ),
                            ],
                          ),
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
    );
  }
}
