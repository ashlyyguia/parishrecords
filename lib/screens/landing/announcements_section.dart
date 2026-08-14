import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_colors.dart';
import '../../models/announcement.dart';
import '../../services/announcements_repository.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/safe_image.dart';
import 'landing_kit.dart';

final _publicAnnouncementsProvider = StreamProvider<List<Announcement>>((ref) {
  return AnnouncementsRepository().watchPublicActive();
});

class AnnouncementsSection extends ConsumerWidget {
  const AnnouncementsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_publicAnnouncementsProvider);
    final compact = LandingKit.isCompact(context);

    return LandingPage(
      children: [
        const LandingHero(
          eyebrow: 'PARISH ANNOUNCEMENTS',
          title: 'News & notices',
          subtitle:
              'Stay updated with the latest news, schedules, and important '
              'notices from our parish community.',
          glyph: Icons.campaign_rounded,
        ),
        SizedBox(height: compact ? 28 : 44),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
          error: (_, _) => const AppEmptyState(
            icon: Icons.wifi_off_rounded,
            title: 'Could not load announcements',
            message: 'Please check your connection and try again.',
          ),
          data: (items) {
            if (items.isEmpty) {
              return const AppEmptyState(
                icon: Icons.campaign_outlined,
                title: 'No announcements yet',
                message: 'Check back soon for parish news and updates.',
              );
            }
            final sorted = List<Announcement>.from(items)
              ..sort((a, b) {
                if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
                return a.eventDateTime.compareTo(b.eventDateTime);
              });
            return Column(
              children: [
                for (final a in sorted) ...[
                  _AnnouncementCard(announcement: a),
                  const SizedBox(height: 16),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement});
  final Announcement announcement;

  bool get _isMarriage => announcement.announcementType == 'marriage';
  bool get _pinned => announcement.pinned;

  @override
  Widget build(BuildContext context) {
    final compact = LandingKit.isMobile(context);

    return AppCard(
      padding: EdgeInsets.zero,
      borderColor: _pinned ? AppColors.tintStrong : null,
      color: _pinned ? AppColors.tint : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isMarriage &&
              (announcement.imageUrl != null ||
                  announcement.imageUrl2 != null))
            _MarriageImages(announcement: announcement, compact: compact),
          Padding(
            padding: EdgeInsets.all(compact ? 18 : 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _pinned ? Colors.white : AppColors.tint,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.tintStrong),
                  ),
                  child: Icon(_icon(), color: _color(), size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (_pinned) ...[
                            const _Badge(label: 'PINNED', color: AppColors.primary),
                            const SizedBox(width: 8),
                          ],
                          if (announcement.announcementType != 'general')
                            _Badge(
                              label: announcement.announcementType.toUpperCase(),
                              color: _color(),
                            ),
                        ],
                      ),
                      if (_pinned || announcement.announcementType != 'general')
                        const SizedBox(height: 10),
                      Text(
                        announcement.title,
                        style: LandingKit.heading(compact ? 17 : 20),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        announcement.description,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: LandingKit.body(compact ? 13.5 : 14.5, height: 1.55),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _MetaChip(
                            icon: Icons.calendar_today_rounded,
                            label: _formatDate(announcement.eventDateTime),
                          ),
                          if (announcement.location.isNotEmpty)
                            _MetaChip(
                              icon: Icons.location_on_rounded,
                              label: announcement.location,
                              muted: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _icon() {
    if (_pinned) return Icons.push_pin_rounded;
    switch (announcement.announcementType) {
      case 'marriage':
        return Icons.favorite_rounded;
      case 'baptism':
        return Icons.water_drop_rounded;
      case 'confirmation':
        return Icons.handshake_rounded;
      case 'death':
        return Icons.church_rounded;
      default:
        return Icons.campaign_rounded;
    }
  }

  Color _color() {
    switch (announcement.announcementType) {
      case 'marriage':
        return const Color(0xFFEC4899);
      case 'baptism':
        return AppColors.primary;
      case 'confirmation':
        return AppColors.primaryDark;
      case 'death':
        return AppColors.slate500;
      default:
        return AppColors.primary;
    }
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: LandingKit.body(10, color: color, weight: FontWeight.w700)
            .copyWith(letterSpacing: 0.6),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.muted = false,
  });
  final IconData icon;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? AppColors.slate500 : AppColors.primaryDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: muted ? AppColors.field : AppColors.tint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: muted ? AppColors.border : AppColors.tintStrong,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(label, style: LandingKit.body(12, color: color, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _MarriageImages extends StatelessWidget {
  const _MarriageImages({required this.announcement, required this.compact});
  final Announcement announcement;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 170.0 : 220.0;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            if (announcement.imageUrl != null)
              Expanded(
                child: _Photo(
                  url: announcement.imageUrl!,
                  name: announcement.person1Name ?? 'Groom',
                ),
              ),
            if (announcement.imageUrl != null &&
                announcement.imageUrl2 != null)
              const SizedBox(width: 10),
            if (announcement.imageUrl2 != null)
              Expanded(
                child: _Photo(
                  url: announcement.imageUrl2!,
                  name: announcement.person2Name ?? 'Bride',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.url, required this.name});
  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          SafeImage(
            imageUrl: url,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) => Container(
              color: AppColors.field,
              child: const Icon(Icons.person, color: AppColors.slate400),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xCC0F172A), Colors.transparent],
                ),
              ),
              child: Text(
                name,
                style: LandingKit.body(13, color: Colors.white, weight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
