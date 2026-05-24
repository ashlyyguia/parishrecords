import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/announcement.dart';
import '../../services/announcements_repository.dart';
import '../../widgets/safe_image.dart';
import 'landing_common.dart';

final _publicAnnouncementsProvider = StreamProvider<List<Announcement>>((ref) {
  return AnnouncementsRepository().watchPublicActive();
});

class AnnouncementsSection extends ConsumerWidget {
  const AnnouncementsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcementsAsync = ref.watch(_publicAnnouncementsProvider);

    return Builder(
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final isMobile = size.width < 600;
        final horizontalPadding = isMobile ? 24.0 : 48.0;
        final topPadding = isMobile ? 100.0 : 120.0;
        final titleSize = isMobile ? 32.0 : 42.0;
        final subtitleSize = isMobile ? 14.0 : 16.0;

        return LandingCommon.diagonalBackground(
          child: Container(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              topPadding,
              horizontalPadding,
              48,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Parish Announcements',
                      style: LandingCommon.titleStyle(fontSize: titleSize),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Stay updated with the latest news, schedules, and important notices from our parish community.',
                      style: LandingCommon.bodyStyle(fontSize: subtitleSize),
                    ),
                    const SizedBox(height: 32),
                    Expanded(
                      child: announcementsAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, st) => const Center(
                          child: Text('Could not load announcements.'),
                        ),
                        data: (items) {
                          if (items.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.campaign_outlined,
                                    size: 56,
                                    color: LandingCommon.primary.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
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

                          final sortedItems = List<Announcement>.from(items)
                            ..sort((a, b) {
                              if (a.pinned && !b.pinned) return -1;
                              if (!a.pinned && b.pinned) return 1;
                              return a.eventDateTime.compareTo(b.eventDateTime);
                            });

                          return ListView.separated(
                            itemCount: sortedItems.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 16),
                            itemBuilder: (context, i) => _AnnouncementCard(
                              announcement: sortedItems[i],
                              isHighlighted: sortedItems[i].pinned,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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

  bool get _isMarriage => announcement.announcementType == 'marriage';

  @override
  Widget build(BuildContext context) {
    final dateStr = _formatDate(announcement.eventDateTime);
    final isCompact = MediaQuery.of(context).size.width < 600;

    return Container(
      decoration: BoxDecoration(
        color: isHighlighted
            ? LandingCommon.primary.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isHighlighted
              ? LandingCommon.primary.withValues(alpha: 0.25)
              : Colors.grey.withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Marriage Images ────────────────────────────────────────
          if (_isMarriage &&
              (announcement.imageUrl != null || announcement.imageUrl2 != null))
            _buildMarriageImages(isCompact),
          // ── Body ─────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.all(isCompact ? 20 : 28),
            child: isCompact
                ? _buildCompactLayout(dateStr)
                : _buildWideLayout(dateStr),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout(String dateStr) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isHighlighted
                ? LandingCommon.primary.withValues(alpha: 0.1)
                : LandingCommon.bg,
            shape: BoxShape.circle,
          ),
          child: Icon(
            _getIconForType(),
            color: isHighlighted ? LandingCommon.primary : _getColorForType(),
            size: 28,
          ),
        ),
        const SizedBox(width: 20),
        // Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type badge
                  if (announcement.announcementType != 'general') ...[
                    _buildTypeBadge(),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      announcement.title,
                      style: LandingCommon.bodyStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                announcement.description,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: LandingCommon.bodyStyle(
                  fontSize: 16,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  // Date chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: LandingCommon.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: LandingCommon.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          dateStr,
                          style: LandingCommon.bodyStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: LandingCommon.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Location (if available)
                  if (announcement.location.isNotEmpty)
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              announcement.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LandingCommon.bodyStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout(String dateStr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isHighlighted
                    ? LandingCommon.primary.withValues(alpha: 0.1)
                    : LandingCommon.bg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getIconForType(),
                color: isHighlighted
                    ? LandingCommon.primary
                    : _getColorForType(),
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type badge
                  if (!_isMarriage &&
                      announcement.announcementType != 'general')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _buildTypeBadge(),
                    ),
                  Text(
                    announcement.title,
                    style: LandingCommon.bodyStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 52),
          child: Text(
            announcement.description,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: LandingCommon.bodyStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 52),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 12,
                color: LandingCommon.primary,
              ),
              const SizedBox(width: 6),
              Text(
                dateStr,
                style: LandingCommon.bodyStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: LandingCommon.primary,
                ),
              ),
              if (announcement.location.isNotEmpty) ...[
                const SizedBox(width: 12),
                Icon(
                  Icons.location_on_outlined,
                  size: 12,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    announcement.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LandingCommon.bodyStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeBadge() {
    final color = _getColorForType();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        announcement.announcementType.toUpperCase(),
        style: LandingCommon.bodyStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  IconData _getIconForType() {
    if (announcement.pinned) return Icons.push_pin_outlined;
    switch (announcement.announcementType) {
      case 'marriage':
        return Icons.favorite;
      case 'baptism':
        return Icons.water_drop_outlined;
      case 'confirmation':
        return Icons.handshake_outlined;
      case 'death':
        return Icons.church_outlined;
      default:
        return Icons.campaign_outlined;
    }
  }

  Color _getColorForType() {
    switch (announcement.announcementType) {
      case 'marriage':
        return Colors.pink.shade400;
      case 'baptism':
        return Colors.blue.shade400;
      case 'confirmation':
        return Colors.purple.shade400;
      case 'death':
        return Colors.grey.shade600;
      default:
        return LandingCommon.primary;
    }
  }

  Widget _buildMarriageImages(bool isCompact) {
    final height = isCompact ? 160.0 : 200.0;

    return Container(
      height: height,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Groom photo
          if (announcement.imageUrl != null)
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SafeImage(
                      imageUrl: announcement.imageUrl!,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade200,
                        child: Icon(Icons.person, color: Colors.grey.shade400),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.6),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Text(
                          announcement.person1Name ?? 'Groom',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (announcement.imageUrl != null && announcement.imageUrl2 != null)
            const SizedBox(width: 8),
          // Bride photo
          if (announcement.imageUrl2 != null)
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SafeImage(
                      imageUrl: announcement.imageUrl2!,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade200,
                        child: Icon(Icons.person, color: Colors.grey.shade400),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.6),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Text(
                          announcement.person2Name ?? 'Bride',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
