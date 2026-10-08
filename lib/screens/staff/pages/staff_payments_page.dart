import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/donations_repository.dart';
import '../../../utils/donation_display.dart';
import '../../admin/admin_design_system.dart';
import '../../admin/pages/admin_certificate_fees_page.dart'
    show RecordCertificateFeeForm;
import '../../admin/pages/admin_donations_page.dart' show RecordDonationForm;
import '../../admin/widgets/finance_module_design.dart'
    hide formatPaymentMethod;

/// Which kind of payment a [StaffPaymentsPage] records.
enum StaffPaymentKind { donation, certificateFee }

/// Staff can record walk-in cash donations and certificate fees, using the
/// same forms as the admin pages. They see only the entries they recorded
/// themselves (the full ledger stays with Finance and Admin); Finance is
/// notified of each new entry and reconciles it as usual.
class StaffPaymentsPage extends StatefulWidget {
  const StaffPaymentsPage({super.key, required this.kind});

  final StaffPaymentKind kind;

  @override
  State<StaffPaymentsPage> createState() => _StaffPaymentsPageState();
}

class _StaffPaymentsPageState extends State<StaffPaymentsPage> {
  final _repo = DonationsRepository();
  late Future<List<Map<String, dynamic>>> _future;

  bool get _isCert => widget.kind == StaffPaymentKind.certificateFee;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant StaffPaymentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) _reload();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final all = await _repo.listRecordedByMe();
    return all.where((d) {
      final isCert =
          (d['campaign'] ?? '').toString().trim().toLowerCase() == 'certificate';
      return _isCert ? isCert : !isCert;
    }).toList();
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _record() async {
    final result = await showFinanceFormSheet<Map<String, dynamic>>(
      context: context,
      style: FinanceModuleStyle.of(
        _isCert
            ? FinanceModuleKind.certificateFees
            : FinanceModuleKind.donations,
      ),
      title: _isCert ? 'Record certificate fee' : 'Record cash donation',
      child: _isCert
          ? const RecordCertificateFeeForm()
          : const RecordDonationForm(),
      actions: const [],
    );
    if (result == null) return;
    try {
      if (_isCert) {
        await _repo.create(
          amount: (result['amount'] as num).toDouble(),
          method: result['method']?.toString() ?? 'cash',
          campaign: 'certificate',
          certificateType: result['certificateType']?.toString(),
          donorName: result['payerName']?.toString(),
          anonymous: result['anonymous'] == true,
          createdAt: result['date'] as DateTime?,
        );
      } else {
        await _repo.createManualCashDonation(
          amount: (result['amount'] as num).toDouble(),
          campaign: result['campaign']?.toString(),
          donorName: result['donorName']?.toString(),
          anonymous: result['anonymous'] == true,
          createdAt: result['date'] as DateTime?,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isCert
                ? 'Certificate fee recorded. Finance has been notified.'
                : 'Donation recorded. Finance has been notified.',
          ),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    final pad = isCompact ? 12.0 : 24.0;
    return Container(
      decoration: AdminDesignSystem.pageBackground(context),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            child: AdminDesignSystem.pageHeader(
              context,
              title: _isCert ? 'Certificate Fees' : 'Donations',
              subtitle: _isCert
                  ? 'Record certificate fees paid at the parish office.'
                  : 'Record cash donations received at the parish office.',
              icon: _isCert
                  ? Icons.receipt_long_outlined
                  : Icons.volunteer_activism_outlined,
              actions: [
                AdminDesignSystem.actionButton(
                  context,
                  label: _isCert ? 'Add Certificate Fee' : 'Add Donation',
                  icon: Icons.add,
                  onPressed: _record,
                  isPrimary: true,
                ),
                AdminDesignSystem.actionButton(
                  context,
                  label: 'Refresh',
                  icon: Icons.refresh,
                  onPressed: _reload,
                  isPrimary: false,
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: Container(
                decoration: AdminDesignSystem.cardDecoration(context),
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return _message(
                        context,
                        Icons.error_outline,
                        'Could not load your entries.',
                        '${snap.error}',
                      );
                    }
                    final rows = snap.data ?? const [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Text(
                            'Recorded by you',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Expanded(
                          child: rows.isEmpty
                              ? _message(
                                  context,
                                  _isCert
                                      ? Icons.receipt_long_outlined
                                      : Icons.volunteer_activism_outlined,
                                  _isCert
                                      ? 'No certificate fees recorded yet'
                                      : 'No donations recorded yet',
                                  'Use the "Add" button to record one.',
                                )
                              : _list(context, rows),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, List<Map<String, dynamic>> rows) {
    final df = DateFormat('MMM d, yyyy');
    final money = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = rows[i];
        final created = r['created_at'];
        final date = created is DateTime ? df.format(created) : '—';
        final name = r['anonymous'] == true
            ? 'Anonymous'
            : ((r['donor_name'] ?? '').toString().trim().isEmpty
                ? '—'
                : r['donor_name'].toString());
        final what = _isCert
            ? 'Certificate: ${(r['certificate_type'] ?? '—')}'
            : donationTypeLabel(r);
        final reconciled = r['reconciled'] == true;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            child: Icon(
              _isCert ? Icons.receipt_long : Icons.payments_outlined,
              color: scheme.onPrimaryContainer,
              size: 20,
            ),
          ),
          title: Text(name),
          subtitle: Text(
            '$date · $what · ${formatPaymentMethod(donationPaymentMethodId(r))}',
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money.format((r['amount'] as num?) ?? 0),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                reconciled ? 'Reconciled' : 'Pending',
                style: TextStyle(
                  fontSize: 12,
                  color: reconciled ? Colors.green.shade700 : Colors.orange.shade800,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _message(
    BuildContext context,
    IconData icon,
    String title,
    String body,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
