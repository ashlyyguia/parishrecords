import 'package:flutter/material.dart';
import '../../../services/admin_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    await _adminRepo.saveSettings(
      language: _language,
      timezone: _timezone,
      notify: _notify,
      autoBackup: _autoBackup,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final queryText = _logSearch.text.trim().toLowerCase();
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          Text('Application Settings & Audit Logs', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('General Settings', style: Theme.of(context).textTheme.titleMedium),
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
                  _SettingRow(label: 'Enable Notifications', child: Switch(value: _notify, onChanged: (v) => setState(() => _notify = v))),
                  _SettingRow(label: 'Auto Backups', child: Switch(value: _autoBackup, onChanged: (v) => setState(() => _autoBackup = v))),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _save, child: const Text('Save Changes'))),
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
                  Text('Audit Logs', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _logSearch,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search logs'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 360,
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('logs')
                          .orderBy('timestamp', descending: true)
                          .limit(200)
                          .snapshots(),
                      builder: (context, snap) {
                        final docs = snap.data?.docs ?? const [];
                        final list = docs.map((d) {
                          final m = d.data();
                          return {
                            'action': (m['action'] ?? '').toString(),
                            'details': (m['details'] ?? '').toString(),
                            'timestamp': (m['timestamp'] ?? '').toString(),
                          };
                        }).where((m) {
                          if (queryText.isEmpty) return true;
                          return m.values.any((v) => v.toString().toLowerCase().contains(queryText));
                        }).toList();
                        if (list.isEmpty) return const Center(child: Text('No logs'));
                        return ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const Divider(height: 0),
                          itemBuilder: (_, i) {
                            final m = list[i];
                            return ListTile(
                              leading: const Icon(Icons.history),
                              title: Text(m['action'] ?? 'Action'),
                              subtitle: Text(m['details'] ?? ''),
                              trailing: Text(m['timestamp'] ?? ''),
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
              Expanded(child: Align(alignment: Alignment.centerLeft, child: child)),
            ],
          ),
        );
      },
    );
  }
}
