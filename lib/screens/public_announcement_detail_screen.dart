import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/announcement.dart';
import '../services/announcements_repository.dart';

class PublicAnnouncementDetailScreen extends StatefulWidget {
  final String announcementId;

  const PublicAnnouncementDetailScreen({
    super.key,
    required this.announcementId,
  });

  @override
  State<PublicAnnouncementDetailScreen> createState() =>
      _PublicAnnouncementDetailScreenState();
}

class _PublicAnnouncementDetailScreenState
    extends State<PublicAnnouncementDetailScreen> {
  final _repo = AnnouncementsRepository();
  Announcement? _announcement;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = await _repo.loadById(widget.announcementId);
    if (a != null) {
      await _repo.incrementViews(a.id);
    }
    if (!mounted) return;
    setState(() {
      _announcement = a;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : _announcement == null
        ? const Center(child: Text('Announcement not found'))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_announcement!.imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _announcement!.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const ColoredBox(color: Colors.grey),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      _announcement!.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.event, size: 18),
                        const SizedBox(width: 4),
                        Text(_announcement!.eventDateTime.toString()),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.place, size: 18),
                        const SizedBox(width: 4),
                        Text(_announcement!.location),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _announcement!.description,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    if (_announcement!.attachmentUrl != null)
                      ElevatedButton.icon(
                        onPressed: () {
                          final url = _announcement!.attachmentUrl!;
                          launchUrl(Uri.parse(url));
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Download attachment'),
                      ),
                  ],
                ),
              ),
            ),
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Announcement')),
      body: body,
    );
  }
}
