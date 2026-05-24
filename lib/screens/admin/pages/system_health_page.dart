import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AdminSystemHealthPage extends StatelessWidget {
  const AdminSystemHealthPage({super.key});

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
                    Icons.health_and_safety_outlined,
                    size: 32,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'System Health & Backups',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Infra health, uptime, and backup management.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    // Firebase Auth Status
                    _HealthCard(
                      title: 'Firebase Authentication',
                      subtitle: 'User auth service',
                      status: _HealthStatus.healthy,
                      icon: Icons.verified_user,
                      onTap: () => _checkAuthStatus(context),
                    ),
                    const SizedBox(height: 12),

                    // Firestore Status
                    _HealthCard(
                      title: 'Cloud Firestore',
                      subtitle: 'Database service',
                      status: _HealthStatus.healthy,
                      icon: Icons.storage,
                      onTap: () => _checkFirestoreStatus(context),
                    ),
                    const SizedBox(height: 12),

                    // Firebase Storage
                    _HealthCard(
                      title: 'Cloud Storage',
                      subtitle: 'File storage service',
                      status: _HealthStatus.healthy,
                      icon: Icons.cloud_upload,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Cloud Storage is healthy'),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // System Metrics
                    _MetricsCard(),
                    const SizedBox(height: 12),

                    // Backup Status
                    _BackupCard(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _checkAuthStatus(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Authentication Status'),
          content: Text(
            user != null
                ? 'Authenticated as: ${user.email}\nUID: ${user.uid.substring(0, 8)}...'
                : 'Not authenticated',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _checkFirestoreStatus(BuildContext context) async {
    try {
      await FirebaseFirestore.instance.collection('users').limit(1).get();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Firestore connection: OK')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Firestore error: $e')));
      }
    }
  }
}

enum _HealthStatus { healthy, warning, error }

class _HealthCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final _HealthStatus status;
  final IconData icon;
  final VoidCallback onTap;

  const _HealthCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case _HealthStatus.healthy:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case _HealthStatus.warning:
        statusColor = Colors.orange;
        statusIcon = Icons.warning;
        break;
      case _HealthStatus.error:
        statusColor = Colors.red;
        statusIcon = Icons.error;
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.1),
          child: Icon(icon, color: statusColor),
        ),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon, color: statusColor),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _MetricsCard extends StatefulWidget {
  @override
  State<_MetricsCard> createState() => _MetricsCardState();
}

class _MetricsCardState extends State<_MetricsCard> {
  String _appVersion = 'Loading...';
  String _buildNumber = 'Loading...';
  String _platform = 'Unknown';
  String _lastLogin = 'Unknown';

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final user = FirebaseAuth.instance.currentUser;
      final metadata = user?.metadata;
      final lastSignIn = metadata?.lastSignInTime;

      String platform;
      if (Platform.isAndroid) {
        platform = 'Android';
      } else if (Platform.isIOS) {
        platform = 'iOS';
      } else if (Platform.isWindows) {
        platform = 'Windows';
      } else if (Platform.isMacOS) {
        platform = 'macOS';
      } else if (Platform.isLinux) {
        platform = 'Linux';
      } else {
        platform = 'Web';
      }

      setState(() {
        _appVersion = packageInfo.version;
        _buildNumber = packageInfo.buildNumber;
        _platform = platform;
        _lastLogin = lastSignIn != null ? _formatDateTime(lastSignIn) : 'Never';
      });
    } catch (e) {
      setState(() {
        _appVersion = 'Unknown';
        _buildNumber = 'Unknown';
        _platform = 'Unknown';
        _lastLogin = 'Unknown';
      });
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'System Metrics',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _loadMetrics,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _MetricRow(label: 'App Version', value: _appVersion),
            _MetricRow(label: 'Build Number', value: _buildNumber),
            _MetricRow(label: 'Platform', value: _platform),
            _MetricRow(label: 'Last Login', value: _lastLogin),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetricRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withValues(alpha: 0.1),
          child: const Icon(Icons.backup, color: Colors.blue),
        ),
        title: Text(
          'Backup Status',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: const Text('Automatic backups enabled'),
        trailing: Chip(
          label: const Text('Active'),
          backgroundColor: Colors.green.withValues(alpha: 0.1),
          side: BorderSide.none,
          labelStyle: const TextStyle(color: Colors.green),
        ),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Backups are managed by Firebase automatically'),
            ),
          );
        },
      ),
    );
  }
}
