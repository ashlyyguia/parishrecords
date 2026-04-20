// ignore_for_file: unnecessary_underscores, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/notifications_repository.dart';
import '../admin_design_system.dart';

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
  String _tab = 'all';

  bool _creating = false;
  String? _selectedUserId;
  bool _isBroadcast = true;
  List<Map<String, dynamic>> _usersList = [];
  bool _loadingUsers = false;

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

  Future<void> _createNotification(
    void Function(void Function()) setDialogState,
  ) async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and message are required')),
      );
      return;
    }

    setDialogState(() {
      _creating = true;
    });

    try {
      await _repo.create(title: title, body: body, userId: _isBroadcast ? null : _selectedUserId);

      if (!mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Notification sent')));

      setState(() {
        _creating = false;
      });
      _reload();
    } catch (e) {
      if (!mounted) return;
      setDialogState(() {
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

  Future<void> _fetchUsers() async {
    if (_usersList.isNotEmpty) return;
    setState(() => _loadingUsers = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('users').orderBy('email').limit(200).get();
      _usersList = snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'email': data['email']?.toString() ?? '',
          'name': data['display_name']?.toString() ?? data['name']?.toString() ?? '',
        };
      }).toList();
    } catch (_) {}
    if (mounted) setState(() => _loadingUsers = false);
  }

  Future<void> _showCreateDialog() async {
    _titleCtrl.clear();
    _bodyCtrl.clear();
    _isBroadcast = true;
    _selectedUserId = null;
    await _fetchUsers();

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.notifications_active,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  const Text('New Notification'),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      decoration: InputDecoration(
                        labelText: 'Title',
                        prefixIcon: const Icon(Icons.title),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _bodyCtrl,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Message',
                        prefixIcon: const Icon(Icons.message),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<bool>(
                            title: const Text('Broadcast'),
                            value: true,
                            groupValue: _isBroadcast,
                            onChanged: (v) => setDialogState(() => _isBroadcast = v!),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<bool>(
                            title: const Text('Specific User'),
                            value: false,
                            groupValue: _isBroadcast,
                            onChanged: (v) => setDialogState(() => _isBroadcast = v!),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                    if (!_isBroadcast) ...[
                      const SizedBox(height: 8),
                      if (_loadingUsers)
                        const Center(child: CircularProgressIndicator())
                      else
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: 'Select User',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          value: _selectedUserId,
                          items: _usersList.map((u) {
                            return DropdownMenuItem<String>(
                              value: u['id'],
                              child: Text('${u['name']} (${u['email']})'),
                            );
                          }).toList(),
                          onChanged: (v) => setDialogState(() => _selectedUserId = v),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _creating
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: _creating
                      ? null
                      : () => _createNotification(setDialogState),
                  icon: _creating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_creating ? 'Sending...' : 'Send'),
                ),
              ],
            );
          },
        );
      },
    );

    if (mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: AdminDesignSystem.pageBackground(context),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminDesignSystem.pageHeader(
                context,
                title: 'Notifications',
                subtitle: 'Manage system notifications and announcements',
                icon: Icons.notifications,
              ),
              const SizedBox(height: 20),
              Container(
                decoration: AdminDesignSystem.cardDecoration(context),
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 720;
                    return Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: isNarrow ? constraints.maxWidth : 340,
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: 'Search notifications...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: colorScheme.surfaceContainerHighest
                                  .withOpacity(0.5),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildTab('All', 'all', Icons.inbox),
                              _buildTab(
                                'Unread',
                                'unread',
                                Icons.mark_email_unread,
                              ),
                              _buildTab('Archived', 'archived', Icons.archive),
                            ],
                          ),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _creating ? null : _showCreateDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('New notification'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              if (_selected.isNotEmpty)
                Container(
                  decoration: AdminDesignSystem.cardDecoration(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Text(
                        '${_selected.length} selected',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _bulkSetRead(true),
                        icon: const Icon(Icons.mark_email_read_outlined),
                        label: const Text('Mark read'),
                      ),
                      TextButton.icon(
                        onPressed: () => _bulkSetRead(false),
                        icon: const Icon(Icons.mark_email_unread_outlined),
                        label: const Text('Mark unread'),
                      ),
                      TextButton.icon(
                        onPressed: () => _bulkArchive(),
                        icon: const Icon(Icons.archive_outlined),
                        label: const Text('Archive'),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => _selected.clear()),
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Container(
                  decoration: AdminDesignSystem.cardDecoration(context),
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
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: colorScheme.error,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Failed to load notifications',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${snap.error}',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.error,
                                  ),
                                ),
                                const SizedBox(height: 16),
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
                      Iterable<Map<String, dynamic>> it = list;
                      if (_tab == 'unread') {
                        it = it.where(
                          (m) =>
                              !(m['read'] == true) && !(m['archived'] == true),
                        );
                      }
                      if (_tab == 'archived') {
                        it = it.where((m) => m['archived'] == true);
                      }

                      final q = _searchCtrl.text.trim().toLowerCase();
                      if (q.isNotEmpty) {
                        it = it.where(
                          (m) => m.values.any(
                            (v) =>
                                v?.toString().toLowerCase().contains(q) ??
                                false,
                          ),
                        );
                      }

                      final items = it.toList();

                      if (items.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.notifications_off_outlined,
                                size: 64,
                                color: colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No notifications',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.outline,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Create a new notification to get started',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.outlineVariant,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final m = items[i];
                          final key = (m['_key'] ?? '').toString();
                          final read = m['read'] == true;
                          final archived = m['archived'] == true;
                          final selected = _selected.contains(key);

                          return _buildNotificationTile(
                            context,
                            key: key,
                            title: m['title']?.toString() ?? 'Notification',
                            body: m['body']?.toString() ?? '',
                            read: read,
                            archived: archived,
                            selected: selected,
                            createdAt: m['createdAt']?.toString(),
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

  Widget _buildTab(String label, String value, IconData icon) {
    final isSelected = _tab == value;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => setState(() => _tab = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTile(
    BuildContext context, {
    required String key,
    required String title,
    required String body,
    required bool read,
    required bool archived,
    required bool selected,
    String? createdAt,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primaryContainer.withOpacity(0.3)
            : read
            ? null
            : colorScheme.primaryContainer.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: read ? FontWeight.normal : FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!read)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'New',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
            if (archived)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.outline,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Archived',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            if (createdAt != null)
              Text(
                _formatDateTime(createdAt),
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: read ? 'Mark unread' : 'Mark read',
              onPressed: () => _setRead(key, !read),
              icon: Icon(
                read
                    ? Icons.mark_email_unread_outlined
                    : Icons.mark_email_read_outlined,
                color: colorScheme.primary,
              ),
            ),
            IconButton(
              tooltip: archived ? 'Already archived' : 'Archive',
              onPressed: archived ? null : () => _archive(key),
              icon: Icon(
                Icons.archive_outlined,
                color: archived ? colorScheme.outline : colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inDays > 365) {
        return '${(diff.inDays / 365).floor()} years ago';
      } else if (diff.inDays > 30) {
        return '${(diff.inDays / 30).floor()} months ago';
      } else if (diff.inDays > 7) {
        return '${(diff.inDays / 7).floor()} weeks ago';
      } else if (diff.inDays > 0) {
        return '${diff.inDays} days ago';
      } else if (diff.inHours > 0) {
        return '${diff.inHours} hours ago';
      } else if (diff.inMinutes > 0) {
        return '${diff.inMinutes} minutes ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return isoString;
    }
  }
}
