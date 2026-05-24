import 'package:flutter/material.dart';

import '../../widgets/online_donation_flow.dart';
import 'landing_common.dart';

class DonationsSection extends StatelessWidget {
  const DonationsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return LandingCommon.sectionShell(
      title: 'Support Our Parish',
      subtitle:
          'Online giving via GCash. Select a type, enter your name, scan the QR, and pay in the GCash app.',
      left: LandingCommon.churchImageCard(),
      right: LandingCommon.contentCard(
        child: const OnlineDonationFlow(
          visualStyle: OnlineDonationVisualStyle.landing,
        ),
      ),
    );
  }
}
