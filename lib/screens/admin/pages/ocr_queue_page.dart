import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/ocr_jobs_provider.dart';

class AdminOcrQueuePage extends ConsumerStatefulWidget {
  const AdminOcrQueuePage({super.key});

  @override
  ConsumerState<AdminOcrQueuePage> createState() => _AdminOcrQueuePageState();
}

class _AdminOcrQueuePageState extends ConsumerState<AdminOcrQueuePage> {
  int _selectedTab = 0;

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
                'Manage OCR jobs, approvals, and re-runs.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('Unassigned'),
                    icon: Icon(Icons.pending_outlined),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('Assigned'),
                    icon: Icon(Icons.person_outline),
                  ),
                ],
                selected: {_selectedTab},
                onSelectionChanged: (Set<int> newSelection) {
                  setState(() {
                    _selectedTab = newSelection.first;
                  });
                },
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _selectedTab == 0
                    ? _UnassignedJobsList(ref: ref)
                    : _AssignedJobsList(ref: ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnassignedJobsList extends ConsumerWidget {
  final WidgetRef ref;
  const _UnassignedJobsList({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(ocrJobsUnassignedProvider(50));

    return jobsAsync.when(
      data: (jobs) {
        if (jobs.isEmpty) {
          return const Center(child: Text('No unassigned OCR jobs'));
        }
        return ListView.builder(
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final job = jobs[index];
            return _JobCard(
              job: job,
              isUnassigned: true,
              onClaim: () => _claimJob(context, ref, job['id']),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Future<void> _claimJob(
    BuildContext context,
    WidgetRef ref,
    String jobId,
  ) async {
    try {
      final repo = ref.read(ocrJobsRepositoryProvider);
      final result = await repo.claimJob(jobId);
      if (result != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job claimed successfully')),
        );
        ref.invalidate(ocrJobsUnassignedProvider);
        ref.invalidate(ocrJobsAssignedToMeProvider);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to claim job: $e')));
      }
    }
  }
}

class _AssignedJobsList extends ConsumerWidget {
  final WidgetRef ref;
  const _AssignedJobsList({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(ocrJobsAssignedToMeProvider(50));

    return jobsAsync.when(
      data: (jobs) {
        if (jobs.isEmpty) {
          return const Center(child: Text('No assigned OCR jobs'));
        }
        return ListView.builder(
          itemCount: jobs.length,
          itemBuilder: (context, index) {
            final job = jobs[index];
            return _JobCard(
              job: job,
              isUnassigned: false,
              onProcess: () => _processJob(context, job),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  void _processJob(BuildContext context, Map<String, dynamic> job) {
    // Navigate to OCR processing screen
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Processing job: ${job['id']}')));
  }
}

class _JobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final bool isUnassigned;
  final VoidCallback? onClaim;
  final VoidCallback? onProcess;

  const _JobCard({
    required this.job,
    required this.isUnassigned,
    this.onClaim,
    this.onProcess,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = job['status'] ?? 'pending';
    final type = job['type'] ?? 'Unknown';
    final createdAt = job['created_at'] ?? '';

    Color statusColor;
    IconData statusIcon;
    switch (status.toString().toLowerCase()) {
      case 'completed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'processing':
        statusColor = Colors.orange;
        statusIcon = Icons.sync;
        break;
      case 'error':
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.pending;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.1),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Text(
          '$type OCR Job',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${status.toString().toUpperCase()}'),
            if (createdAt.isNotEmpty)
              Text('Created: $createdAt', style: theme.textTheme.bodySmall),
          ],
        ),
        trailing: isUnassigned
            ? ElevatedButton.icon(
                onPressed: onClaim,
                icon: const Icon(Icons.add_task, size: 16),
                label: const Text('Claim'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
              )
            : OutlinedButton.icon(
                onPressed: onProcess,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Process'),
              ),
      ),
    );
  }
}
