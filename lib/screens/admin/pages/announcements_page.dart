// ignore_for_file: use_build_context_synchronously

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../models/announcement.dart';
import '../../../services/announcements_repository.dart';
import '../../../widgets/safe_image.dart';

class AdminAnnouncementsPage extends StatefulWidget {
  const AdminAnnouncementsPage({super.key});

  @override
  State<AdminAnnouncementsPage> createState() => _AdminAnnouncementsPageState();
}

class _AdminAnnouncementsPageState extends State<AdminAnnouncementsPage> {
  final _repo = AnnouncementsRepository();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Text(
            'Announcements',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Stats chips
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
                  final views = items.fold<int>(0, (s, a) => s + a.views);
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
                label: const Text('New Announcement'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── List ──────────────────────────────────────────────────────────
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
                          'Failed to load: ${snapshot.error}',
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                    );
                  }
                  final items = snapshot.data ?? const <Announcement>[];
                  if (items.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.campaign_outlined,
                            size: 56,
                            color: colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No announcements yet',
                            style: TextStyle(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 0),
                    itemBuilder: (context, index) {
                      final a = items[index];
                      return ListTile(
                        leading: a.imageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SafeImage(
                                  imageUrl: a.imageUrl!,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _fallbackIcon(a),
                                ),
                              )
                            : _fallbackIcon(a),
                        title: Text(
                          a.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${a.location} • ${DateFormat('MMM d, yyyy  h:mm a').format(a.eventDateTime)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Status chip
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _statusColor(
                                  a.status,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                a.status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _statusColor(a.status),
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _openEditDialog(existing: a);
                                } else if (value == 'delete') {
                                  _delete(a);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
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

  Widget _fallbackIcon(Announcement a) {
    return CircleAvatar(
      backgroundColor: Colors.deepOrange.withValues(alpha: 0.12),
      child: Icon(
        a.pinned ? Icons.push_pin : Icons.campaign_outlined,
        color: Colors.deepOrange,
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'archived':
        return Colors.grey;
      default:
        return Colors.orange;
    }
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
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
    final person1Ctrl = TextEditingController(
      text: existing?.person1Name ?? '',
    );
    final person2Ctrl = TextEditingController(
      text: existing?.person2Name ?? '',
    );
    DateTime? eventDateTime = existing?.eventDateTime;
    bool pinned = existing?.pinned ?? false;
    String status = existing?.status ?? 'draft';
    String announcementType = existing?.announcementType ?? 'general';
    Uint8List? imageBytes;
    String? imageFileName;
    Uint8List? image2Bytes;
    String? image2FileName;
    Uint8List? attachmentBytes;
    String? attachmentFileName;
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setS) {
            // ── Date / time picker ──────────────────────────────────────
            Future<void> pickDateTime() async {
              final now = DateTime.now();
              final date = await showDatePicker(
                context: context,
                initialDate: eventDateTime ?? now,
                firstDate: now.subtract(const Duration(days: 365)),
                lastDate: now.add(const Duration(days: 365 * 5)),
              );
              if (!context.mounted || date == null) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(eventDateTime ?? now),
              );
              if (!context.mounted || time == null) return;
              setS(() {
                eventDateTime = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
              });
            }

            // ── Image picker ────────────────────────────────────────────
            Future<void> pickImage() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.image,
                withData: true,
              );
              if (result == null || result.files.single.bytes == null) return;
              setS(() {
                imageBytes = result.files.single.bytes;
                imageFileName = result.files.single.name;
              });
            }

            Future<void> pickImage2() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.image,
                withData: true,
              );
              if (result == null || result.files.single.bytes == null) return;
              setS(() {
                image2Bytes = result.files.single.bytes;
                image2FileName = result.files.single.name;
              });
            }

            // ── Attachment picker ───────────────────────────────────────
            Future<void> pickAttachment() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: const ['pdf'],
                withData: true,
              );
              if (result == null || result.files.single.bytes == null) return;
              setS(() {
                attachmentBytes = result.files.single.bytes;
                attachmentFileName = result.files.single.name;
              });
            }

            // ── Save ────────────────────────────────────────────────────
            Future<void> save() async {
              final isMarriage = announcementType == 'marriage';
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

              if (isMarriage &&
                  (person1Ctrl.text.trim().isEmpty ||
                      person2Ctrl.text.trim().isEmpty)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'For Marriage announcements, both names are required',
                    ),
                  ),
                );
                return;
              }

              setS(() {
                saving = true;
              });

              try {
                if (existing == null) {
                  await _repo.create(
                    title: titleCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    eventDateTime: eventDateTime!,
                    location: locationCtrl.text.trim(),
                    status: status,
                    pinned: pinned,
                    announcementType: announcementType,
                    person1Name: person1Ctrl.text.trim().isEmpty
                        ? null
                        : person1Ctrl.text.trim(),
                    person2Name: person2Ctrl.text.trim().isEmpty
                        ? null
                        : person2Ctrl.text.trim(),
                    imageBytes: imageBytes,
                    imageFileName: imageFileName,
                    image2Bytes: image2Bytes,
                    image2FileName: image2FileName,
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
                    announcementType: announcementType,
                    person1Name: person1Ctrl.text.trim().isEmpty
                        ? null
                        : person1Ctrl.text.trim(),
                    person2Name: person2Ctrl.text.trim().isEmpty
                        ? null
                        : person2Ctrl.text.trim(),
                  );
                  await _repo.update(
                    updated,
                    newImageBytes: imageBytes,
                    newImageFileName: imageFileName,
                    newImage2Bytes: image2Bytes,
                    newImage2FileName: image2FileName,
                    newAttachmentBytes: attachmentBytes,
                    newAttachmentFileName: attachmentFileName,
                  );
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (mounted) context.go('/admin/announcements');
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text('Failed to save: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } finally {
                if (dialogContext.mounted) setS(() => saving = false);
              }
            }

            // ── Dialog UI ───────────────────────────────────────────────
            return AlertDialog(
              scrollable: true,
              title: Text(
                existing == null ? 'New Announcement' : 'Edit Announcement',
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Image section ─────────────────────────────
                    if (announcementType == 'marriage') ...[
                      Text(
                        'Groom Photo',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    _buildImageSection(
                      context,
                      imageBytes: imageBytes,
                      existingImageUrl: existing?.imageUrl,
                      onPick: pickImage,
                      onRemove: () => setS(() => imageBytes = null),
                    ),
                    if (announcementType == 'marriage') ...[
                      const SizedBox(height: 16),
                      Text(
                        'Bride Photo',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildImageSection(
                        context,
                        imageBytes: image2Bytes,
                        existingImageUrl: existing?.imageUrl2,
                        onPick: pickImage2,
                        onRemove: () => setS(() => image2Bytes = null),
                      ),
                    ],
                    const SizedBox(height: 12),

                    // ── Title ─────────────────────────────────────
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'Title *'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description *',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: locationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Location *',
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Date/time ─────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            eventDateTime == null
                                ? 'No date/time selected *'
                                : DateFormat(
                                    'MMM d, yyyy  h:mm a',
                                  ).format(eventDateTime!),
                            style: TextStyle(
                              color: eventDateTime == null
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: pickDateTime,
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: const Text('Pick date & time'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── Pinned ────────────────────────────────────
                    Row(
                      children: [
                        Checkbox(
                          value: pinned,
                          onChanged: (v) => setS(() => pinned = v ?? false),
                        ),
                        const Text('Pin announcement'),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // ── Status ────────────────────────────────────
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(value: 'draft', child: Text('Draft')),
                        DropdownMenuItem(
                          value: 'active',
                          child: Text('Active'),
                        ),
                        DropdownMenuItem(
                          value: 'archived',
                          child: Text('Archived'),
                        ),
                      ],
                      onChanged: (v) => setS(() => status = v ?? 'draft'),
                    ),
                    const SizedBox(height: 12),

                    // ── Announcement Type ─────────────────────────
                    DropdownButtonFormField<String>(
                      value: announcementType,
                      decoration: const InputDecoration(
                        labelText: 'Announcement Type',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'general',
                          child: Text('General'),
                        ),
                        DropdownMenuItem(
                          value: 'marriage',
                          child: Text('Marriage'),
                        ),
                        DropdownMenuItem(
                          value: 'baptism',
                          child: Text('Baptism'),
                        ),
                        DropdownMenuItem(
                          value: 'confirmation',
                          child: Text('Confirmation'),
                        ),
                        DropdownMenuItem(value: 'death', child: Text('Death')),
                      ],
                      onChanged: (v) =>
                          setS(() => announcementType = v ?? 'general'),
                    ),
                    const SizedBox(height: 12),

                    if (announcementType == 'marriage') ...[
                      TextField(
                        controller: person1Ctrl,
                        decoration: const InputDecoration(
                          labelText: 'Person 1 (Groom) *',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: person2Ctrl,
                        decoration: const InputDecoration(
                          labelText: 'Person 2 (Bride) *',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── PDF attachment ────────────────────────────
                    OutlinedButton.icon(
                      onPressed: pickAttachment,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(
                        attachmentFileName == null
                            ? 'Select PDF attachment (optional)'
                            : 'PDF: $attachmentFileName',
                      ),
                    ),
                  ],
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
                  label: Text(saving ? 'Saving…' : 'Save Announcement'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Image section widget shown inside the edit dialog.
  Widget _buildImageSection(
    BuildContext context, {
    Uint8List? imageBytes,
    String? existingImageUrl,
    required VoidCallback onPick,
    required VoidCallback onRemove,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    if (imageBytes != null) {
      // Newly selected image — show memory preview
      return SizedBox(
        height: 180,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                imageBytes,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  _iconBtn(Icons.photo_camera, onPick, colorScheme),
                  const SizedBox(width: 4),
                  _iconBtn(
                    Icons.close,
                    onRemove,
                    colorScheme,
                    color: colorScheme.error,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (existingImageUrl != null) {
      // Already-saved image — show network preview + change button
      return SizedBox(
        height: 180,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SafeImage(
                imageUrl: existingImageUrl,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _noImagePlaceholder(context, onPick, colorScheme),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _iconBtn(Icons.photo_camera, onPick, colorScheme),
            ),
          ],
        ),
      );
    }

    // No image yet
    return _noImagePlaceholder(context, onPick, colorScheme);
  }

  Widget _noImagePlaceholder(
    BuildContext context,
    VoidCallback onPick,
    ColorScheme colorScheme,
  ) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 40,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap to upload photo',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(
    IconData icon,
    VoidCallback onTap,
    ColorScheme cs, {
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (color ?? cs.primary).withValues(alpha: 0.9),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
