import 'package:flutter/material.dart';
import 'landing_common.dart';
import '../../widgets/parish_mass_schedule.dart';

class MassTimeSection extends StatelessWidget {
  const MassTimeSection({super.key});

  @override
  Widget build(BuildContext context) {
    return LandingCommon.sectionShell(
      title: 'Schedule of Mass',
      subtitle: 'Holy Rosary Parish — weekly liturgy schedule.',
      left: LandingCommon.churchImageCard(),
      right: ParishMassSchedule(accentColor: LandingCommon.primary),
    );
  }
}
