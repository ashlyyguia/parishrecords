import 'package:flutter/material.dart';

import '../services/requests_repository.dart';

/// Asks staff/admin why a certificate request is being rejected.
/// Returns the message, or null when cancelled.
Future<String?> showRejectRequestDialog(
  BuildContext context, {
  String typeLabel = '',
  String personName = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RejectRequestDialog(
      typeLabel: typeLabel,
      personName: personName,
    ),
  );
}

class _RejectRequestDialog extends StatefulWidget {
  const _RejectRequestDialog({
    required this.typeLabel,
    required this.personName,
  });

  final String typeLabel;
  final String personName;

  @override
  State<_RejectRequestDialog> createState() => _RejectRequestDialogState();
}

class _RejectRequestDialogState extends State<_RejectRequestDialog> {
  static const quickReasons = <String>[
    'Record not found in the parish register',
    'Details do not match our records',
    'Please visit the parish office to verify your identity',
    'Incomplete information',
  ];

  final _ctrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subject = [
      if (widget.typeLabel.isNotEmpty) '${widget.typeLabel} certificate',
      if (widget.personName.isNotEmpty) 'for ${widget.personName}',
    ].join(' ');

    return AlertDialog(
      icon: Icon(Icons.cancel_outlined, color: theme.colorScheme.error),
      title: const Text('Reject request'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject.isNotEmpty
                      ? 'Tell the parishioner why the $subject is being rejected. '
                          'They will see this message in their notification and in My Requests.'
                      : 'Tell the parishioner why this request is being rejected. '
                          'They will see this message in their notification and in My Requests.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in quickReasons)
                      ActionChip(
                        label: Text(r, style: const TextStyle(fontSize: 12)),
                        onPressed: () {
                          _ctrl.text = r;
                          _ctrl.selection = TextSelection.collapsed(
                            offset: r.length,
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('reject-note'),
                  controller: _ctrl,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Reason / message *',
                    hintText: 'e.g. We could not find the record. Please bring a copy of …',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => (v == null || v.trim().length < 3)
                      ? 'Please write a short reason'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('reject-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _submit,
          icon: const Icon(Icons.send_outlined, size: 18),
          label: const Text('Reject & notify'),
        ),
      ],
    );
  }
}

/// Shows the message staff left when changing a request's status.
class RequestStatusNote extends StatelessWidget {
  const RequestStatusNote({
    super.key,
    required this.request,
    this.title = 'Message from the parish office',
  });

  final Map<String, dynamic> request;
  final String title;

  @override
  Widget build(BuildContext context) {
    final note = RequestsRepository.statusNote(request);
    if (note.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final rejected =
        (request['status'] ?? '').toString().toLowerCase() == 'rejected';
    final accent = rejected ? cs.error : cs.primary;
    return Container(
      key: const ValueKey('request-status-note'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.chat_bubble_outline, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(note),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
