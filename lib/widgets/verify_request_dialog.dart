import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/register_record_search.dart';
import '../services/requests_repository.dart';
import 'request_record_check.dart';

/// What staff confirmed when verifying a certificate request.
class VerifyRequestResult {
  const VerifyRequestResult({
    required this.record,
    required this.checks,
    this.note,
  });

  final RegisterRecordOption record;
  final Map<String, bool> checks;
  final String? note;
}

/// The checks staff must confirm before a request can be verified.
const List<(String, String)> kVerificationChecks = [
  ('record_found', 'The record is in the parish register'),
  ('name_date_match', 'Name and sacrament date match the record'),
  ('family_match', 'Parents (and sponsors, where relevant) match'),
  (
    'requester_ok',
    'The requester is the person on the certificate or an immediate family member',
  ),
];

/// Opens the verification panel for a pending request. Returns null when
/// cancelled.
Future<VerifyRequestResult?> showVerifyRequestDialog(
  BuildContext context, {
  required Map<String, dynamic> request,
  Future<RegisterRecordOption?> Function(String type, String id)? loadLinked,
  Future<List<RegisterRecordOption>> Function(String type, String query)?
      search,
}) {
  return showDialog<VerifyRequestResult>(
    context: context,
    builder: (_) => _VerifyRequestDialog(
      request: request,
      loadLinked: loadLinked,
      search: search,
    ),
  );
}

class _VerifyRequestDialog extends StatefulWidget {
  const _VerifyRequestDialog({
    required this.request,
    this.loadLinked,
    this.search,
  });

  final Map<String, dynamic> request;
  final Future<RegisterRecordOption?> Function(String type, String id)?
      loadLinked;
  final Future<List<RegisterRecordOption>> Function(String type, String query)?
      search;

  @override
  State<_VerifyRequestDialog> createState() => _VerifyRequestDialogState();
}

class _VerifyRequestDialogState extends State<_VerifyRequestDialog> {
  final _searchCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final Map<String, bool> _checks = {
    for (final c in kVerificationChecks) c.$1: false,
  };

  RegisterRecordOption? _selected;
  List<RegisterRecordOption> _results = const [];
  bool _loadingLinked = false;
  bool _searching = false;
  bool _searched = false;
  String? _searchError;

  String get _type =>
      (widget.request['request_type'] ?? 'baptism').toString();

  Future<RegisterRecordOption?> _loadLinked(String type, String id) =>
      widget.loadLinked != null
          ? widget.loadLinked!(type, id)
          : RegisterRecordSearch().byId(type, id);

  Future<List<RegisterRecordOption>> _search(String type, String q) =>
      widget.search != null
          ? widget.search!(type, q)
          : RegisterRecordSearch().search(type, q);

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = RequestsRepository.personOnCertificate(widget.request);
    final linkedId = (widget.request['record_id'] ?? '').toString();
    if (linkedId.isNotEmpty) {
      _loadingLinked = true;
      _loadLinked(_type, linkedId).then((r) {
        if (!mounted) return;
        setState(() {
          _selected = r;
          _loadingLinked = false;
        });
      }).catchError((Object _) {
        if (mounted) setState(() => _loadingLinked = false);
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await _search(_type, q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searched = true;
      });
    } catch (e) {
      if (mounted) setState(() => _searchError = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  bool get _canVerify =>
      _selected != null && _checks.values.every((v) => v);

  String _fmt(DateTime? d) => d == null ? '' : DateFormat.yMMMd().format(d);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final typeLabel = RequestsRepository.certificateTypeLabel(_type);
    final person = RequestsRepository.personOnCertificate(widget.request);
    final submittedBy = RequestsRepository.submittedByName(widget.request);

    return AlertDialog(
      icon: Icon(Icons.fact_check_outlined, color: cs.primary),
      title: const Text('Verify request'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$typeLabel certificate'
                '${person.isNotEmpty ? ' for $person' : ''}',
                style: theme.textTheme.titleMedium,
              ),
              if (submittedBy.isNotEmpty)
                Text('Requested by: $submittedBy',
                    style: theme.textTheme.bodySmall),
              RequestDetailLines(request: widget.request),
              const SizedBox(height: 16),
              Text('1. Parish register record',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (_loadingLinked)
                const LinearProgressIndicator()
              else if (_selected != null)
                _selectedCard(cs, theme)
              else
                _searchSection(cs, theme),
              const SizedBox(height: 16),
              Text('2. Checks',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              for (final c in kVerificationChecks)
                CheckboxListTile(
                  key: ValueKey('check-${c.$1}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _checks[c.$1],
                  onChanged: (v) => setState(() => _checks[c.$1] = v ?? false),
                  title: Text(c.$2),
                ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('verify-note'),
                controller: _noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'e.g. Book 12, Page 34, Line 5',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('verify-confirm'),
          onPressed: _canVerify
              ? () => Navigator.of(context).pop(
                    VerifyRequestResult(
                      record: _selected!,
                      checks: Map.of(_checks),
                      note: _noteCtrl.text.trim().isEmpty
                          ? null
                          : _noteCtrl.text.trim(),
                    ),
                  )
              : null,
          icon: const Icon(Icons.verified_outlined, size: 18),
          label: const Text('Mark as verified'),
        ),
      ],
    );
  }

  Widget _selectedCard(ColorScheme cs, ThemeData theme) {
    final r = _selected!;
    return Container(
      key: const ValueKey('verify-selected-record'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
        children: [
          const Icon(Icons.menu_book_outlined, color: Colors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.name.isEmpty ? '(no name)' : r.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  [
                    if (r.date != null) _fmt(r.date),
                    if (r.details.isNotEmpty) r.details,
                    'ID ${r.id}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _selected = null;
              _checks['record_found'] = false;
            }),
            child: const Text('Change'),
          ),
        ],
      ),
          if (r.fields.isNotEmpty) ...[
            const Divider(height: 16),
            RegisterRecordFieldsView(fields: r.fields),
          ],
        ],
      ),
    );
  }

  Widget _searchSection(ColorScheme cs, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'No register record is linked yet. Search the register and pick the '
          'matching entry.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('verify-search'),
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
                decoration: const InputDecoration(
                  labelText: 'Name in the register',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              key: const ValueKey('verify-search-button'),
              onPressed: _searching ? null : _runSearch,
              child: _searching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Search'),
            ),
          ],
        ),
        if (_searchError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_searchError!, style: TextStyle(color: cs.error)),
          ),
        if (_searched && _results.isEmpty && _searchError == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No matching record. If the record is not in the register, '
              'reject the request with that reason.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              '${_results.length} matching record${_results.length == 1 ? '' : 's'} '
              '— compare every detail with the request before choosing.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        for (final r in _results)
          Container(
            key: ValueKey('verify-result-${r.id}'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.menu_book_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.name.isEmpty ? '(no name)' : r.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            [
                              if (r.date != null) 'Recorded date: ${_fmt(r.date)}',
                              'ID ${r.id}',
                            ].join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => setState(() => _selected = r),
                      child: const Text('Use this'),
                    ),
                  ],
                ),
                if (r.fields.isNotEmpty) ...[
                  const Divider(height: 16),
                  RegisterRecordFieldsView(fields: r.fields),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'No other details are stored for this record.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Every stored detail of a register record, as aligned label/value rows.
class RegisterRecordFieldsView extends StatelessWidget {
  const RegisterRecordFieldsView({super.key, required this.fields});

  final List<MapEntry<String, String>> fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w500,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in fields)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 150, child: Text(f.key, style: labelStyle)),
                const SizedBox(width: 8),
                Expanded(child: Text(f.value, style: valueStyle)),
              ],
            ),
          ),
      ],
    );
  }
}
