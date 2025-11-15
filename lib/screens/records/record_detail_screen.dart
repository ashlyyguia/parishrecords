import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../providers/records_provider.dart';
import '../../models/record.dart';

class RecordDetailScreen extends ConsumerWidget {
  final String recordId;
  const RecordDetailScreen({super.key, required this.recordId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(recordsProvider);
    final rec = records.where((r) => r.id == recordId).cast<ParishRecord?>().firstOrNull;

    if (rec == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record')),
        body: const Center(child: Text('Record not found')),
      );
    }

    final df = DateFormat.yMMMMd();
    return Scaffold(
      appBar: AppBar(
        title: Text(rec.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.go('/records/${rec.id}/edit', extra: rec),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Delete record?'),
                    content: Text('This will delete "${rec.name}"'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref.read(recordsProvider.notifier).deleteRecord(rec.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record deleted')));
                    Navigator.of(context).pop();
                  }
                }
              }
            },
            itemBuilder: (c) => [
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (rec.imagePath != null) ...[
            kIsWeb
                ? const SizedBox(height: 180, child: Center(child: Text('Image preview not available on web')))
                : AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.file(File(rec.imagePath!), fit: BoxFit.cover),
                  ),
          ] else ...[
            Container(
              height: 140,
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F4F8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE6E8EF)),
              ),
              child: const Center(child: Text('No image attached')),
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rec.name, style: Theme.of(context).textTheme.titleLarge, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Chip(label: Text(_capitalize(rec.type.name))),
                    const SizedBox(width: 8),
                    const Icon(Icons.calendar_today_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text(df.format(rec.date)),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.category_outlined),
                        title: const Text('Record Type'),
                        subtitle: Text(_capitalize(rec.type.name)),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        leading: const Icon(Icons.calendar_today_outlined),
                        title: const Text('Record Date'),
                        subtitle: Text(df.format(rec.date)),
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

  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

extension FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
