import 'package:flutter/material.dart';
import '../../../services/notifications_repository.dart';

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({super.key});

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  final _searchCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final Set<String> _selected = {};
  String _tab = 'all'; // all | unread | archived

  bool _creating = false;

  final NotificationsRepository _repo = NotificationsRepository();

  Future<List<Map<String, dynamic>>>? _itemsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _itemsFuture = _loadItems();
    });
  }

  Future<List<Map<String, dynamic>>> _loadItems() async {
    final list = await _repo.listStrict(limit: 50);
    return list
        .map(
          (n) => {
            '_key': n.id,
            'title': n.title,
            'body': n.body,
            'read': n.read,
            'archived': n.archived,
            'createdAt': n.createdAt.toIso8601String(),
          },
        )
        .toList();
  }

  Future<void> _setRead(String id, bool read) async {
    await _repo.setRead(id, read);
    _reload();
  }

  Future<void> _archive(String id) async {
    await _repo.setArchived(id, true);
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _createNotification() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and message are required')),
      );
      return;
    }

    setState(() {
      _creating = true;
    });

    try {
      await _repo.create(title: title, body: body);

      if (!mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Notification sent')));

      setState(() {
        _creating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send notification: $e')),
      );
    }
  }

  Future<void> _bulkSetRead(bool read) async {
    if (_selected.isEmpty) return;
    final ids = _selected.toList();
    await _repo.bulkSetRead(ids, read);
    if (!mounted) return;
    setState(() => _selected.clear());
    _reload();
  }

  Future<void> _bulkArchive() async {
    if (_selected.isEmpty) return;
    final ids = _selected.toList();
    await _repo.bulkSetArchived(ids, true);
    if (!mounted) return;
    setState(() => _selected.clear());
    _reload();
  }

  Future<void> _showCreateDialog() async {
    _titleCtrl.clear();
    _bodyCtrl.clear();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('New notification'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyCtrl,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Message'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _creating
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _creating ? null : _createNotification,
              child: _creating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send'),
            ),
          ],
        );
      },
    );

    if (mounted) {
      _reload();
    }
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
                      const SizedBox(width: 12, height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _creating ? null : _showCreateDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('New notification'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _tab == 'all',
                onSelected: (_) {
                  setState(() {
                    _tab = 'all';
                  });
                },
              ),
              ChoiceChip(
                label: const Text('Unread'),
                selected: _tab == 'unread',
                onSelected: (_) {
                  setState(() {
                    _tab = 'unread';
                  });
                },
              ),
              ChoiceChip(
                label: const Text('Archived'),
                selected: _tab == 'archived',
                onSelected: (_) {
                  setState(() {
                    _tab = 'archived';
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: _selected.isEmpty ? null : () => _bulkSetRead(true),
                icon: const Icon(Icons.mark_email_read_outlined),
                label: const Text('Mark selected read'),
              ),
              TextButton.icon(
                onPressed: _selected.isEmpty ? null : () => _bulkSetRead(false),
                icon: const Icon(Icons.mark_email_unread_outlined),
                label: const Text('Mark selected unread'),
              ),
              TextButton.icon(
                onPressed: _selected.isEmpty ? null : () => _bulkArchive(),
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archive selected'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _itemsFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline),
                            const SizedBox(height: 8),
                            const Text('Failed to load notifications'),
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
                    separatorBuilder: (_, _) => const Divider(height: 0),
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
