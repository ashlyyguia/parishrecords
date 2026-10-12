import 'package:flutter/material.dart';

import '../services/requests_repository.dart';

/// Small amber badge for certificate requests submitted without a linked
/// register record. Renders nothing for verified requests.
class RequestRecordCheckBadge extends StatelessWidget {
  const RequestRecordCheckBadge({super.key, required this.request});

  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    if (!RequestsRepository.needsRecordCheck(request)) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const ValueKey('record-not-verified'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search, size: 14, color: Colors.amber.shade900),
          const SizedBox(width: 4),
          Text(
            'Record not yet verified',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Colors.amber.shade900,
            ),
          ),
        ],
      ),
    );
  }
}

/// The details a parishioner typed for an unverified request, for the office
/// to look up in the register.
class RequestDetailLines extends StatelessWidget {
  const RequestDetailLines({super.key, required this.request});

  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final lines = RequestsRepository.detailLines(request);
    final needsCheck = RequestsRepository.needsRecordCheck(request);
    if (lines.isEmpty && !needsCheck) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        if (needsCheck) ...[
          RequestRecordCheckBadge(request: request),
          const SizedBox(height: 6),
          Text(
            'No register record was linked. Find the entry using these details '
            'before approving.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        for (final e in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${e.key}: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: e.value),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// "Verified by Ana · Oct 12, 2026" plus the register record and notes, for
/// requests the parish office has checked against the register.
class RequestVerificationInfo extends StatelessWidget {
  const RequestVerificationInfo({
    super.key,
    required this.request,
    this.compact = false,
  });

  final Map<String, dynamic> request;

  /// Card view: one line only.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final v = request['verification'];
    if (v is! Map) return const SizedBox.shrink();
    final summary = RequestsRepository.verificationSummary(request);
    final record = (v['record_name'] ?? '').toString().trim();
    final note = (v['note'] ?? '').toString().trim();
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('request-verification-info'),
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_outlined, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              [
                summary,
                if (!compact && record.isNotEmpty) 'Register record: $record',
                if (!compact && note.isNotEmpty) 'Notes: $note',
              ].join('\n'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.blue.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
