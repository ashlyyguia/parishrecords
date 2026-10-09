import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/ocr_save_guard.dart';

/// What happened to the last Save on an OCR review screen.
class OcrSaveStatus {
  const OcrSaveStatus.waiting(this.rowCount)
      : outcome = OcrSaveOutcome.waitingForConnection,
        error = null;
  const OcrSaveStatus.failed(this.rowCount, this.error)
      : outcome = OcrSaveOutcome.failed;

  final OcrSaveOutcome outcome;
  final int rowCount;
  final Object? error;
}

/// Shown above the Save button when a save is waiting for the connection or
/// didn't go through. The reviewed rows are always kept.
class OcrSaveStatusBanner extends StatelessWidget {
  const OcrSaveStatusBanner({
    super.key,
    required this.status,
    required this.onRetry,
    this.retrying = false,
  });

  final OcrSaveStatus status;
  final VoidCallback onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final waiting = status.outcome == OcrSaveOutcome.waitingForConnection;
    final rows = status.rowCount == 1 ? '1 reviewed row' : '${status.rowCount} reviewed rows';
    final title = waiting
        ? 'Waiting for the internet connection…'
        : 'Not saved yet';
    final body = waiting
        ? 'Your $rows are kept on this device and will be saved automatically '
            'when the connection returns. Keep this page open, or tap Retry.'
        : 'Your $rows are kept on this device. Check your connection, then '
            'tap Retry.${_detail()}';
    final bg = waiting ? cs.tertiaryContainer : cs.errorContainer;
    final fg = waiting ? cs.onTertiaryContainer : cs.onErrorContainer;

    return Container(
      key: const ValueKey('ocr-save-status'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(waiting ? Icons.cloud_sync_outlined : Icons.cloud_off_outlined,
              color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(body, style: TextStyle(color: fg, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            key: const ValueKey('ocr-save-retry'),
            onPressed: retrying ? null : onRetry,
            icon: retrying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: TextButton.styleFrom(foregroundColor: fg),
          ),
        ],
      ),
    );
  }

  String _detail() {
    final e = status.error;
    if (e == null) return '';
    final text = e.toString().replaceFirst('Exception: ', '').trim();
    if (text.isEmpty) return '';
    final short = text.length > 140 ? '${text.substring(0, 140)}…' : text;
    return '\n($short)';
  }
}

/// Unsaved scans kept on this device, offered on the scanner's first step.
class OcrPendingSavesBanner extends StatelessWidget {
  const OcrPendingSavesBanner({
    super.key,
    required this.saves,
    required this.label,
    required this.onResume,
    required this.onDiscard,
  });

  final List<OcrPendingSave> saves;

  /// e.g. "baptismal" / "marriage".
  final String label;
  final void Function(OcrPendingSave save) onResume;
  final void Function(OcrPendingSave save) onDiscard;

  @override
  Widget build(BuildContext context) {
    if (saves.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('MMM d, h:mm a');
    return Card(
      key: const ValueKey('ocr-pending-saves'),
      color: cs.tertiaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restore_page_outlined, color: cs.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    saves.length == 1
                        ? 'You have an unsaved $label scan'
                        : 'You have ${saves.length} unsaved $label scans',
                    style: TextStyle(
                      color: cs.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'The save was interrupted before the server confirmed it. '
              'Resume to check the rows and save again — rows that already '
              'reached the server will not be duplicated.',
              style: TextStyle(color: cs.onTertiaryContainer, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            for (final s in saves)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      '${s.rowCount} row${s.rowCount == 1 ? '' : 's'} · '
                      '${fmt.format(s.savedAt.toLocal())}',
                      style: TextStyle(color: cs.onTertiaryContainer),
                    ),
                    FilledButton.tonalIcon(
                      key: ValueKey('ocr-resume-${s.scanId}'),
                      onPressed: () => onResume(s),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Resume'),
                    ),
                    TextButton(
                      key: ValueKey('ocr-discard-${s.scanId}'),
                      onPressed: () => onDiscard(s),
                      child: const Text('Discard'),
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
