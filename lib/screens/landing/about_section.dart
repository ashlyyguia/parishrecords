import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../widgets/app_card.dart';
import 'landing_kit.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final compact = LandingKit.isCompact(context);

    return LandingPage(
      children: [
        const LandingHero(
          eyebrow: 'ABOUT THE PARISH',
          title: 'Holy Rosary Parish',
          subtitle:
              'Serving Oroquieta City with faith, service, and community since 1952.',
          glyph: Icons.auto_stories_rounded,
        ),
        SizedBox(height: compact ? 32 : 52),

        // Welcome
        const LandingSectionHeader(
          icon: Icons.church_rounded,
          title: 'Welcome',
          subtitle: 'A community of faith in the heart of the city',
        ),
        SizedBox(height: compact ? 18 : 26),
        _WelcomeBlock(compact: compact),
        SizedBox(height: compact ? 40 : 64),

        // History + milestones
        const LandingSectionHeader(
          icon: Icons.history_edu_rounded,
          title: 'Our History',
          subtitle: 'Seven decades of service and growth',
        ),
        SizedBox(height: compact ? 18 : 26),
        _HistoryBlock(compact: compact),
        SizedBox(height: compact ? 40 : 64),

        // Clergy & staff
        const LandingSectionHeader(
          icon: Icons.groups_rounded,
          title: 'Clergy & Staff',
          subtitle: 'The people who serve our parish',
        ),
        SizedBox(height: compact ? 18 : 26),
        const _StaffGrid(),
      ],
    );
  }
}

class _WelcomeBlock extends StatelessWidget {
  const _WelcomeBlock({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Welcome to Holy Rosary Parish',
          style: LandingKit.heading(compact ? 22 : 26),
        ),
        const SizedBox(height: 14),
        Text(
          'Our parish is a vibrant community of faith located in the heart of '
          'Oroquieta City. We welcome all who seek spiritual growth, sacramental '
          'grace, and meaningful fellowship.',
          style: LandingKit.body(compact ? 14.5 : 15.5),
        ),
        const SizedBox(height: 12),
        Text(
          'Join us for Mass, participate in our ministries, and become part of '
          'our growing parish family.',
          style: LandingKit.body(compact ? 14.5 : 15.5),
        ),
      ],
    );

    if (compact) {
      return Column(
        children: [
          const LandingImageFrame(aspectRatio: 16 / 10),
          const SizedBox(height: 24),
          copy,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(flex: 6, child: LandingImageFrame(aspectRatio: 16 / 10)),
        const SizedBox(width: 48),
        Expanded(flex: 5, child: copy),
      ],
    );
  }
}

class _HistoryBlock extends StatelessWidget {
  const _HistoryBlock({required this.compact});
  final bool compact;

  static const _milestones = [
    ('1952', 'Parish officially founded.'),
    ('1988', 'Major church renovation completed.'),
    ('2005', 'Parish community hall inaugurated.'),
    ('2026', 'Launch of the Parish Operational Management System.'),
  ];

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Holy Rosary Parish was established in 1952 to serve the growing '
          'Catholic community in Oroquieta City. What began as a small chapel '
          'has grown into a vibrant parish dedicated to spiritual growth, '
          'sacramental service, and community outreach.',
          style: LandingKit.body(compact ? 14 : 15),
        ),
        const SizedBox(height: 20),
        Text('Key Milestones', style: LandingKit.heading(18)),
        const SizedBox(height: 14),
        for (final m in _milestones) _Milestone(year: m.$1, text: m.$2),
      ],
    );

    if (compact) {
      return Column(
        children: [
          const LandingImageFrame(aspectRatio: 16 / 10),
          const SizedBox(height: 24),
          copy,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(flex: 6, child: LandingImageFrame(aspectRatio: 4 / 3)),
        const SizedBox(width: 48),
        Expanded(flex: 5, child: copy),
      ],
    );
  }
}

class _Milestone extends StatelessWidget {
  const _Milestone({required this.year, required this.text});
  final String year;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.tint,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.tintStrong),
            ),
            child: Text(
              year,
              style: LandingKit.body(
                13,
                color: AppColors.primaryDark,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(text, style: LandingKit.body(14.5, height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffMember {
  final String name;
  final String role;
  final String description;
  const _StaffMember(this.name, this.role, this.description);
}

class _StaffGrid extends StatelessWidget {
  const _StaffGrid();

  static const _staff = [
    _StaffMember(
      'Rev. Fr. Juan D. Santos',
      'Parish Priest',
      'Serving Holy Rosary Parish since 2018. He oversees spiritual leadership, '
          'sacramental administration, and parish development programs.',
    ),
    _StaffMember(
      'Rev. Fr. Michael P. Reyes',
      'Assistant Parish Priest',
      'Assists in daily Masses, confession schedules, and youth ministry '
          'programs while supporting parish outreach initiatives.',
    ),
    _StaffMember(
      'Ms. Maria L. Cruz',
      'Parish Secretary',
      'Responsible for record management, certificate processing, and parish '
          'office operations.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final compact = LandingKit.isCompact(context);
    if (compact) {
      return Column(
        children: [
          for (final m in _staff) ...[
            _StaffCard(member: m),
            const SizedBox(height: 16),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _staff.length; i++) ...[
          Expanded(child: _StaffCard(member: _staff[i])),
          if (i != _staff.length - 1) const SizedBox(width: 18),
        ],
      ],
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.member});
  final _StaffMember member;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tinted banner with avatar
          Container(
            height: 84,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.tint, AppColors.tintStrong],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            ),
          ),
          Transform.translate(
            offset: const Offset(20, -32),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: AppColors.brandGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: const Icon(Icons.person_rounded, color: Colors.white, size: 30),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name, style: LandingKit.heading(17)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.tint,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.tintStrong),
                  ),
                  child: Text(
                    member.role,
                    style: LandingKit.body(
                      12,
                      color: AppColors.primaryDark,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(member.description, style: LandingKit.body(13.5, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
