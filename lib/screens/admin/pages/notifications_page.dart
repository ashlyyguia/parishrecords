import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({super.key});

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  final _searchCtrl = TextEditingController();
  final Set<String> _selected = {};
  String _tab = 'all'; // all | unread | archived

  Stream<List<Map<String, dynamic>>> _streamItems() {
    return FirebaseFirestore.instance
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final m = d.data();
              return {
                '_key': d.id,
                'title': (m['title'] ?? '').toString(),
                'body': (m['body'] ?? '').toString(),
                'read': m['read'] == true,
                'archived': m['archived'] == true,
                'createdAt': m['createdAt'],
              };
            }).toList());
  }

  Future<void> _setRead(String id, bool read) async {
    await FirebaseFirestore.instance.collection('notifications').doc(id).set({'read': read}, SetOptions(merge: true));
  }

  Future<void> _archive(String id) async {
    await FirebaseFirestore.instance.collection('notifications').doc(id).set({'archived': true}, SetOptions(merge: true));
  }

  Future<void> _bulk(bool? read, {bool archive = false}) async {
    if (_selected.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final id in _selected) {
      final ref = FirebaseFirestore.instance.collection('notifications').doc(id);
      if (archive) {
        batch.set(ref, {'archived': true}, SetOptions(merge: true));
      } else if (read != null) {
        batch.set(ref, {'read': read}, SetOptions(merge: true));
      }
    }
    await batch.commit();
    setState(() => _selected.clear());
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
          Text('Notifications', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 720;
                  final gap = isNarrow ? 8.0 : 12.0;
                  return Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'all', label: Text('All')),
                          ButtonSegment(value: 'unread', label: Text('Unread')),
                          ButtonSegment(value: 'archived', label: Text('Archived')),
                        ],
                        selected: {_tab},
                        onSelectionChanged: (s) => setState(() => _tab = s.first),
                      ),
                      SizedBox(
                        width: isNarrow ? constraints.maxWidth : 340,
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search notifications'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Compose'),
                        onPressed: _openCompose,
                      ),
                      OutlinedButton.icon(onPressed: _selected.isEmpty ? null : () => _bulk(true), icon: const Icon(Icons.mark_email_read_outlined), label: const Text('Mark read')),
                      OutlinedButton.icon(onPressed: _selected.isEmpty ? null : () => _bulk(false), icon: const Icon(Icons.mark_email_unread_outlined), label: const Text('Mark unread')),
                      OutlinedButton.icon(onPressed: _selected.isEmpty ? null : () => _bulk(null, archive: true), icon: const Icon(Icons.archive_outlined), label: const Text('Archive')),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _streamItems(),
                builder: (context, snap) {
                  final list = snap.data ?? const <Map<String, dynamic>>[];
                  // filter by tab and search
                  Iterable<Map<String, dynamic>> it = list;
                  if (_tab == 'unread') it = it.where((m) => !(m['read'] == true) && !(m['archived'] == true));
                  if (_tab == 'archived') it = it.where((m) => m['archived'] == true);
                  final q = _searchCtrl.text.trim().toLowerCase();
                  if (q.isNotEmpty) it = it.where((m) => m.values.any((v) => v?.toString().toLowerCase().contains(q) ?? false));
                  final items = it.toList();
                  if (items.isEmpty) return const Center(child: Text('No notifications'));
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
                        title: Text(m['title']?.toString() ?? 'Notification', style: TextStyle(fontWeight: read ? FontWeight.normal : FontWeight.w600)),
                        subtitle: Text(m['body']?.toString() ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (archived) const Padding(padding: EdgeInsets.only(right: 8), child: Chip(label: Text('Archived'))),
                            if (!read) const Padding(padding: EdgeInsets.only(right: 8), child: Chip(label: Text('Unread'))),
                            IconButton(
                              tooltip: read ? 'Mark unread' : 'Mark read',
                              onPressed: () => _setRead(key, !read),
                              icon: Icon(read ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined),
                            ),
                            IconButton(
                              tooltip: 'Archive',
                              onPressed: archived ? null : () => _archive(key),
                              icon: const Icon(Icons.archive_outlined),
                            ),
                          ],
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

extension on _AdminNotificationsPageState {
  Future<void> _openCompose() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String target = 'all'; // all | role | user
    String role = 'admin';
    final targetCtrl = TextEditingController(); // user uid/email

    await showDialog(
      context: context,
      builder: (ctx) {
        String localTarget = target;
        String localRole = role;
        return StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: const Text('Compose notification'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: bodyCtrl,
                    decoration: const InputDecoration(labelText: 'Body'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 480;
                      final gap = isNarrow ? 8.0 : 12.0;
                      return Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          const Text('Target:'),
                          DropdownButton<String>(
                            value: localTarget,
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All')),
                              DropdownMenuItem(value: 'role', child: Text('Role')),
                              DropdownMenuItem(value: 'user', child: Text('User')),
                            ],
                            onChanged: (v) => setD(() => localTarget = v ?? 'all'),
                          ),
                          if (localTarget == 'role')
                            DropdownButton<String>(
                              value: localRole,
                              items: const [
                                DropdownMenuItem(value: 'admin', child: Text('admin')),
                                DropdownMenuItem(value: 'staff', child: Text('staff')),
                                DropdownMenuItem(value: 'volunteer', child: Text('volunteer')),
                              ],
                              onChanged: (v) => setD(() => localRole = v ?? 'admin'),
                            )
                          else if (localTarget == 'user')
                            SizedBox(
                              width: isNarrow ? constraints.maxWidth : 260,
                              child: TextField(
                                controller: targetCtrl,
                                decoration: const InputDecoration(hintText: 'User UID'),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final title = titleCtrl.text.trim();
                  final body = bodyCtrl.text.trim();
                  if (title.isEmpty || body.isEmpty) return;
                  final data = <String, dynamic>{
                    'title': title,
                    'body': body,
                    'createdAt': FieldValue.serverTimestamp(),
                    'read': false,
                    'archived': false,
                  };
                  if (localTarget == 'role') data['role'] = localRole;
                  if (localTarget == 'user') data['userId'] = targetCtrl.text.trim();
                  await FirebaseFirestore.instance.collection('notifications').add(data);
                  if (context.mounted) Navigator.pop(ctx);
                },
                child: const Text('Send'),
              ),
            ],
          ),
        );
      },
    );
  }
}
