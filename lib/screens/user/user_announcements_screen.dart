import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/announcement.dart';
import '../../services/announcements_repository.dart';
import '../../widgets/safe_image.dart';

final _userAnnouncementsProvider = StreamProvider<List<Announcement>>((ref) {
  return AnnouncementsRepository().watchPublicActive();
});

class UserAnnouncementsScreen extends ConsumerWidget {
  const UserAnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final announcementsAsync = ref.watch(_userAnnouncementsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Announcements',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Latest updates and notices from the parish.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
          announcementsAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, st) => SliverFillRemaining(
              child: Center(
                child: Text('Could not load announcements: $e'),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.campaign_outlined,
                          size: 64,
                          color: colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No announcements at this time.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                );
              }

              final sorted = List<Announcement>.from(items)
                ..sort((a, b) {
                  if (a.pinned && !b.pinned) return -1;
                  if (!a.pinned && b.pinned) return 1;
                  return b.eventDateTime.compareTo(a.eventDateTime);
                });

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return _AnnouncementCard(
                        announcement: sorted[index],
                        onTap: () => _showDetail(context, sorted[index]),
                      );
                    },
                    childCount: sorted.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, Announcement a) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AnnouncementDetailSheet(announcement: a),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// List card
// ─────────────────────────────────────────────────────────────────────────────

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.onTap,
  });

  final Announcement announcement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final a = announcement;
    final dateStr =
        DateFormat('MMM d, yyyy  h:mm a').format(a.eventDateTime);

    final isMarriage = a.announcementType == 'marriage';
    final hasMarriagePhotos =
        isMarriage && (a.imageUrl != null || a.imageUrl2 != null);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 14),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasMarriagePhotos)
                  _MarriagePhotoBanner(
                    imageUrl1: a.imageUrl,
                    imageUrl2: a.imageUrl2,
                    person1Name: a.person1Name,
                    person2Name: a.person2Name,
                    fullWidth: true,
                  )
                else if (a.imageUrl != null)
                  SafeImage(
                    imageUrl: a.imageUrl!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),

                Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type badge + pin
                  Row(
                    children: [
                      _TypeBadge(type: a.announcementType),
                      if (a.pinned) ...[
                        const SizedBox(width: 8),
                        _badge(
                          context,
                          Icons.push_pin,
                          'Pinned',
                          colorScheme.primary,
                        ),
                      ],
                      const Spacer(),
                      Icon(
                        Icons.chevron_right,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Text(
                    a.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),

                  // Description — show up to 3 lines
                  Text(
                    a.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),

                  // Date & location row
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 14, color: colorScheme.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          dateStr,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  if (a.location.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 14, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            a.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (isMarriage &&
                      !hasMarriagePhotos &&
                      (a.person1Name != null || a.person2Name != null)) ...[
                    const SizedBox(height: 8),
                    _MarriageCoupleLine(
                      person1: a.person1Name,
                      person2: a.person2Name,
                    ),
                  ],

                  // "Tap to read more" hint
                  const SizedBox(height: 6),
                  Text(
                    'Tap to read more',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                  ),
                ],
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full detail bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AnnouncementDetailSheet extends StatelessWidget {
  const _AnnouncementDetailSheet({required this.announcement});

  final Announcement announcement;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final a = announcement;
    final dateStr =
        DateFormat('EEEE, MMMM d, yyyy  •  h:mm a').format(a.eventDateTime);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.97,
      expand: false,
      builder: (_, controller) {
        return Column(
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),

            // Scrollable content
            Expanded(
              child: ListView(
                controller: controller,
                padding: EdgeInsets.zero,
                children: [
                  // ── Hero image(s) ───────────────────────────────────
                  if (a.announcementType == 'marriage' &&
                      (a.imageUrl != null || a.imageUrl2 != null)) ...[
                    _MarriagePhotoBanner(
                      imageUrl1: a.imageUrl,
                      imageUrl2: a.imageUrl2,
                      person1Name: a.person1Name,
                      person2Name: a.person2Name,
                      fullWidth: true,
                      height: 200,
                    ),
                  ] else if (a.imageUrl != null) ...[
                    SafeImage(
                      imageUrl: a.imageUrl!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ],

                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Type badge + pin
                        Row(
                          children: [
                            _TypeBadge(type: a.announcementType),
                            if (a.pinned) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.push_pin,
                                        size: 12, color: colorScheme.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Pinned',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.primary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Title
                        Text(
                          a.title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),

                        // Marriage couple names
                        if (a.announcementType == 'marriage' &&
                            (a.person1Name != null ||
                                a.person2Name != null)) ...[
                          _InfoRow(
                            icon: Icons.favorite,
                            iconColor: Colors.pinkAccent,
                            text:
                                '${a.person1Name ?? ''} & ${a.person2Name ?? ''}',
                            textStyle: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.pinkAccent,
                                ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Date
                        _InfoRow(
                          icon: Icons.calendar_today_outlined,
                          iconColor: colorScheme.primary,
                          text: dateStr,
                        ),
                        const SizedBox(height: 8),

                        // Location
                        if (a.location.isNotEmpty) ...[
                          _InfoRow(
                            icon: Icons.location_on_outlined,
                            iconColor: colorScheme.secondary,
                            text: a.location,
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Divider
                        Divider(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.5)),
                        const SizedBox(height: 16),

                        // Full description
                        Text(
                          'Details',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          a.description,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(height: 1.6),
                        ),

                        // Second image (non-marriage single image2)
                        if (a.announcementType != 'marriage' &&
                            a.imageUrl2 != null) ...[
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SafeImage(
                              imageUrl: a.imageUrl2!,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],

                        // PDF attachment
                        if (a.attachmentUrl != null) ...[
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: () {
                              // Attachment open handled via URL launcher if needed
                            },
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('View Attachment'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Marriage photo banner — two photos side by side with names
// ─────────────────────────────────────────────────────────────────────────────

class _MarriagePhotoBanner extends StatelessWidget {
  const _MarriagePhotoBanner({
    this.imageUrl1,
    this.imageUrl2,
    this.person1Name,
    this.person2Name,
    this.fullWidth = true,
    this.height = 140,
  });

  final String? imageUrl1;
  final String? imageUrl2;
  final String? person1Name;
  final String? person2Name;
  final bool fullWidth;
  final double height;

  Widget _photoCell(
    BuildContext context, {
    required String? url,
    required String? name,
    required bool isLeft,
  }) {
    final cs = Theme.of(context).colorScheme;

    Widget child;
    if (url != null) {
      child = Stack(
        fit: StackFit.expand,
        children: [
          SafeImage(
            imageUrl: url,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          if (name != null && name.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      child = ColoredBox(
        color: Colors.pink.shade50,
        child: Icon(
          Icons.person_outline_rounded,
          size: 40,
          color: cs.primary.withValues(alpha: 0.4),
        ),
      );
    }

    return Expanded(child: child);
  }

  @override
  Widget build(BuildContext context) {
    final banner = SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Row(
            children: [
              _photoCell(
                context,
                url: imageUrl1,
                name: person1Name,
                isLeft: true,
              ),
              Container(width: 2, color: Colors.white),
              _photoCell(
                context,
                url: imageUrl2,
                name: person2Name,
                isLeft: false,
              ),
            ],
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.pink.shade100, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: Colors.pinkAccent,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );

    if (!fullWidth) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: banner,
        ),
      );
    }
    return banner;
  }
}

class _MarriageCoupleLine extends StatelessWidget {
  const _MarriageCoupleLine({this.person1, this.person2});
  final String? person1;
  final String? person2;

  @override
  Widget build(BuildContext context) {
    final names = [
      if (person1 != null && person1!.trim().isNotEmpty) person1!.trim(),
      if (person2 != null && person2!.trim().isNotEmpty) person2!.trim(),
    ].join(' & ');
    if (names.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        Icon(Icons.favorite_rounded, size: 16, color: Colors.pink.shade300),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            names,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.pinkAccent,
                ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final String type;

  static const _labels = {
    'general': 'General',
    'marriage': 'Marriage',
    'baptism': 'Baptism',
    'confirmation': 'Confirmation',
    'death': 'Death Notice',
  };

  static const _colors = {
    'general': Colors.blueGrey,
    'marriage': Colors.pinkAccent,
    'baptism': Colors.lightBlue,
    'confirmation': Colors.deepPurple,
    'death': Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[type] ?? type;
    final color = _colors[type] ?? Colors.blueGrey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (color as Color).withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.text,
    this.textStyle,
  });

  final IconData icon;
  final Color iconColor;
  final String text;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: textStyle ??
                Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
          ),
        ),
      ],
    );
  }
}
