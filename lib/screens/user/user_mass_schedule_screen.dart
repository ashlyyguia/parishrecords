import 'package:flutter/material.dart';

import '../../widgets/page_header.dart';
import '../../widgets/parish_mass_schedule.dart';

class UserMassScheduleScreen extends StatelessWidget {
  const UserMassScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            sliver: const SliverToBoxAdapter(
              child: PageHeader(
                icon: Icons.schedule_rounded,
                title: 'Mass Schedule',
                subtitle: 'Holy Rosary Parish · weekly liturgy schedule',
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            sliver: const SliverToBoxAdapter(
              child: ParishMassSchedule(),
            ),
          ),
        ],
      ),
    );
  }
}
