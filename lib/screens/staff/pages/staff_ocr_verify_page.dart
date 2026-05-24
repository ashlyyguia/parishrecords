import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../models/register_ocr_entry.dart';
import '../../../providers/ocr_jobs_provider.dart';
import '../../../providers/records_provider.dart';
import '../../../services/register_ocr_parser.dart';
import '../../../services/register_ocr_record_save.dart';
import '../../../services/register_ocr_scan_helper.dart';
import '../../../widgets/register_ocr_table.dart';

class StaffOcrVerifyPage extends ConsumerWidget {
  const StaffOcrVerifyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;

    final extra = GoRouterState.of(context).extra;
    final focusedId = extra is Map ? extra['id']?.toString() : null;

    final jobsAsync = ref.watch(ocrJobsAssignedToMeProvider(50));
    final unassignedAsync = ref.watch(ocrJobsUnassignedProvider(10));

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('OCR Verification'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/staff/ocr/upload'),
            icon: const Icon(Icons.upload_file),
            label: const Text('New scan'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review OCR-extracted register rows, edit fields, then save '
                'official records and lock the job.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.inbox_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: unassignedAsync.when(
                          loading: () =>
                              const Text('Loading available tasks…'),
                          error: (e, _) =>
                              Text('Available tasks: error ($e)'),
                          data: (rows) => Text(
                            'Unassigned tasks: ${rows.length}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final repo = ref.read(ocrJobsRepositoryProvider);
                          final claimed = await repo.claimNextAvailable();
                          ref.invalidate(ocrJobsAssignedToMeProvider(50));
                          ref.invalidate(ocrJobsUnassignedProvider(10));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  claimed == null
                                      ? 'No available OCR tasks'
                                      : 'Claimed task #$claimed',
                                ),
                              ),
                            );
                            if (claimed != null) {
                              context.go(
                                '/staff/ocr/verify',
                                extra: {'id': claimed},
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.assignment_turned_in_outlined),
                        label: const Text('Claim next'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: jobsAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (e, _) => Center(
                    child: Text('Failed to load OCR jobs: $e'),
                  ),
                  data: (rows) {
                    final active = rows
                        .where((m) => m['locked'] != true)
                        .toList();
                    if (active.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.task_alt_outlined,
                              size: 56,
                              color: colorScheme.outline,
                            ),
                            const SizedBox(height: 12),
                            const Text('No open jobs assigned to you.'),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () =>
                                  context.go('/staff/ocr/upload'),
                              child: const Text('Upload register scan'),
                            ),
                          ],
                        ),
                      );
                    }

                    final selected = focusedId == null
                        ? active.first
                        : active.firstWhere(
                            (m) => (m['id'] ?? '').toString() == focusedId,
                            orElse: () => active.first,
                          );

                    final isNarrow = width < 860;
                    final list = _JobsList(
                      rows: active,
                      selectedId: (selected['id'] ?? '').toString(),
                    );
                    final detail = _VerifyDetailPanel(job: selected);

                    if (isNarrow) {
                      return Column(
                        children: [
                          SizedBox(height: 200, child: list),
                          const SizedBox(height: 12),
                          Expanded(child: detail),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 320, child: list),
                        const SizedBox(width: 12),
                        Expanded(child: detail),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobsList extends StatelessWidget {
  const _JobsList({required this.rows, required this.selectedId});

  final List<Map<String, dynamic>> rows;
  final String selectedId;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final m = rows[i];
          final id = (m['id'] ?? '').toString();
          final type = (m['type'] ?? 'ocr').toString();
          final status = (m['status'] ?? 'unknown').toString();
          final count = m['record_count'] ?? 0;
          final selected = id == selectedId;

          return ListTile(
            selected: selected,
            title: Text(type[0].toUpperCase() + type.substring(1)),
            subtitle: Text('Status: $status · $count row(s)'),
            onTap: () => context.go('/staff/ocr/verify', extra: {'id': id}),
          );
        },
      ),
    );
  }
}

class _VerifyDetailPanel extends ConsumerStatefulWidget {
  const _VerifyDetailPanel({required this.job});

  final Map<String, dynamic> job;

  @override
  ConsumerState<_VerifyDetailPanel> createState() =>
      _VerifyDetailPanelState();
}

class _VerifyDetailPanelState extends ConsumerState<_VerifyDetailPanel> {
  late List<RegisterOcrEntry> _entries;
  late TextEditingController _rawTextCtrl;
  bool _certify = false;
  bool _createRecords = true;
  bool _saving = false;
  bool _showRaw = false;
  int _fillGeneration = 0;

  @override
  void initState() {
    super.initState();
    _entries = RegisterOcrScanHelper.ensureUniqueEntryIds(
      registerEntriesForJob(widget.job),
    );
    if (_entries.isEmpty) {
      _entries = [RegisterOcrEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: '',
        lineNo: '1',
        baptismDateText: '',
        rawLine: '',
      )];
    }
    _rawTextCtrl = TextEditingController(
      text: widget.job['raw_text']?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _VerifyDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.job['id'] ?? '').toString() !=
        (widget.job['id'] ?? '').toString()) {
      _entries = RegisterOcrScanHelper.ensureUniqueEntryIds(
        registerEntriesForJob(widget.job),
      );
      _rawTextCtrl.text = widget.job['raw_text']?.toString() ?? '';
      _certify = false;
      _fillGeneration++;
    }
  }

  @override
  void dispose() {
    _rawTextCtrl.dispose();
    super.dispose();
  }

  String get _jobId => (widget.job['id'] ?? '').toString();
  String get _type => (widget.job['type'] ?? 'baptism').toString();
  String get _vol => widget.job['vol_number']?.toString() ?? '';
  String get _series => widget.job['series_number']?.toString() ?? '';

  int get _validSelected =>
      _entries.where((e) => e.selected && e.isValid).length;

  void _reparse() {
    final parsed = RegisterOcrParser.parse(
      _rawTextCtrl.text,
      recordType: _type,
    );
    setState(() {
      _entries = RegisterOcrScanHelper.ensureUniqueEntryIds(parsed.entries);
      _fillGeneration++;
    });
  }

  Future<void> _saveAndLock() async {
    if (!_certify || _jobId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save & lock job?'),
        content: Text(
          _createRecords && _validSelected > 0
              ? 'This will create $_validSelected official record(s), '
                  'update the OCR job, and mark it completed (locked).'
              : 'This will save your edits and lock the job without '
                  'creating parish records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(ocrJobsRepositoryProvider);
      final maps = registerEntriesToMaps(_entries);

      if (_createRecords && _validSelected > 0) {
        await saveRegisterOcrEntries(
          ref: ref,
          entries: _entries,
          recordType: _type,
          volNumber: _vol,
          seriesNumber: _series,
          source: 'register_ocr_verify',
        );
      }

      await repo.saveAndLockJob(
        jobId: _jobId,
        parsedEntries: maps,
        rawText: _rawTextCtrl.text.trim(),
        recordCount: _entries.length,
      );

      ref.invalidate(ocrJobsAssignedToMeProvider(50));
      ref.invalidate(ocrJobsUnassignedProvider(10));
      ref.invalidate(recordsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _createRecords && _validSelected > 0
                ? 'Saved $_validSelected record(s) and locked job.'
                : 'Job locked successfully.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      context.go('/staff/records');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openBulkEditor() async {
    await context.push(
      '/staff/ocr/bulk-records',
      extra: {
        'rawText': _rawTextCtrl.text,
        'recordType': _type,
        'volNumber': _vol,
        'seriesNumber': _series,
        'entries': _entries,
      },
    );
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final locked = widget.job['locked'] == true;
    final isMarriage = _type.toLowerCase() == 'marriage';

    if (isMarriage) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.favorite_outline, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Marriage register jobs',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Open the upload page, scan the register, and use the '
                'marriage table editor. Then create an OCR job from there.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/staff/ocr/upload'),
                child: const Text('Go to OCR upload'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Job #$_jobId',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(
                      label: Text(_type),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (_vol.isNotEmpty)
                      Chip(
                        label: Text('Vol $_vol'),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (_series.isNotEmpty)
                      Chip(
                        label: Text('Series $_series'),
                        visualDensity: VisualDensity.compact,
                      ),
                    Chip(
                      label: Text('$_validSelected valid selected'),
                      backgroundColor:
                          colorScheme.primaryContainer.withValues(alpha: 0.5),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _showRaw = !_showRaw),
                  icon: Icon(_showRaw ? Icons.expand_less : Icons.expand_more),
                  label: Text(_showRaw ? 'Hide raw text' : 'Show raw text'),
                ),
                TextButton.icon(
                  onPressed: _reparse,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Re-parse'),
                ),
                TextButton.icon(
                  onPressed: _openBulkEditor,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Bulk save'),
                ),
              ],
            ),
          ),
          if (_showRaw)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _rawTextCtrl,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Raw OCR text',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          Expanded(
            child: RegisterOcrTable(
              key: ValueKey('verify-ocr-$_fillGeneration'),
              fillGeneration: _fillGeneration,
              entries: _entries,
              onChanged: () => setState(() {}),
              onRemove: locked
                  ? null
                  : (i) => setState(() => _entries.removeAt(i)),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _createRecords,
                  onChanged: locked
                      ? null
                      : (v) => setState(() => _createRecords = v == true),
                  title: const Text('Create official parish records'),
                  subtitle: Text(
                    '$_validSelected row(s) ready with name and baptism date',
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _certify,
                  onChanged: locked
                      ? null
                      : (v) => setState(() => _certify = v == true),
                  title: const Text('I certify the fields are correct'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: locked || !_certify || _saving
                      ? null
                      : _saveAndLock,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.lock_outline),
                  label: Text(
                    _saving ? 'Saving…' : 'Save & Lock',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
