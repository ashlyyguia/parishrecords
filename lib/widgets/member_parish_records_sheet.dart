import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/household.dart';
import '../providers/household_provider.dart';
import '../providers/user_providers.dart';
import '../services/household_repository.dart';

/// Lets a parishioner see, link and unlink the parish register records for
/// one household member. Opened from the church icon on My Profile.
class MemberParishRecordsSheet extends ConsumerStatefulWidget {
  const MemberParishRecordsSheet({
    super.key,
    required this.householdId,
    required this.memberId,
  });

  final String householdId;
  final String memberId;

  /// Shows the sheet. Returns true when any link changed.
  static Future<bool> show(
    BuildContext context, {
    required String householdId,
    required String memberId,
  }) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => MemberParishRecordsSheet(
        householdId: householdId,
        memberId: memberId,
      ),
    );
    return changed ?? false;
  }

  @override
  ConsumerState<MemberParishRecordsSheet> createState() =>
      _MemberParishRecordsSheetState();
}

class _MemberParishRecordsSheetState
    extends ConsumerState<MemberParishRecordsSheet> {
  static const _types = <String, String>{
    'baptism': 'Baptism',
    'confirmation': 'Confirmation',
    'marriage': 'Marriage',
    'death': 'Death / Funeral',
  };

  HouseholdMember? _member;
  List<SacramentRecordCandidate> _candidates = const [];
  bool _loading = true;
  String? _error;
  String? _busyKey;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(householdRepositoryProvider);
      final member = await repo.getMember(widget.memberId);
      if (member == null) throw Exception('Member not found');
      final candidates = await repo.findRecordCandidates(member);
      if (!mounted) return;
      setState(() {
        _member = member;
        _candidates = candidates;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load parish records: $e';
        _loading = false;
      });
    }
  }

  String? _linkedId(String type) {
    final m = _member;
    if (m == null) return null;
    final id = switch (type) {
      'baptism' => m.baptismRecordId,
      'confirmation' => m.confirmationRecordId,
      'marriage' => m.marriageRecordId,
      'death' => m.deathRecordId,
      _ => null,
    };
    return (id == null || id.trim().isEmpty) ? null : id;
  }

  void _afterChange() {
    _changed = true;
    ref.invalidate(hasLinkedSacramentsProvider);
    ref.invalidate(householdLinkedSacramentStubsProvider);
  }

  Future<void> _link(SacramentRecordCandidate c) async {
    setState(() => _busyKey = '${c.type}:${c.recordId}');
    try {
      await ref
          .read(householdRepositoryProvider)
          .linkRecordCandidate(memberId: widget.memberId, record: c);
      _afterChange();
      await _load();
    } catch (e) {
      _snack('Could not link the record: $e');
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _unlink(String type) async {
    setState(() => _busyKey = 'unlink:$type');
    try {
      await ref
          .read(householdRepositoryProvider)
          .unlinkSacramentRecord(memberId: widget.memberId, type: type);
      _afterChange();
      await _load();
    } catch (e) {
      _snack('Could not unlink the record: $e');
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(DateTime? d) => d == null ? '' : DateFormat.yMMMd().format(d);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _member?.fullName ?? 'Member';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Parish records', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Link $name to their entries in the parish register. '
              'Linked records let the office issue certificates faster.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Column(
                children: [
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  TextButton(onPressed: _load, child: const Text('Try again')),
                ],
              )
            else
              ..._types.entries.map((e) => _typeSection(e.key, e.value)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('scan-to-link'),
              onPressed: () {
                Navigator.of(context).pop(_changed);
                context.go(
                  '/user/households/${widget.householdId}/members/${widget.memberId}/ocr-link',
                );
              },
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan a certificate to find the record'),
            ),
            const SizedBox(height: 8),
            Text(
              "Can't find the record? You can still request a certificate and "
              'type the details; the parish office will look it up.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeSection(String type, String label) {
    final theme = Theme.of(context);
    final linkedId = _linkedId(type);
    final options = _candidates.where((c) => c.type == type).toList();
    final linkedName = options
        .where((c) => c.recordId == linkedId)
        .map((c) => c.name)
        .firstOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  linkedId != null ? Icons.verified_outlined : Icons.link_off,
                  size: 20,
                  color: linkedId != null ? Colors.green : theme.disabledColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label, style: theme.textTheme.titleSmall),
                ),
                if (linkedId != null)
                  TextButton(
                    onPressed: _busyKey != null ? null : () => _unlink(type),
                    child: _busyKey == 'unlink:$type'
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Unlink'),
                  ),
              ],
            ),
            if (linkedId != null)
              Padding(
                padding: const EdgeInsets.only(left: 28, bottom: 4),
                child: Text(
                  'Linked${linkedName != null ? ' to $linkedName' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (options.where((c) => c.recordId != linkedId).isEmpty &&
                linkedId == null)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 4),
                child: Text(
                  'No matching record found in the register.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ...options.where((c) => c.recordId != linkedId).map((c) {
              final key = '${c.type}:${c.recordId}';
              final date = _fmt(c.recordDate);
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 28),
                title: Text(c.name),
                subtitle: Text([
                  if (date.isNotEmpty) date,
                  'Match ${c.score.clamp(0, 100)}%',
                ].join(' · ')),
                trailing: FilledButton.tonal(
                  onPressed: _busyKey != null ? null : () => _link(c),
                  child: _busyKey == key
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(linkedId != null ? 'Use this' : 'Link'),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
