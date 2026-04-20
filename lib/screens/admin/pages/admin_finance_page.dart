// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/app_loading.dart';
import '../../../services/donations_repository.dart';

/// Enhanced Admin Finance & Donations Monitoring
class AdminFinancePage extends ConsumerStatefulWidget {
  const AdminFinancePage({super.key});

  @override
  ConsumerState<AdminFinancePage> createState() => _AdminFinancePageState();
}

class _AdminFinancePageState extends ConsumerState<AdminFinancePage> {
  int _selectedPeriod = 2; // 0: Today, 1: Week, 2: Month, 3: Year
  int _refreshKey = 0; // Increment to reload donations list

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Finance & Donations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export Report',
            onPressed: () => _exportReport(),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => _recordDonation(context),
            icon: const Icon(Icons.add),
            label: const Text('Record Donation'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // Period Selector
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Today')),
                ButtonSegment(value: 1, label: Text('Week')),
                ButtonSegment(value: 2, label: Text('Month')),
                ButtonSegment(value: 3, label: Text('Year')),
              ],
              selected: {_selectedPeriod},
              onSelectionChanged: (v) =>
                  setState(() => _selectedPeriod = v.first),
            ),
          ),

          // Summary Cards & Donations List
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey(_refreshKey),
              future: _loadDonations(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoading(message: 'Loading donations...');
                }

                final donations = snapshot.data ?? [];

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _refreshKey++);
                  },
                  child: Column(
                    children: [
                      _buildSummaryCards(donations),
                      const SizedBox(height: 16),
                      Expanded(
                        child: donations.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                itemCount: donations.length,
                                itemBuilder: (context, index) {
                                  final data = donations[index];
                                  final donationId =
                                      data['id']?.toString() ?? '';
                                  return _DonationCard(
                                    donationId: donationId,
                                    data: data,
                                    onView: () => _viewDonationDetails(
                                      context,
                                      donationId,
                                      data,
                                    ),
                                    onEdit: () => _editDonation(
                                      context,
                                      donationId,
                                      data,
                                    ),
                                    onDelete: () =>
                                        _deleteDonation(context, donationId),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Map<String, double> _calculateAnalytics(
    List<Map<String, dynamic>> donations,
  ) {
    double total = 0;
    double tithes = 0;
    double projects = 0;
    double outreach = 0;

    for (final d in donations) {
      final amount = (d['amount'] as num?)?.toDouble() ?? 0;
      final campaign = (d['campaign'] ?? 'General').toString();
      total += amount;

      switch (campaign.toLowerCase()) {
        case 'tithes':
          tithes += amount;
          break;
        case 'projects':
          projects += amount;
          break;
        case 'outreach':
          outreach += amount;
          break;
      }
    }

    return {
      'total': total,
      'tithes': tithes,
      'projects': projects,
      'outreach': outreach,
    };
  }

  String _formatAmount(double amount) {
    if (amount == 0) return '₱0';
    if (amount >= 1000000) {
      return '₱${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '₱${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '₱${amount.toStringAsFixed(0)}';
  }

  Widget _buildSummaryCards(List<Map<String, dynamic>> donations) {
    final analytics = _calculateAnalytics(donations);

    final cards = [
      _FinanceCard(
        title: 'Total Donations',
        amount: _formatAmount(analytics['total']!),
        icon: Icons.volunteer_activism,
        color: Colors.teal,
      ),
      _FinanceCard(
        title: 'Tithes',
        amount: _formatAmount(analytics['tithes']!),
        icon: Icons.church,
        color: Colors.blue,
      ),
      _FinanceCard(
        title: 'Projects',
        amount: _formatAmount(analytics['projects']!),
        icon: Icons.build,
        color: Colors.orange,
      ),
      _FinanceCard(
        title: 'Outreach',
        amount: _formatAmount(analytics['outreach']!),
        icon: Icons.favorite,
        color: Colors.pink,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          // Mobile: Stack vertically
          return Column(
            children: cards
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: c,
                  ),
                )
                .toList(),
          );
        } else if (constraints.maxWidth < 1000) {
          // Tablet: 2 cards per row
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              children: cards
                  .map(
                    (c) => SizedBox(
                      width: (constraints.maxWidth - 48) / 2,
                      child: c,
                    ),
                  )
                  .toList(),
            ),
          );
        }
        // Desktop: 4 cards in a row
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: cards
                .map(
                  (c) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: c,
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadDonations() async {
    final repo = DonationsRepository();
    final donations = await repo.list(limit: 50);
    debugPrint('[Finance] Loaded ${donations.length} donations');
    if (donations.isNotEmpty) {
      debugPrint('[Finance] First donation: ${donations.first}');
    }
    return donations;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.volunteer_activism_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No donations recorded yet',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _recordDonation(context),
            icon: const Icon(Icons.add),
            label: const Text('Record First Donation'),
          ),
        ],
      ),
    );
  }

  Future<void> _recordDonation(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _RecordDonationDialog(),
    );

    if (result != null) {
      try {
        final repo = DonationsRepository();
        await repo.create(
          amount: (result['amount'] as num).toDouble(),
          method: result['method']?.toString() ?? 'cash',
          campaign: result['campaign']?.toString(),
          donorName: result['donorName']?.toString(),
          anonymous: result['anonymous'] == true,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Donation recorded successfully')),
          );
          setState(() => _refreshKey++); // Refresh the list
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  void _viewDonationDetails(
    BuildContext context,
    String donationId,
    Map<String, dynamic> data,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Donation Details',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            _DetailRow('Donor', data['donor_name'] ?? 'Anonymous'),
            _DetailRow('Amount', '₱${data['amount']?.toString() ?? '0'}'),
            _DetailRow('Category', data['campaign'] ?? 'General'),
            _DetailRow('Payment Method', data['method'] ?? 'Cash'),
            if (data['householdId'] != null)
              _DetailRow('Household', data['householdName'] ?? 'Unknown'),
            if (data['notes'] != null) _DetailRow('Notes', data['notes']),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _editDonation(context, donationId, data);
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.print),
                    label: const Text('Print Receipt'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _editDonation(
    BuildContext context,
    String donationId,
    Map<String, dynamic> data,
  ) {
    // Show edit dialog
  }

  Future<void> _deleteDonation(BuildContext context, String donationId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Donation'),
        content: const Text(
          'Are you sure you want to delete this donation record? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = DonationsRepository();
      await repo.delete(donationId);
      if (mounted) {
        setState(() => _refreshKey++);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Donation deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete donation: $e')),
        );
      }
    }
  }

  void _exportReport() {
    // Export to PDF/Excel
  }
}

class _FinanceCard extends StatelessWidget {
  final String title;
  final String amount;
  final IconData icon;
  final Color color;

  const _FinanceCard({
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              amount,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonationCard extends StatelessWidget {
  final String donationId;
  final Map<String, dynamic> data;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DonationCard({
    required this.donationId,
    required this.data,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final donorName = data['donor_name'] ?? 'Anonymous';
    final amount = data['amount']?.toString() ?? '0';
    final category = data['campaign'] ?? 'General';
    final paymentMethod = data['method'] ?? 'Cash';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getCategoryColor(category).withValues(alpha: 0.1),
          child: Icon(
            _getCategoryIcon(category),
            color: _getCategoryColor(category),
          ),
        ),
        title: Text(donorName),
        subtitle: Row(
          children: [
            Text(category),
            const SizedBox(width: 8),
            Icon(_getPaymentIcon(paymentMethod), size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(paymentMethod, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '₱$amount',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
          ],
        ),
        onTap: onView,
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'tithes':
        return Colors.blue;
      case 'projects':
        return Colors.orange;
      case 'outreach':
        return Colors.pink;
      default:
        return Colors.teal;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'tithes':
        return Icons.church;
      case 'projects':
        return Icons.build;
      case 'outreach':
        return Icons.favorite;
      default:
        return Icons.volunteer_activism;
    }
  }

  IconData _getPaymentIcon(String method) {
    switch (method.toLowerCase()) {
      case 'gcash':
        return Icons.account_balance_wallet;
      case 'bank':
        return Icons.account_balance;
      default:
        return Icons.payments;
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordDonationDialog extends StatefulWidget {
  const _RecordDonationDialog();

  @override
  State<_RecordDonationDialog> createState() => _RecordDonationDialogState();
}

class _RecordDonationDialogState extends State<_RecordDonationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _donorNameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _category = 'General';
  String _paymentMethod = 'Cash';

  @override
  void dispose() {
    _donorNameCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record Donation'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _donorNameCtrl,
                decoration: const InputDecoration(labelText: 'Donor Name'),
              ),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(labelText: 'Amount *'),
                keyboardType: TextInputType.number,
                validator: (v) => v?.isEmpty == true ? 'Required' : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: const [
                  DropdownMenuItem(value: 'Tithes', child: Text('Tithes')),
                  DropdownMenuItem(value: 'Projects', child: Text('Projects')),
                  DropdownMenuItem(value: 'Outreach', child: Text('Outreach')),
                  DropdownMenuItem(value: 'General', child: Text('General')),
                ],
                onChanged: (v) => setState(() => _category = v!),
              ),
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment Method'),
                items: const [
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'GCash', child: Text('GCash')),
                  DropdownMenuItem(
                    value: 'Bank Transfer',
                    child: Text('Bank Transfer'),
                  ),
                  DropdownMenuItem(value: 'Check', child: Text('Check')),
                ],
                onChanged: (v) => setState(() => _paymentMethod = v!),
              ),
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final donorName = _donorNameCtrl.text.trim();
              Navigator.pop(context, {
                'donorName': donorName.isEmpty ? null : donorName,
                'amount': double.tryParse(_amountCtrl.text) ?? 0,
                'campaign': _category,
                'method': _paymentMethod.toLowerCase(),
                'anonymous': donorName.isEmpty,
              });
            }
          },
          child: const Text('Record'),
        ),
      ],
    );
  }
}
