import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../models/register_ocr_entry.dart';
import '../../../providers/ocr_jobs_provider.dart';
import '../../../services/register_ocr_parser.dart';
import '../../../widgets/register_ocr_table.dart';

class AdminOcrQueuePage extends ConsumerStatefulWidget {
  const AdminOcrQueuePage({super.key});

  @override
  ConsumerState<AdminOcrQueuePage> createState() => _AdminOcrQueuePageState();
}

class _AdminOcrQueuePageState extends ConsumerState<AdminOcrQueuePage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.document_scanner_outlined,
                    size: 32,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'OCR Queue & Jobs',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Each job shows parsed register records in a table for review.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(child: _AllJobsList(ref: ref)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllJobsList extends ConsumerWidget {
  const _AllJobsList({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(ocrJobsAllProvider(50));

    return jobsAsync.when(
      data: (jobs) {
        if (jobs.isEmpty) {
          return const Center(child: Text('No OCR jobs available'));
        }
        return ListView.builder(
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final job = jobs[index];
            return _JobCard(
              job: job,
              onEdit: () => _editJob(context, ref, job),
              onDelete: () => _deleteJob(context, ref, job['id'] as String),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Future<void> _deleteJob(
    BuildContext context,
    WidgetRef ref,
    String jobId,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete OCR Job'),
        content: const Text('Are you sure you want to delete this job?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final repo = ref.read(ocrJobsRepositoryProvider);
      await repo.deleteJob(jobId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job deleted successfully')),
        );
        ref.invalidate(ocrJobsAllProvider);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete job: $e')),
        );
      }
    }
  }
}

class _JobCard extends StatefulWidget {
  const _JobCard({
    required this.job,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> job;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<_JobCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final job = widget.job;
    final status = job['status']?.toString() ?? 'pending';
    final type = job['type']?.toString() ?? 'Unknown';
    final volNumber = job['vol_number']?.toString() ?? '';
    final seriesNumber = job['series_number']?.toString() ?? '';
    final createdAt = job['created_at']?.toString() ?? '';
    final entries = registerEntriesForJob(job);
    final recordCount = entries.isNotEmpty
        ? entries.length
        : (job['record_count'] as int? ?? 0);

    final statusStyle = _statusStyle(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: statusStyle.color.withValues(alpha: 0.12),
                    child: Icon(statusStyle.icon, color: statusStyle.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_capitalize(type)} · ${_volSeriesLabel(volNumber, seriesNumber)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _MetaChip(
                              label: status.toUpperCase(),
                              color: statusStyle.color,
                            ),
                            _MetaChip(
                              label: '$recordCount record(s)',
                              color: colorScheme.primary,
                            ),
                            if (createdAt.isNotEmpty)
                              _MetaChip(
                                label: _formatCreated(createdAt),
                                color: colorScheme.outline,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                    onPressed: () => setState(() => _expanded = !_expanded),
                    tooltip: _expanded ? 'Collapse' : 'Expand',
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Review & Edit',
                    onPressed: widget.onEdit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Delete',
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Register records',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  RegisterOcrTable(
                    fillGeneration: 0,
                    entries: entries,
                    readOnly: true,
                    showCheckboxes: false,
                    compact: true,
                    maxHeight: entries.isEmpty ? 120 : 280,
                  ),
                  if (entries.isEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'No rows parsed yet. Open Verify to edit raw text and re-parse.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: widget.onEdit,
                      icon: const Icon(Icons.fact_check_outlined, size: 18),
                      label: const Text('Verify & Edit'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _volSeriesLabel(String vol, String series) {
    final parts = <String>[
      if (vol.isNotEmpty) 'Vol $vol' else 'Vol —',
      if (series.isNotEmpty) 'Series $series' else 'Series —',
    ];
    return parts.join(' · ');
  }

  String _formatCreated(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('MMM d, yyyy · h:mm a').format(dt.toLocal());
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _StatusStyle {
  const _StatusStyle(this.color, this.icon);
  final Color color;
  final IconData icon;
}

_StatusStyle _statusStyle(String status) {
  switch (status.toLowerCase()) {
    case 'completed':
      return const _StatusStyle(Colors.green, Icons.check_circle);
    case 'processing':
      return const _StatusStyle(Colors.orange, Icons.sync);
    case 'error':
    case 'failed':
      return const _StatusStyle(Colors.red, Icons.error);
    default:
      return const _StatusStyle(Colors.grey, Icons.pending);
  }
}

Future<void> _editJob(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> job,
) async {
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => _EditJobDialog(job: job),
  );

  if (result != null && context.mounted) {
    try {
      final repo = ref.read(ocrJobsRepositoryProvider);
      await repo.updateJob(job['id'] as String, result);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job updated and saved successfully')),
        );
        ref.invalidate(ocrJobsAllProvider);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update job: $e')),
        );
      }
    }
  }
}

class _EditJobDialog extends StatefulWidget {
  const _EditJobDialog({required this.job});
  final Map<String, dynamic> job;

  @override
  State<_EditJobDialog> createState() => _EditJobDialogState();
}

class _EditJobDialogState extends State<_EditJobDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String _type;
  late TextEditingController _volCtrl;
  late TextEditingController _seriesCtrl;
  late TextEditingController _rawTextCtrl;
  late List<RegisterOcrEntry> _entries;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _type = widget.job['type']?.toString() ?? 'baptism';
    _volCtrl = TextEditingController(
      text: widget.job['vol_number']?.toString() ?? '',
    );
    _seriesCtrl = TextEditingController(
      text: widget.job['series_number']?.toString() ?? '',
    );
    _rawTextCtrl = TextEditingController(
      text: widget.job['raw_text']?.toString() ?? '',
    );
    _entries = registerEntriesForJob(widget.job);
    if (_entries.isEmpty && _rawTextCtrl.text.trim().isNotEmpty) {
      _reparse();
    }
  }

  void _reparse() {
    final result = RegisterOcrParser.parse(
      _rawTextCtrl.text,
      recordType: _type,
    );
    setState(() => _entries = result.entries);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _volCtrl.dispose();
    _seriesCtrl.dispose();
    _rawTextCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogW = size.width > 900 ? 900.0 : size.width * 0.95;
    final dialogH = size.height > 700 ? 640.0 : size.height * 0.85;

    return Dialog(
      child: SizedBox(
        width: dialogW,
        height: dialogH,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Verify OCR Job',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: 'Records (${_entries.length})'),
                const Tab(text: 'Job & Raw text'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  RegisterOcrTable(
                    fillGeneration: 0,
                    entries: _entries,
                    onChanged: () => setState(() {}),
                    onRemove: (i) => setState(() => _entries.removeAt(i)),
                    compact: true,
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _type,
                          decoration: const InputDecoration(labelText: 'Type'),
                          items: const [
                            DropdownMenuItem(
                              value: 'baptism',
                              child: Text('Baptism'),
                            ),
                            DropdownMenuItem(
                              value: 'confirmation',
                              child: Text('Confirmation'),
                            ),
                            DropdownMenuItem(
                              value: 'marriage',
                              child: Text('Marriage'),
                            ),
                            DropdownMenuItem(
                              value: 'funeral',
                              child: Text('Funeral'),
                            ),
                          ],
                          onChanged: (v) => setState(() => _type = v ?? 'baptism'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _volCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Vol Number',
                            hintText: 'Register volume number',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _seriesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Series Number',
                            hintText: 'Register series number',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _rawTextCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Raw scanned text',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 10,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            _reparse();
                            _tabController.animateTo(0);
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Re-parse into records table'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context, {
                        'type': _type,
                        'vol_number': _volCtrl.text.trim(),
                        'series_number': _seriesCtrl.text.trim(),
                        'raw_text': _rawTextCtrl.text.trim(),
                        'parsed_entries': registerEntriesToMaps(_entries),
                        'record_count': _entries.length,
                      });
                    },
                    child: const Text('Done & Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
