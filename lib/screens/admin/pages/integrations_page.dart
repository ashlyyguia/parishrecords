import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../firebase_options.dart';

class AdminIntegrationsPage extends StatefulWidget {
  const AdminIntegrationsPage({super.key});

  @override
  State<AdminIntegrationsPage> createState() => _AdminIntegrationsPageState();
}

class _AdminIntegrationsPageState extends State<AdminIntegrationsPage> {
  bool _showApiKeys = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final firebaseConfig = DefaultFirebaseOptions.web;

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
                    Icons.vpn_key_outlined,
                    size: 32,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Integrations & API Keys',
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
                'Manage payment providers, SMS, email, and external API tokens.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    // Firebase Configuration Card
                    _IntegrationCard(
                      title: 'Firebase Configuration',
                      subtitle:
                          'Core backend services (Auth, Firestore, Storage)',
                      icon: Icons.local_fire_department,
                      isConfigured: true,
                      onTap: () => setState(() => _showApiKeys = !_showApiKeys),
                      trailing: _showApiKeys
                          ? const Icon(Icons.expand_less)
                          : const Icon(Icons.expand_more),
                    ),
                    if (_showApiKeys) ...[
                      const SizedBox(height: 8),
                      _ConfigItem(
                        label: 'Project ID',
                        value: firebaseConfig.projectId,
                      ),
                      _ConfigItem(
                        label: 'Auth Domain',
                        value: firebaseConfig.authDomain,
                      ),
                      _ConfigItem(
                        label: 'Storage Bucket',
                        value: firebaseConfig.storageBucket,
                      ),
                      _ConfigItem(
                        label: 'Messaging Sender ID',
                        value: firebaseConfig.messagingSenderId,
                      ),
                      _ConfigItem(
                        label: 'Measurement ID',
                        value: firebaseConfig.measurementId,
                      ),
                    ],
                    const SizedBox(height: 12),

                    // Payment Providers
                    _IntegrationCard(
                      title: 'Payment Providers',
                      subtitle: 'Stripe, PayPal, GCash (not configured)',
                      icon: Icons.payment,
                      isConfigured: false,
                      onTap: () =>
                          _showConfigureDialog(context, 'Payment Providers'),
                    ),
                    const SizedBox(height: 12),

                    // Email Service
                    _IntegrationCard(
                      title: 'Email Service',
                      subtitle: 'SendGrid, Mailgun (using Firebase fallback)',
                      icon: Icons.email,
                      isConfigured: true,
                      onTap: () =>
                          _showConfigureDialog(context, 'Email Service'),
                    ),
                    const SizedBox(height: 12),

                    // SMS Service
                    _IntegrationCard(
                      title: 'SMS Service',
                      subtitle: 'Twilio, Vonage (not configured)',
                      icon: Icons.sms,
                      isConfigured: false,
                      onTap: () => _showConfigureDialog(context, 'SMS Service'),
                    ),
                    const SizedBox(height: 12),

                    // Cloud Storage
                    _IntegrationCard(
                      title: 'Cloud Storage',
                      subtitle: 'Firebase Storage (configured)',
                      icon: Icons.cloud_upload,
                      isConfigured: true,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Cloud Storage is configured'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConfigureDialog(BuildContext context, String integration) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Configure $integration'),
        content: Text(
          'To configure $integration, you need to:\n\n'
          '1. Create an account with the provider\n'
          '2. Obtain API credentials\n'
          '3. Add them to your backend configuration\n\n'
          'Contact your developer to set this up.',
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

class _IntegrationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isConfigured;
  final VoidCallback onTap;
  final Widget? trailing;

  const _IntegrationCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isConfigured,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isConfigured
              ? Colors.green.withValues(alpha: 0.1)
              : Colors.orange.withValues(alpha: 0.1),
          child: Icon(icon, color: isConfigured ? Colors.green : Colors.orange),
        ),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Row(
          children: [
            Icon(
              isConfigured ? Icons.check_circle : Icons.pending,
              size: 14,
              color: isConfigured ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 4),
            Expanded(child: Text(subtitle, style: theme.textTheme.bodySmall)),
          ],
        ),
        trailing:
            trailing ??
            (isConfigured
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.settings)),
        onTap: onTap,
      ),
    );
  }
}

class _ConfigItem extends StatelessWidget {
  final String label;
  final String? value;

  const _ConfigItem({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayValue = value ?? 'Not set';

    return Card(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: ListTile(
        dense: true,
        title: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          displayValue,
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: displayValue));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label copied to clipboard')),
            );
          },
        ),
      ),
    );
  }
}
