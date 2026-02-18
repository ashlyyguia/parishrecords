import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../services/admin_repository.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  String _language = 'en';
  String _timezone = 'UTC';
  bool _notify = true;
  bool _autoBackup = false;
  final _logSearch = TextEditingController();
  DateTime? _logFrom;
  DateTime? _logTo;
  bool _loading = true;
  final _adminRepo = AdminRepository();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final d = await _adminRepo.getSettings();
      _language = (d['language'] ?? 'en').toString();
      _timezone = (d['timezone'] ?? 'UTC').toString();
      _notify = d['notify'] == null ? true : d['notify'] == true;
      _autoBackup = (d['auto_backup'] == true) || (d['autoBackup'] == true);
    } catch (_) {
      // fallback to defaults on error
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    try {
      await _adminRepo.saveSettings(
        language: _language,
        timezone: _timezone,
        notify: _notify,
        autoBackup: _autoBackup,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Settings saved')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save settings: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final queryText = _logSearch.text.trim().toLowerCase();
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          Text(
            'Application Settings & Audit Logs',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'General Settings',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (_loading) const LinearProgressIndicator(),
                  _SettingRow(
                    label: 'Default Language',
                    child: DropdownButton<String>(
                      value: _language,
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                      ],
                      onChanged: (v) => setState(() => _language = v ?? 'en'),
                    ),
                  ),
                  _SettingRow(
                    label: 'Timezone',
                    child: DropdownButton<String>(
                      value: _timezone,
                      items: const [
                        DropdownMenuItem(value: 'UTC', child: Text('UTC')),
                      ],
                      onChanged: (v) => setState(() => _timezone = v ?? 'UTC'),
                    ),
                  ),
                  _SettingRow(
                    label: 'Enable Notifications',
                    child: Switch(
                      value: _notify,
                      onChanged: (v) => setState(() => _notify = v),
                    ),
                  ),
                  _SettingRow(
                    label: 'Auto Backups',
                    child: Switch(
                      value: _autoBackup,
                      onChanged: (v) => setState(() => _autoBackup = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Audit Logs',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _logSearch,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search logs',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            _logFrom == null
                                ? 'From: All'
                                : 'From: ${DateFormat('yMMMd').format(_logFrom!)}',
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _logFrom ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null && mounted) {
                              setState(() {
                                _logFrom = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                );
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            _logTo == null
                                ? 'To: Today'
                                : 'To: ${DateFormat('yMMMd').format(_logTo!)}',
                          ),
                          onPressed: () async {
                            final initial = _logTo ?? DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null && mounted) {
                              setState(() {
                                _logTo = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                  23,
                                  59,
                                  59,
                                );
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 360,
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: _adminRepo.getLogs(limit: 200, days: 365),
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
                                  const Text('Failed to load audit logs'),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Details: ${snap.error}',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: () => setState(() {}),
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        // Normalize date range: if both are set and From > To, swap them
                        DateTime? from = _logFrom;
                        DateTime? to = _logTo;
                        if (from != null && to != null && from.isAfter(to)) {
                          final tmp = from;
                          from = to;
                          to = tmp;
                        }

                        final raw = snap.data ?? const <Map<String, dynamic>>[];
                        final list = raw
                            .map((m) {
                              final tsRaw = m['action_time'] ?? m['timestamp'];
                              final dt = DateTime.tryParse(
                                tsRaw?.toString() ?? '',
                              );
                              final action = (m['action'] ?? '').toString();
                              final details = (m['details'] ?? '').toString();

                              // Try to extract email from details like "User someone@mail.com logged in"
                              String email = '';
                              final emailMatch = RegExp(
                                r'User\s+([^\s]+)\s+logged',
                              ).firstMatch(details);
                              if (emailMatch != null) {
                                email = emailMatch.group(1) ?? '';
                              }

                              final time = dt != null
                                  ? DateFormat('H:mm').format(dt)
                                  : '';

                              final dateLabel = dt != null
                                  ? DateFormat('yMMMd').format(dt)
                                  : '';

                              final userName = email.isNotEmpty
                                  ? email.split('@').first
                                  : 'User';

                              final title = action == 'login'
                                  ? userName
                                  : action == 'logout'
                                  ? userName
                                  : action.replaceAll('_', ' ');

                              final status = action == 'login'
                                  ? 'Logged in'
                                  : action == 'logout'
                                  ? 'Logged out'
                                  : details;

                              return {
                                'action': action,
                                'title': title,
                                'details': details,
                                'email': email,
                                'time': time,
                                'dateLabel': dateLabel,
                                'userName': userName,
                                'status': status,
                                'timestamp': dt,
                              };
                            })
                            .where((m) {
                              final dt = m['timestamp'] as DateTime?;
                              if (from != null &&
                                  (dt == null || dt.isBefore(from))) {
                                return false;
                              }
                              if (to != null &&
                                  (dt == null || dt.isAfter(to))) {
                                return false;
                              }
                              if (queryText.isEmpty) return true;
                              return m.values.any(
                                (v) => v.toString().toLowerCase().contains(
                                  queryText,
                                ),
                              );
                            })
                            .toList();
                        if (list.isEmpty) {
                          return const Center(child: Text('No logs'));
                        }
                        return ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const Divider(height: 0),
                          itemBuilder: (_, i) {
                            final m = list[i];
                            final title = (m['title'] ?? 'User').toString();
                            final email = (m['email'] ?? '').toString();
                            final time = (m['time'] ?? '').toString();
                            final status = (m['status'] ?? '').toString();
                            return ListTile(
                              leading: const Icon(Icons.history),
                              title: Text(title),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(email, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          status,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${m['dateLabel'] ?? ''} $time',
                                        textAlign: TextAlign.right,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _SettingRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 420;
        if (isNarrow) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: child),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 200, child: Text(label)),
              const SizedBox(width: 12),
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: child),
              ),
            ],
          ),
        );
      },
    );
  }
}
