import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/ocr_jobs_provider.dart';
import '../../../services/ocr_jobs_repository.dart';

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
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
              Row(
                children: [
                  Icon(
                    Icons.fact_check_outlined,
                    size: 32,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'OCR Field Verification',
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
                'Edit/confirm OCR-extracted fields before saving an official record.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.inbox_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: unassignedAsync.when(
                          loading: () => const Text('Loading available tasks…'),
                          error: (e, _) => Text('Available tasks: error ($e)'),
                          data: (rows) => Text(
                            'Available unassigned tasks: ${rows.length}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final repo = OcrJobsRepository();
                          final claimed = await repo.claimNextAvailable();
                          ref.invalidate(ocrJobsAssignedToMeProvider(50));
                          ref.invalidate(ocrJobsUnassignedProvider(10));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  claimed == null
                                      ? 'No available OCR tasks to claim'
                                      : 'Claimed OCR task #$claimed',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.assignment_turned_in_outlined),
                        label: const Text('Claim'),
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
                    child: Text(
                      'Failed to load OCR jobs: $e',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  data: (rows) {
                    if (rows.isEmpty) {
                      return const Center(child: Text('No assigned jobs.'));
                    }

                    final selected = focusedId == null
                        ? rows.first
                        : rows.firstWhere(
                            (m) => (m['id'] ?? '').toString() == focusedId,
                            orElse: () => rows.first,
                          );

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 860;
                        final list = _JobsList(
                          rows: rows,
                          selectedId: (selected['id'] ?? '').toString(),
                        );
                        final detail = _VerifyDetail(job: selected);

                        if (isNarrow) {
                          return Column(
                            children: [
                              SizedBox(height: 220, child: list),
                              const SizedBox(height: 12),
                              Expanded(child: detail),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            SizedBox(width: 360, child: list),
                            const SizedBox(width: 12),
                            Expanded(child: detail),
                          ],
                        );
                      },
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
  }
}

class _JobsList extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final String selectedId;
  const _JobsList({required this.rows, required this.selectedId});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final m = rows[i];
          final id = (m['id'] ?? '').toString();
          final type = (m['type'] ?? 'ocr').toString();
          final status = (m['status'] ?? 'unknown').toString();
          final selected = id == selectedId;

          return ListTile(
            selected: selected,
            title: Text(type),
            subtitle: Text('Status: $status'),
            onTap: () => context.go('/staff/ocr/verify', extra: {'id': id}),
          );
        },
      ),
    );
  }
}

class _VerifyDetail extends StatefulWidget {
  final Map<String, dynamic> job;
  const _VerifyDetail({required this.job});

  @override
  State<_VerifyDetail> createState() => _VerifyDetailState();
}

class _VerifyDetailState extends State<_VerifyDetail> {
  bool _certify = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final id = (widget.job['id'] ?? '').toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Job #$id',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Split view + confidence badges will be implemented next.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _certify,
              onChanged: (v) => setState(() => _certify = v == true),
              title: const Text('I certify the fields are correct'),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: !_certify
                    ? null
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Save & Lock not implemented yet.'),
                          ),
                        );
                      },
                icon: const Icon(Icons.lock_outline),
                label: const Text('Save & Lock'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
