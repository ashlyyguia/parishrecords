import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/parish_payment_config.dart';
import '../screens/landing/landing_common.dart';
import '../services/donations_repository.dart';
import 'payment_qr_card.dart';

enum OnlineDonationVisualStyle { landing, app }

/// Online donation wizard.
/// Landing: type → name → QR code (3 steps).
/// App: type → personal info → amount & wallet → pay (4 steps).
class OnlineDonationFlow extends StatefulWidget {
  const OnlineDonationFlow({
    super.key,
    this.visualStyle = OnlineDonationVisualStyle.landing,
    this.onCompleted,
    this.prefillName,
    this.prefillEmail,
    this.prefillPhone,
  });

  final OnlineDonationVisualStyle visualStyle;
  final VoidCallback? onCompleted;
  final String? prefillName;
  final String? prefillEmail;
  final String? prefillPhone;

  @override
  State<OnlineDonationFlow> createState() => _OnlineDonationFlowState();
}

class _OnlineDonationFlowState extends State<OnlineDonationFlow> {
  int _step = 0;
  late String _donationType;
  String _paymentMethodId = ParishPaymentConfig.methods.first.id;
  int _amount = 500;
  bool _useCustomAmount = false;
  bool _submitting = false;
  bool _saveSuccess = false;
  String? _savedDonationId;
  String? _saveError;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _message = TextEditingController();
  final _customAmount = TextEditingController();

  bool get _isLanding =>
      widget.visualStyle == OnlineDonationVisualStyle.landing;

  List<String> get _stepLabels => _isLanding
      ? const ['Type', 'Name', 'QR Code']
      : const ['Type', 'Your info', 'Amount', 'Pay'];

  List<String> get _donationTypeOptions => _isLanding
      ? ParishPaymentConfig.landingDonationTypes
      : ParishPaymentConfig.donationTypes;

  Color get _primary =>
      _isLanding ? LandingCommon.primary : Theme.of(context).colorScheme.primary;

  @override
  void initState() {
    super.initState();
    _donationType = _donationTypeOptions.first;
    if (_isLanding) {
      _amount = 0;
      _paymentMethodId = 'gcash';
    }
    _name.text = widget.prefillName ?? '';
    _email.text = widget.prefillEmail ?? '';
    _phone.text = widget.prefillPhone ?? '';
    if (!_isLanding) {
      _customAmount.addListener(_onCustomAmountInput);
    }
  }

  @override
  void dispose() {
    if (!_isLanding) {
      _customAmount.removeListener(_onCustomAmountInput);
    }
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _message.dispose();
    _customAmount.dispose();
    super.dispose();
  }

  void _onCustomAmountInput() {
    if (_isLanding || _step != 2) return;
    final v = double.tryParse(_customAmount.text.trim());
    if (v != null && v > 0) {
      setState(() => _useCustomAmount = true);
    }
  }

  void _resetLandingSaveState() {
    _saveSuccess = false;
    _savedDonationId = null;
    _saveError = null;
  }

  double get _resolvedAmount {
    if (_useCustomAmount) {
      final v = double.tryParse(_customAmount.text.trim());
      return v != null && v > 0 ? v : 0;
    }
    return _amount.toDouble();
  }

  ParishPaymentMethod? get _selectedPayment =>
      ParishPaymentMethod.byId(_paymentMethodId);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStepper(),
        const SizedBox(height: 28),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(
            key: ValueKey('$_step-$_isLanding'),
            child: _buildStepContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildStepper() {
    return Row(
      children: List.generate(_stepLabels.length, (index) {
        final isActive = _step >= index;
        final isDone = _step > index;
        return Expanded(
          child: Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isActive ? _primary : Colors.grey.shade100,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isActive ? _primary : Colors.grey.shade300,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: isDone
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Text(
                            '${index + 1}',
                            style: _labelStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isActive
                                  ? Colors.white
                                  : Colors.grey.shade600,
                            ),
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _stepLabels[index],
                    style: _labelStyle(
                      fontSize: 10,
                      color: isActive ? _primary : Colors.grey.shade500,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              if (index < _stepLabels.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 18),
                    color: isActive ? _primary : Colors.grey.shade200,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStepContent() {
    if (_isLanding) {
      switch (_step) {
        case 0:
          return _buildTypeStep();
        case 1:
          return _buildNameStep();
        default:
          return _buildLandingQrStep();
      }
    }
    switch (_step) {
      case 0:
        return _buildTypeStep();
      case 1:
        return _buildPersonalInfoStep();
      case 2:
        return _buildAmountStep();
      default:
        return _buildPaymentStep();
    }
  }

  Widget _buildTypeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          _isLanding ? 'Type of donation' : 'Select donation type',
        ),
        const SizedBox(height: 16),
        ..._donationTypeOptions.map((t) {
          final selected = _donationType == t;
          if (_isLanding) {
            return _buildLandingTypeTile(t, selected);
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => setState(() => _donationType = t),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: selected
                      ? _primary.withValues(alpha: 0.06)
                      : (_isLanding ? LandingCommon.bg : null),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? _primary : Colors.grey.shade200,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? _primary : Colors.grey.shade400,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(t, style: _labelStyle(fontSize: 15))),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 24),
        _buildNextButton(),
      ],
    );
  }

  Widget _buildLandingTypeTile(String label, bool selected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? LandingCommon.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => setState(() => _donationType = label),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: Text(
              label,
              style: LandingCommon.bodyStyle(
                fontSize: 16,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? LandingCommon.primary : const Color(0xFF334155),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Landing step 2: donor name only.
  Widget _buildNameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Your name'),
        const SizedBox(height: 8),
        Text(
          'Enter the name of the person making this donation.',
          style: _labelStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        _buildField(_name, 'Full name', Icons.person_outline),
        const SizedBox(height: 24),
        Row(
          children: [
            _buildBackButton(),
            const SizedBox(width: 16),
            Expanded(child: _buildNextButton(onPressed: _validateNameStep)),
          ],
        ),
      ],
    );
  }

  bool _validateNameStep() {
    if (_name.text.trim().isEmpty) {
      _showError('Please enter your name.');
      return false;
    }
    setState(() {
      _step++;
      _resetLandingSaveState();
      if (_isLanding) {
        _paymentMethodId = 'gcash';
      }
    });
    return false;
  }

  Widget _buildPersonalInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Personal information'),
        const SizedBox(height: 8),
        Text(
          'We use this to acknowledge your gift and match your transfer.',
          style: _labelStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        _buildField(_name, 'Full name *', Icons.person_outline),
        const SizedBox(height: 12),
        _buildField(_email, 'Email address *', Icons.email_outlined,
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 12),
        _buildField(_phone, 'Contact number *', Icons.phone_outlined,
            keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        _buildField(_message, 'Message (optional)', Icons.notes_outlined,
            maxLines: 2),
        const SizedBox(height: 24),
        Row(
          children: [
            _buildBackButton(),
            const SizedBox(width: 16),
            Expanded(child: _buildNextButton(onPressed: _validatePersonalInfo)),
          ],
        ),
      ],
    );
  }

  bool _validatePersonalInfo() {
    if (_name.text.trim().isEmpty) {
      _showError('Please enter your full name.');
      return false;
    }
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError('Please enter a valid email address.');
      return false;
    }
    if (_phone.text.trim().isEmpty) {
      _showError('Please enter your contact number.');
      return false;
    }
    setState(() => _step++);
    return false;
  }

  Widget _buildAmountStep() {
    const presets = [100, 500, 1000, 1500, 2000, 5000];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Donation amount'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: presets.map((a) {
            final active = !_useCustomAmount && _amount == a;
            return InkWell(
              onTap: () => setState(() {
                _useCustomAmount = false;
                _amount = a;
              }),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 96,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: active
                      ? _primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active ? _primary : Colors.grey.shade200,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '₱$a',
                  style: _labelStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : null,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Custom amount', style: _labelStyle(fontSize: 14)),
          value: _useCustomAmount,
          activeThumbColor: _primary,
          onChanged: (v) => setState(() => _useCustomAmount = v),
        ),
        if (_useCustomAmount)
          _buildField(
            _customAmount,
            'Enter amount (₱)',
            Icons.payments_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        const SizedBox(height: 24),
        _sectionTitle('Payment method', fontSize: 18),
        const SizedBox(height: 12),
        ...ParishPaymentConfig.methods.map(_buildPaymentMethodTile),
        const SizedBox(height: 24),
        Row(
          children: [
            _buildBackButton(),
            const SizedBox(width: 16),
            Expanded(child: _buildNextButton(onPressed: _validateAmountStep)),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentMethodTile(ParishPaymentMethod m) {
    final selected = _paymentMethodId == m.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _paymentMethodId = m.id),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? m.brandColor : Colors.grey.shade200,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: m.brandColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                m.label,
                style: _labelStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? m.brandColor : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _validateAmountStep() {
    if (_resolvedAmount <= 0) {
      _showError('Please select or enter a valid amount.');
      return false;
    }
    setState(() => _step++);
    return false;
  }

  /// Landing step 3: GCash QR only → pay in GCash → auto-save → show record.
  Widget _buildLandingQrStep() {
    final payment = ParishPaymentMethod.byId('gcash');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Pay with GCash'),
        const SizedBox(height: 8),
        Text(
          'Scan the QR code and enter your amount in the GCash app. '
          'After you complete the payment, tap the button below to save your '
          'donation record for parish finance.',
          style: _labelStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        if (payment != null)
          LayoutBuilder(
            builder: (context, constraints) {
              final qrSize = (constraints.maxWidth * 0.92).clamp(160.0, 360.0);
              return Center(
                child: PaymentQrCard(method: payment, qrSize: qrSize),
              );
            },
          ),
        const SizedBox(height: 20),
        if (_submitting)
          _buildLandingStatusCard(
            icon: Icons.sync,
            color: _primary,
            title: 'Saving your donation…',
            subtitle: 'Recording your gift for Admin and Finance.',
            spinning: true,
          )
        else if (_saveSuccess)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLandingStatusCard(
                icon: Icons.check_circle,
                color: Colors.green.shade700,
                title: 'Donation recorded',
                subtitle:
                    'Thank you, ${_name.text.trim()}! Your gift is on file. '
                    'Finance will match the amount from your GCash transfer.',
              ),
              const SizedBox(height: 16),
              _buildLandingSavedRecordCard(),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _resetForm,
                child: const Text('Make another donation'),
              ),
            ],
          )
        else if (_saveError != null)
          _buildLandingStatusCard(
            icon: Icons.error_outline,
            color: Colors.red.shade700,
            title: 'Could not save donation',
            subtitle: _saveError!,
          )
        else
          _buildLandingStatusCard(
            icon: Icons.qr_code_scanner,
            color: _primary,
            title: 'Paid with GCash?',
            subtitle:
                'After you scan and pay, tap the button below to save your '
                'donation record for Admin and Finance (no sign-in required).',
          ),
        if (!_saveSuccess) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting ? null : () => _submitLandingGcash(),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_alt),
              label: Text(
                _submitting ? 'Saving…' : 'I paid with GCash — save record',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [_buildBackButton()]),
        ],
      ],
    );
  }

  Widget _buildLandingSavedRecordCard() {
    final ref = _savedDonationId;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LandingCommon.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LandingCommon.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: LandingCommon.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                'Your donation record',
                style: _labelStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: LandingCommon.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (ref != null && ref.isNotEmpty)
            _summaryRow('Reference', '${ref.substring(0, 8).toUpperCase()}…'),
          _summaryRow('Type', _donationType),
          _summaryRow('Name', _name.text.trim()),
          _summaryRow('Payment', 'GCash'),
          _summaryRow('Amount', 'Pending (entered in GCash)'),
          _summaryRow('Status', 'Recorded — visible in Admin & Finance'),
        ],
      ),
    );
  }

  Widget _buildLandingStatusCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    bool spinning = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (spinning)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
              ),
            )
          else
            Icon(icon, color: color, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _labelStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(subtitle, style: _labelStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStep() {
    final payment = _selectedPayment;
    final amount = _resolvedAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Scan to pay'),
        const SizedBox(height: 8),
        Text(
          'Transfer ₱${amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2)} using your chosen wallet, then confirm below.',
          style: _labelStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),
        if (payment != null)
          LayoutBuilder(
            builder: (context, constraints) {
              final qrSize = (constraints.maxWidth * 0.88).clamp(260.0, 320.0);
              return Center(
                child: PaymentQrCard(method: payment, qrSize: qrSize),
              );
            },
          ),
        const SizedBox(height: 20),
        Text(
          'Other wallets',
          style: _labelStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 520;
            final others = ParishPaymentConfig.methods
                .where((m) => m.id != _paymentMethodId)
                .toList();
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: others
                    .map(
                      (m) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: PaymentQrCard(method: m, qrSize: 120, compact: true),
                        ),
                      ),
                    )
                    .toList(),
              );
            }
            return Column(
              children: others
                  .map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: PaymentQrCard(method: m, qrSize: 140, compact: true),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 24),
        _buildSummaryCard(amount),
        const SizedBox(height: 24),
        Row(
          children: [
            _buildBackButton(),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: Text(_submitting ? 'Saving…' : 'I have transferred'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _primary.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(double amount) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isLanding
            ? LandingCommon.bg
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _summaryRow('Type', _donationType),
          const Divider(height: 20),
          _summaryRow('Name', _name.text.trim()),
          if (!_isLanding) ...[
            _summaryRow('Email', _email.text.trim()),
            _summaryRow('Phone', _phone.text.trim()),
          ],
          const Divider(height: 20),
          _summaryRow('Payment', _selectedPayment?.label ?? _paymentMethodId),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: _labelStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(
                '₱${amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2)}',
                style: _labelStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: _labelStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: _labelStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitLandingGcash() async {
    if (_name.text.trim().isEmpty) {
      _showError('Please enter your name on the previous step.');
      return;
    }
    if (_saveSuccess) return;

    setState(() {
      _submitting = true;
      _saveSuccess = false;
      _saveError = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final donationId = await DonationsRepository().saveLandingGcashDonation(
        donorName: _name.text.trim(),
        donationType: _donationType,
        email: user?.email,
        phone: null,
      );
      if (!mounted) return;
      setState(() {
        _saveSuccess = true;
        _savedDonationId = donationId;
        _submitting = false;
        _saveError = null;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _submitting = false;
        _saveError = msg.contains('permission-denied')
            ? 'Permission denied. Deploy Firestore rules: firebase deploy --only firestore:rules'
            : 'Save failed: $msg';
      });
      _showError(_saveError!);
    }
  }

  Future<void> _submit({bool auto = false, bool gcashPendingAmount = false}) async {
    if (_isLanding) {
      await _submitLandingGcash();
      return;
    }

    if (!gcashPendingAmount && _resolvedAmount <= 0) {
      if (!auto) _showError('Please enter the amount you transferred.');
      return;
    }

    if (_saveSuccess && auto) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!auto) _showError('Please sign in to save your donation.');
      return;
    }

    final email = _email.text.trim().isNotEmpty
        ? _email.text.trim()
        : (user.email ?? '');
    final phone = _phone.text.trim().isNotEmpty ? _phone.text.trim() : '—';

    setState(() => _submitting = true);
    try {
      final donationId = await DonationsRepository().createOnlineDonation(
        amount: gcashPendingAmount ? 0 : _resolvedAmount,
        donationType: _donationType,
        paymentMethod: gcashPendingAmount ? 'gcash' : _paymentMethodId,
        donorName: _name.text.trim(),
        email: email,
        phone: phone,
        message: _message.text.trim().isEmpty ? null : _message.text.trim(),
        gcashAmountPending: gcashPendingAmount,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Thank you, ${_name.text.trim()}! Your donation was recorded for parish finance.',
          ),
        ),
      );
      if (widget.onCompleted != null) {
        widget.onCompleted!();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      } else {
        _resetForm();
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Could not save donation: $e');
    } finally {
      if (mounted && !_saveSuccess) {
        setState(() => _submitting = false);
      }
    }
  }

  void _resetForm() {
    setState(() {
      _step = 0;
      _amount = _isLanding ? 0 : 500;
      _useCustomAmount = false;
      _donationType = _donationTypeOptions.first;
      _paymentMethodId = ParishPaymentConfig.methods.first.id;
      _resetLandingSaveState();
      _name.clear();
      _email.clear();
      _phone.clear();
      _message.clear();
      _customAmount.clear();
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  Widget _sectionTitle(String text, {double fontSize = 20}) {
    return Text(text,
        style: _labelStyle(fontSize: fontSize, fontWeight: FontWeight.w800));
  }

  TextStyle _labelStyle({
    double? fontSize,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
  }) {
    if (_isLanding) {
      return LandingCommon.bodyStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      );
    }
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
        );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    if (_isLanding) {
      return TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: keyboardType == const TextInputType.numberWithOptions(decimal: true)
            ? (_) => _onCustomAmountInput()
            : null,
        style: LandingCommon.bodyStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
          filled: true,
          fillColor: LandingCommon.bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _primary, width: 2),
          ),
        ),
      );
    }
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildNextButton({VoidCallback? onPressed}) {
    return ElevatedButton(
      onPressed: onPressed ?? () => setState(() => _step++),
      style: ElevatedButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text('Continue'),
    );
  }

  Widget _buildBackButton() {
    return OutlinedButton(
      onPressed: _step > 0 ? () => setState(() => _step--) : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text('Back'),
    );
  }
}
