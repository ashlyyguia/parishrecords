import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../models/announcement.dart';
import '../../../services/announcements_repository.dart';

class AdminAnnouncementsPage extends StatefulWidget {
  const AdminAnnouncementsPage({super.key});

  @override
  State<AdminAnnouncementsPage> createState() => _AdminAnnouncementsPageState();
}

class _AdminAnnouncementsPageState extends State<AdminAnnouncementsPage> {
  final _repo = AnnouncementsRepository();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Announcements',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Simple analytics summary
              StreamBuilder<List<Announcement>>(
                stream: _repo.watchAdminList(),
                builder: (context, snapshot) {
                  final items = snapshot.data ?? const <Announcement>[];
                  final active = items
                      .where((a) => a.status == 'active')
                      .length;
                  final upcoming = items
                      .where(
                        (a) =>
                            a.status == 'active' &&
                            a.eventDateTime.isAfter(DateTime.now()),
                      )
                      .length;
                  final views = items.fold<int>(0, (sum, a) => sum + (a.views));
                  return Wrap(
                    spacing: 12,
                    children: [
                      Chip(label: Text('Total: ${items.length}')),
                      Chip(label: Text('Active: $active')),
                      Chip(label: Text('Upcoming: $upcoming')),
                      Chip(label: Text('Views: $views')),
                    ],
                  );
                },
              ),
              FilledButton.icon(
                onPressed: () => _openEditDialog(),
                icon: const Icon(Icons.add),
                label: const Text('New announcement'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: StreamBuilder<List<Announcement>>(
                stream: _repo.watchAdminList(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Failed to load announcements: ${snapshot.error}',
                        ),
                      ),
                    );
                  }
                  final items = snapshot.data ?? const <Announcement>[];
                  if (items.isEmpty) {
                    return const Center(child: Text('No announcements yet'));
                  }

                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 0),
                    itemBuilder: (context, index) {
                      final a = items[index];
                      return ListTile(
                        leading: a.pinned
                            ? const Icon(Icons.push_pin, color: Colors.amber)
                            : const Icon(Icons.campaign_outlined),
                        title: Text(a.title),
                        subtitle: Text(
                          '${a.location} • ${a.eventDateTime}',
                          maxLines: 2,
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _openEditDialog(existing: a);
                            } else if (value == 'delete') {
                              _delete(a);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(Announcement a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete announcement'),
        content: Text('Delete "${a.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _repo.delete(a);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _openEditDialog({Announcement? existing}) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final locationCtrl = TextEditingController(text: existing?.location ?? '');
    DateTime? eventDateTime = existing?.eventDateTime;
    bool pinned = existing?.pinned ?? false;
    String status = existing?.status ?? 'draft';
    Uint8List? imageBytes;
    String? imageFileName;
    Uint8List? attachmentBytes;
    String? attachmentFileName;
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> pickDateTime() async {
              final now = DateTime.now();
              final date = await showDatePicker(
                context: context,
                initialDate: eventDateTime ?? now,
                firstDate: now.subtract(const Duration(days: 365)),
                lastDate: now.add(const Duration(days: 365 * 5)),
              );
              if (date == null) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(eventDateTime ?? now),
              );
              if (time == null) return;
              setState(() {
                eventDateTime = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
              });
            }

            Future<void> pickImage() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.image,
                withData: true,
              );
              if (result == null || result.files.single.bytes == null) return;
              setState(() {
                imageBytes = result.files.single.bytes;
                imageFileName = result.files.single.name;
              });
            }

            Future<void> pickAttachment() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: const ['pdf'],
                withData: true,
              );
              if (result == null || result.files.single.bytes == null) return;
              setState(() {
                attachmentBytes = result.files.single.bytes;
                attachmentFileName = result.files.single.name;
              });
            }

            Future<void> save() async {
              if (titleCtrl.text.trim().isEmpty ||
                  descCtrl.text.trim().isEmpty ||
                  locationCtrl.text.trim().isEmpty ||
                  eventDateTime == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Title, description, location and date/time are required',
                    ),
                  ),
                );
                return;
              }
              // Preview dialog before final save
              final previewOk = await showDialog<bool>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('Preview announcement'),
                    content: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titleCtrl.text.trim(),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'When: ${eventDateTime!}\nWhere: ${locationCtrl.text.trim()}',
                          ),
                          const SizedBox(height: 8),
                          Text(descCtrl.text.trim()),
                          const SizedBox(height: 8),
                          Text('Status: $status  •  Pinned: $pinned'),
                          if (imageFileName != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text('Image: $imageFileName'),
                            ),
                          if (attachmentFileName != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('Attachment: $attachmentFileName'),
                            ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Back'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Publish'),
                      ),
                    ],
                  );
                },
              );
              if (previewOk != true) {
                return;
              }

              setState(() => saving = true);
              try {
                if (existing == null) {
                  await _repo.create(
                    title: titleCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    eventDateTime: eventDateTime!,
                    location: locationCtrl.text.trim(),
                    status: status,
                    pinned: pinned,
                    imageBytes: imageBytes,
                    imageFileName: imageFileName,
                    attachmentBytes: attachmentBytes,
                    attachmentFileName: attachmentFileName,
                  );
                } else {
                  final updated = existing.copyWith(
                    title: titleCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    eventDateTime: eventDateTime!,
                    location: locationCtrl.text.trim(),
                    status: status,
                    pinned: pinned,
                  );
                  await _repo.update(
                    updated,
                    newImageBytes: imageBytes,
                    newImageFileName: imageFileName,
                    newAttachmentBytes: attachmentBytes,
                    newAttachmentFileName: attachmentFileName,
                  );
                }
                if (mounted) Navigator.of(dialogContext).pop();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
              } finally {
                if (mounted) setState(() => saving = false);
              }
            }

            return AlertDialog(
              title: Text(
                existing == null ? 'New announcement' : 'Edit announcement',
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: locationCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Location',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              eventDateTime == null
                                  ? 'No event date/time selected'
                                  : 'Event: $eventDateTime',
                            ),
                          ),
                          TextButton(
                            onPressed: pickDateTime,
                            child: const Text('Pick date & time'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Checkbox(
                            value: pinned,
                            onChanged: (v) => setState(() {
                              pinned = v ?? false;
                            }),
                          ),
                          const Text('Pin announcement'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: status,
                        items: const [
                          DropdownMenuItem(
                            value: 'draft',
                            child: Text('Draft'),
                          ),
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(
                            value: 'archived',
                            child: Text('Archived'),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          status = v ?? 'draft';
                        }),
                        decoration: const InputDecoration(labelText: 'Status'),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: pickImage,
                            icon: const Icon(Icons.image_outlined),
                            label: Text(
                              imageFileName == null
                                  ? 'Select image'
                                  : 'Image: $imageFileName',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: pickAttachment,
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: Text(
                              attachmentFileName == null
                                  ? 'Select PDF attachment'
                                  : 'Attachment: $attachmentFileName',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(saving ? 'Saving...' : 'Save announcement'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
