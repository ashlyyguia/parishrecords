import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_colors.dart';
import '../../widgets/app_card.dart';
import 'landing_kit.dart';

class HomeSection extends StatelessWidget {
  const HomeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final compact = LandingKit.isCompact(context);

    return LandingPage(
      children: [
        LandingHero(
          eyebrow: 'HOLY ROSARY PARISH · OROQUIETA CITY',
          title: 'Welcome to our\nsacred community',
          subtitle:
              'Upcoming liturgies, community gatherings, and important parish '
              'updates — all in one place, for you and your family.',
          actions: [
            LandingButton(
              label: 'View Announcements',
              icon: Icons.campaign_rounded,
              primary: true,
              onDark: true,
              onPressed: () => context.go('/announcements'),
            ),
            LandingButton(
              label: 'Mass Times',
              icon: Icons.schedule_rounded,
              onDark: true,
              onPressed: () => context.go('/mass-time'),
            ),
          ],
        ),
        SizedBox(height: compact ? 28 : 40),

        // Quick links (dashboard-style action cards)
        _QuickLinks(compact: compact),
        SizedBox(height: compact ? 36 : 56),

        // Community strip: photo + copy
        _CommunityStrip(compact: compact),
        SizedBox(height: compact ? 28 : 44),

        // Stats
        const _StatsRow(),
      ],
    );
  }
}

class _QuickLinks extends StatelessWidget {
  const _QuickLinks({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _QuickLinkCard(
        icon: Icons.campaign_rounded,
        title: 'Announcements',
        description: 'News, schedules, and parish notices.',
        onTap: () => context.go('/announcements'),
      ),
      _QuickLinkCard(
        icon: Icons.schedule_rounded,
        title: 'Mass Schedule',
        description: 'Weekday, Saturday and Sunday liturgies.',
        onTap: () => context.go('/mass-time'),
      ),
      _QuickLinkCard(
        icon: Icons.volunteer_activism_rounded,
        title: 'Give a Donation',
        description: 'Support the parish securely via GCash.',
        onTap: () => context.go('/donations'),
      ),
    ];

    if (compact) {
      return Column(
        children: [
          for (final c in cards) ...[c, const SizedBox(height: 14)],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            Expanded(child: cards[i]),
            if (i != cards.length - 1) const SizedBox(width: 18),
          ],
        ],
      ),
    );
  }
}

class _QuickLinkCard extends StatelessWidget {
  const _QuickLinkCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: AppColors.brandGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 16),
          Text(title, style: LandingKit.heading(19)),
          const SizedBox(height: 6),
          Text(description, style: LandingKit.body(13.5, height: 1.5)),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Open',
                style: LandingKit.body(
                  13,
                  color: AppColors.primary,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommunityStrip extends StatelessWidget {
  const _CommunityStrip({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const LandingPill(icon: Icons.church_rounded, label: 'Est. 1952'),
        const SizedBox(height: 18),
        Text(
          'A vibrant community of\nfaith in Oroquieta City',
          style: LandingKit.display(compact ? 26 : 34),
        ),
        const SizedBox(height: 16),
        Text(
          'We welcome all who seek spiritual growth, sacramental grace, and '
          'meaningful fellowship. Join us for Mass, take part in our ministries, '
          'and become part of our growing parish family.',
          style: LandingKit.body(compact ? 14.5 : 15.5),
        ),
        const SizedBox(height: 24),
        LandingButton(
          label: 'Learn about the parish',
          icon: Icons.arrow_forward_rounded,
          primary: true,
          onPressed: () => context.go('/about'),
        ),
      ],
    );

    if (compact) {
      return Column(
        children: [
          const LandingImageFrame(aspectRatio: 16 / 10),
          const SizedBox(height: 28),
          copy,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(flex: 6, child: LandingImageFrame(aspectRatio: 16 / 11)),
        const SizedBox(width: 56),
        Expanded(flex: 5, child: copy),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    const stats = [
      ('70+', 'Years of service'),
      ('9', 'Masses each week'),
      ('5', 'Sunday liturgies'),
      ('1', 'Parish family'),
    ];
    final compact = LandingKit.isMobile(context);

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final s in stats)
          SizedBox(
            width: compact
                ? (MediaQuery.sizeOf(context).width - 40 - 16) / 2
                : (LandingKit.maxContentWidth - 3 * 16) / 4,
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.$1, style: LandingKit.display(30, color: AppColors.primary)),
                  const SizedBox(height: 6),
                  Text(
                    s.$2,
                    style: LandingKit.body(13, weight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
