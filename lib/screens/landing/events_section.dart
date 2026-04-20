import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/parish_event.dart';
import '../../services/events_repository.dart';
import 'landing_common.dart';

final _publicEventsProvider = StreamProvider<List<ParishEvent>>((ref) {
  return EventsRepository().watchPublicActive();
});

class EventsSection extends ConsumerWidget {
  const EventsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(_publicEventsProvider);

    return LandingCommon.sectionShell(
      title: 'Upcoming Events',
      subtitle: 'Stay connected with parish activities, celebrations, and community gatherings.',
      left: LandingCommon.churchImageCard(),
      right: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => _StaticEvents(onNavigate: () => context.go('/announcements')),
        data: (items) {
          if (items.isEmpty) {
            return _StaticEvents(onNavigate: () => context.go('/announcements'));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < items.take(4).length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                _EventCard(event: items[i], index: i),
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => context.go('/announcements'),
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('See All Events'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: LandingCommon.primary,
                  side: BorderSide(color: LandingCommon.primary.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Fallback static events when no live data
class _StaticEvents extends StatelessWidget {
  const _StaticEvents({required this.onNavigate});
  final VoidCallback onNavigate;

  static const _events = [
    {'title': 'Parish Fiesta Celebration', 'subtitle': 'Annual community fiesta with procession and Mass.', 'date': 'May 3'},
    {'title': 'Youth Ministry Gathering', 'subtitle': 'Weekly meetings and faith formation for youth.', 'date': 'Every Wed'},
    {'title': 'Community Feeding Program', 'subtitle': 'Serve and support our outreach mission.', 'date': 'May 10'},
    {'title': 'Couples for Christ', 'subtitle': 'Marriage enrichment and family ministry sessions.', 'date': 'May 17'},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < _events.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _StaticEventCard(event: _events[i], index: i),
        ],
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: onNavigate,
          icon: const Icon(Icons.arrow_forward, size: 16),
          label: const Text('See All Events'),
          style: OutlinedButton.styleFrom(
            foregroundColor: LandingCommon.primary,
            side: BorderSide(color: LandingCommon.primary.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.index});
  final ParishEvent event;
  final int index;

  static const _colors = [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFF0891B2), Color(0xFF059669)];

  @override
  Widget build(BuildContext context) {
    final color = _colors[index % _colors.length];
    final title = event.title;
    final location = event.location;
    final dateRaw = event.eventDateTime;
    String dateStr = '';
    if (dateRaw != null) {
      dateStr = '${dateRaw.month.toString().padLeft(2, '0')}-${dateRaw.day.toString().padLeft(2, '0')}';
    } else {
      dateStr = 'TBD';
    }

    return _EventCardLayout(color: color, title: title, subtitle: location, date: dateStr);
  }
}

class _StaticEventCard extends StatelessWidget {
  const _StaticEventCard({required this.event, required this.index});
  final Map<String, String> event;
  final int index;

  static const _colors = [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFF0891B2), Color(0xFF059669)];

  @override
  Widget build(BuildContext context) {
    final color = _colors[index % _colors.length];
    return _EventCardLayout(
      color: color,
      title: event['title']!,
      subtitle: event['subtitle']!,
      date: event['date']!,
    );
  }
}

class _EventCardLayout extends StatelessWidget {
  const _EventCardLayout({
    required this.color,
    required this.title,
    required this.subtitle,
    required this.date,
  });
  final Color color;
  final String title;
  final String subtitle;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              date,
              style: LandingCommon.bodyStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: LandingCommon.bodyStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LandingCommon.bodyStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
