import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/online_donation_flow.dart';
import 'landing_kit.dart';

class DonationsSection extends StatelessWidget {
  const DonationsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final compact = LandingKit.isCompact(context);

    final flowCard = AppCard(
      padding: EdgeInsets.all(compact ? 18 : 24),
      child: const OnlineDonationFlow(
        visualStyle: OnlineDonationVisualStyle.landing,
      ),
    );

    final aside = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        LandingImageFrame(aspectRatio: 4 / 3),
        SizedBox(height: 18),
        _GiveInfo(
          icon: Icons.qr_code_2_rounded,
          title: 'Fast & secure via GCash',
          text: 'Choose a type, enter your name, scan the QR, and pay right in '
              'the GCash app.',
        ),
        SizedBox(height: 12),
        _GiveInfo(
          icon: Icons.volunteer_activism_rounded,
          title: 'Every gift matters',
          text: 'Your generosity sustains the liturgy, ministries, and outreach '
              'of Holy Rosary Parish.',
        ),
        SizedBox(height: 12),
        _GiveInfo(
          icon: Icons.receipt_long_rounded,
          title: 'Tithes & certificate fees',
          text: 'Give a free-will offering or settle sacramental document fees '
              'in one place.',
        ),
      ],
    );

    return LandingPage(
      children: [
        const LandingHero(
          eyebrow: 'SUPPORT OUR PARISH',
          title: 'Give a\ndonation',
          subtitle:
              'Online giving via GCash — simple, secure, and a real help to our '
              'parish community.',
          glyph: Icons.volunteer_activism_rounded,
        ),
        SizedBox(height: compact ? 28 : 44),
        if (compact) ...[
          aside,
          const SizedBox(height: 20),
          flowCard,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: aside),
              const SizedBox(width: 40),
              Expanded(flex: 6, child: flowCard),
            ],
          ),
      ],
    );
  }
}

class _GiveInfo extends StatelessWidget {
  const _GiveInfo({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.tint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.tintStrong),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: LandingKit.heading(15)),
                const SizedBox(height: 4),
                Text(text, style: LandingKit.body(13, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
