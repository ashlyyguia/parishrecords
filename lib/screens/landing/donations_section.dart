import 'package:flutter/material.dart';
import 'landing_common.dart';

class DonationsSection extends StatefulWidget {
  const DonationsSection({super.key});

  @override
  State<DonationsSection> createState() => _DonationsSectionState();
}

class _DonationsSectionState extends State<DonationsSection> {
  int step = 0;
  String donationType = 'Tithes / General Fund';
  int amount = 100;

  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget rightContent;
    if (step == 0) {
      rightContent = _buildTypeSelection();
    } else if (step == 1) {
      rightContent = _buildAmountSelection();
    } else if (step == 2) {
      rightContent = _buildInfoForm();
    } else {
      rightContent = _buildSummary();
    }

    return LandingCommon.sectionShell(
      title: 'Support Our Parish',
      subtitle: 'Your generosity helps sustain our ministries, maintain our beautiful church, and expand our community outreach.',
      left: LandingCommon.churchImageCard(),
      right: LandingCommon.contentCard(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStepper(),
            const SizedBox(height: 32),
            rightContent,
          ],
        ),
      ),
    );
  }

  Widget _buildStepper() {
    return Row(
      children: List.generate(4, (index) {
        final isActive = step >= index;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isActive ? LandingCommon.primary : LandingCommon.bg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isActive ? LandingCommon.primary : Colors.grey.shade300,
                  ),
                ),
                alignment: Alignment.center,
                child: step > index
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text(
                        '${index + 1}',
                        style: LandingCommon.bodyStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isActive ? Colors.white : Colors.grey.shade600,
                        ),
                      ),
              ),
              if (index < 3)
                Expanded(
                  child: Container(
                    height: 2,
                    color: isActive ? LandingCommon.primary : Colors.grey.shade200,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildTypeSelection() {
    final types = [
      'Tithes / General Fund',
      'Church Maintenance',
      'Parish Relief Fund',
      'Youth Ministry',
      'Community Outreach',
      'Scholarship Program',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Donation Type', style: LandingCommon.titleStyle(fontSize: 20)),
        const SizedBox(height: 16),
        ...types.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => donationType = t),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: donationType == t ? LandingCommon.primary.withValues(alpha: 0.05) : LandingCommon.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: donationType == t ? LandingCommon.primary : Colors.grey.shade200,
                      width: donationType == t ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        donationType == t ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: donationType == t ? LandingCommon.primary : Colors.grey.shade400,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(t, style: LandingCommon.bodyStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            )),
        const SizedBox(height: 24),
        _buildNextButton(),
      ],
    );
  }

  Widget _buildAmountSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Amount', style: LandingCommon.titleStyle(fontSize: 20)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [100, 500, 1000, 1500, 2000, 5000].map((a) {
            final isActive = amount == a;
            return InkWell(
              onTap: () => setState(() => amount = a),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 100,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: isActive ? LandingCommon.primary : LandingCommon.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive ? LandingCommon.primary : Colors.grey.shade200,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '₱$a',
                  style: LandingCommon.bodyStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            _buildBackButton(),
            const SizedBox(width: 16),
            Expanded(child: _buildNextButton()),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your Information', style: LandingCommon.titleStyle(fontSize: 20)),
        const SizedBox(height: 16),
        _buildTextField(name, 'Full Name', Icons.person_outline),
        const SizedBox(height: 12),
        _buildTextField(email, 'Email Address', Icons.email_outlined),
        const SizedBox(height: 12),
        _buildTextField(phone, 'Contact Number', Icons.phone_outlined),
        const SizedBox(height: 24),
        Row(
          children: [
            _buildBackButton(),
            const SizedBox(width: 16),
            Expanded(child: _buildNextButton()),
          ],
        ),
      ],
    );
  }

  Widget _buildSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Donation Summary', style: LandingCommon.titleStyle(fontSize: 20)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: LandingCommon.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              _buildSummaryRow('Type', donationType),
              const Divider(height: 24),
              _buildSummaryRow('Amount', '₱$amount'),
              const Divider(height: 24),
              _buildSummaryRow('Processing Fee', '₱0.00'),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: LandingCommon.bodyStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    '₱$amount',
                    style: LandingCommon.titleStyle(fontSize: 24, color: LandingCommon.primary),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            _buildBackButton(),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text('Proceed to Payment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: LandingCommon.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: LandingCommon.bodyStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: LandingCommon.bodyStyle(fontSize: 14, color: Colors.grey.shade600)),
        Text(value, style: LandingCommon.bodyStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon) {
    return TextFormField(
      controller: ctrl,
      style: LandingCommon.bodyStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: LandingCommon.bodyStyle(fontSize: 14, color: Colors.grey.shade500),
        prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
        filled: true,
        fillColor: LandingCommon.bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: LandingCommon.primary, width: 2),
        ),
      ),
    );
  }

  Widget _buildNextButton() {
    return ElevatedButton(
      onPressed: () => setState(() => step++),
      style: ElevatedButton.styleFrom(
        backgroundColor: LandingCommon.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: LandingCommon.bodyStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      child: const Text('Continue'),
    );
  }

  Widget _buildBackButton() {
    return OutlinedButton(
      onPressed: () => setState(() => step--),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.grey.shade700,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        side: BorderSide(color: Colors.grey.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: LandingCommon.bodyStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      child: const Text('Back'),
    );
  }
}
