import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/announcement.dart';
import '../../services/announcements_repository.dart';
import 'landing_common.dart';

final _publicAnnouncementsProvider = StreamProvider<List<Announcement>>((ref) {
  return AnnouncementsRepository().watchPublicActive();
});

class AnnouncementsSection extends ConsumerWidget {
  const AnnouncementsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcementsAsync = ref.watch(_publicAnnouncementsProvider);

    return LandingCommon.sectionShell(
      title: 'Parish Announcements',
      subtitle: 'Stay updated with the latest news, schedules, and important notices from our parish community.',
      left: LandingCommon.churchImageCard(),
      right: announcementsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => const Center(child: Text('Could not load announcements.')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.campaign_outlined, size: 56,
                      color: LandingCommon.primary.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text(
                    'No announcements at this time.',
                    style: LandingCommon.bodyStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < items.take(4).length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                _AnnouncementCard(
                  announcement: items[i],
                  isHighlighted: items[i].pinned || i == 0,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.announcement,
    this.isHighlighted = false,
  });

  final Announcement announcement;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final dateStr = _formatDate(announcement.eventDateTime);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isHighlighted
            ? LandingCommon.primary.withValues(alpha: 0.03)
            : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlighted
              ? LandingCommon.primary.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? LandingCommon.primary.withValues(alpha: 0.1)
                  : LandingCommon.bg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              announcement.pinned ? Icons.push_pin_outlined : Icons.campaign_outlined,
              color: isHighlighted ? LandingCommon.primary : Colors.grey.shade700,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        announcement.title,
                        style: LandingCommon.bodyStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: LandingCommon.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        dateStr,
                        style: LandingCommon.bodyStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: LandingCommon.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  announcement.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: LandingCommon.bodyStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (announcement.location.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        announcement.location,
                        style: LandingCommon.bodyStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}



