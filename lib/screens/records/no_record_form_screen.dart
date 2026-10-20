import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/record.dart';
import '../../providers/records_provider.dart';
import '../../widgets/record_form_theme.dart';

/// Entry form for a Certificate of No Record.
///
/// The printed form states that, after examining the parish registers, no
/// entry was found for:
///
///   Mr./Ms./Mx. [full name]
///   a resident of [residence]
///
/// so those two blanks (with the title circled) are what it needs, plus the
/// date issued and the signing priest, which default to today and the parish
/// priest. What the certificate was requested for is kept for the office but
/// not printed. Saved as a `no_record_records` record; its notes hold the
/// fields under `noRecord`.
class NoRecordFormScreen extends ConsumerStatefulWidget {
  final ParishRecord? existing;
  final bool fromAdmin;
  final bool fromStaff;

  const NoRecordFormScreen({
    super.key,
    this.existing,
    this.fromAdmin = false,
    this.fromStaff = false,
  });

  /// Titles the form offers ("Mr./Ms./Mx."); the chosen one is circled on the
  /// printed certificate.
  static const titles = ['Mr.', 'Ms.', 'Mx.'];

  static const defaultPriest = 'FR. DANILO B. RUDINAS';

  @override
  ConsumerState<NoRecordFormScreen> createState() => _NoRecordFormScreenState();
}

class _NoRecordFormScreenState extends ConsumerState<NoRecordFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  late String _recordId;

  String _title = NoRecordFormScreen.titles.first;
  final _nameCtrl = TextEditingController();
  final _residentOfCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  DateTime _dateIssued = DateTime.now();
  final _priestCtrl = TextEditingController(
    text: NoRecordFormScreen.defaultPriest,
  );
  final _remarksCtrl = TextEditingController();
  final _staffNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _recordId =
        'HRP-NR-${DateFormat('yyyyMMdd').format(DateTime.now())}-${const Uuid().v4()}';
    final existing = widget.existing;
    if (existing == null) return;
    _nameCtrl.text = existing.name;
    _dateIssued = existing.date;
    try {
      final decoded = json.decode(existing.notes ?? '');
      if (decoded is! Map<String, dynamic>) return;
      final gm = decoded['noRecord'];
      if (gm is Map) {
        String s(String k) => (gm[k] ?? '').toString();
        if (NoRecordFormScreen.titles.contains(s('title'))) {
          _title = s('title');
        }
        if (s('fullName').isNotEmpty) _nameCtrl.text = s('fullName');
        _residentOfCtrl.text = s('residentOf');
        _purposeCtrl.text = s('purpose');
        if (s('parishPriest').isNotEmpty) _priestCtrl.text = s('parishPriest');
        final issued = DateTime.tryParse(s('dateIssued'));
        if (issued != null) _dateIssued = issued;
      }
      _remarksCtrl.text = (decoded['remarks'] ?? '').toString();
      final meta = decoded['meta'];
      if (meta is Map) {
        _staffNameCtrl.text = (meta['staffName'] ?? '').toString();
        final id = meta['recordId']?.toString();
        if (id != null && id.isNotEmpty) _recordId = id;
      }
    } catch (_) {
      // Notes that are not this form's JSON: keep the defaults.
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _residentOfCtrl,
      _purposeCtrl,
      _priestCtrl,
      _remarksCtrl,
      _staffNameCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateIssued,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dateIssued = picked);
  }

  /// Sacramental records already in the system under this name. A
  /// certificate saying none exists should not be issued over one, so they
  /// are shown before saving.
  List<ParishRecord> _matchingRecords(String name) {
    final words = name
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9ñ]+'))
        .where((w) => w.length >= 2)
        .toList();
    if (words.isEmpty) return const [];
    return ref.read(recordsProvider).where((r) {
      if (r.type == RecordType.goodMoral || r.type == RecordType.noRecord) {
        return false;
      }
      final hay = r.name.toLowerCase();
      return words.every(hay.contains);
    }).toList();
  }

  Future<bool> _confirmNoMatches(String name) async {
    final matches = _matchingRecords(name);
    if (matches.isEmpty) return true;
    final df = DateFormat.yMMMMd();
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Matching records found'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The parish records already have ${matches.length} '
                    'entr${matches.length == 1 ? 'y' : 'ies'} under this name. '
                    'Check that none is this person before issuing a '
                    'Certificate of No Record.',
                  ),
                  const SizedBox(height: 8),
                  for (final r in matches.take(6))
                    Text('• ${r.name} — ${r.type.label}, ${df.format(r.date)}'),
                  if (matches.length > 6)
                    Text('…and ${matches.length - 6} more'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Not the same person — save'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete the required fields')),
      );
      return;
    }
    final name = _nameCtrl.text.trim();
    if (widget.existing == null && !await _confirmNoMatches(name)) return;
    final nowIso = DateTime.now().toIso8601String();
    final details = {
      'noRecord': {
        'title': _title,
        'fullName': name,
        'residentOf': _residentOfCtrl.text.trim(),
        'purpose': _purposeCtrl.text.trim(),
        'dateIssued': DateFormat('yyyy-MM-dd').format(_dateIssued),
        'parishPriest': _priestCtrl.text.trim(),
      },
      'remarks': _remarksCtrl.text.trim(),
      'meta': {
        'createdAt': nowIso,
        'dateEncoded': nowIso,
        'recordId': _recordId,
        'staffName': _staffNameCtrl.text.trim(),
      },
    };

    setState(() => _saving = true);
    try {
      final notifier = ref.read(recordsProvider.notifier);
      if (widget.existing == null) {
        await notifier.addRecord(
          RecordType.noRecord,
          name,
          _dateIssued,
          notes: json.encode(details),
        );
      } else {
        await notifier.updateRecord(
          widget.existing!.id,
          type: RecordType.noRecord,
          name: name,
          date: _dateIssued,
          notes: json.encode(details),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.existing == null
                ? 'Certificate of No Record saved'
                : 'Certificate of No Record updated',
          ),
        ),
      );
      // Back to the Records list of whichever area the form was opened from.
      final path = GoRouterState.of(context).uri.path;
      context.go(
        widget.fromAdmin || path.startsWith('/admin')
            ? '/admin/records'
            : widget.fromStaff || path.startsWith('/staff')
            ? '/staff/records'
            : '/records',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Certificate of No Record'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
      body: RecordFormTheme(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Fields marked * are printed on the certificate.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    section('Person'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: DropdownButtonFormField<String>(
                            initialValue: _title,
                            decoration: const InputDecoration(
                              labelText: 'Title *',
                            ),
                            items: [
                              for (final t in NoRecordFormScreen.titles)
                                DropdownMenuItem(value: t, child: Text(t)),
                            ],
                            onChanged: (v) => setState(
                              () =>
                                  _title = v ?? NoRecordFormScreen.titles.first,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _nameCtrl,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Full name *',
                              hintText: 'e.g. Juan P. Dela Cruz',
                            ),
                            validator: _required,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _residentOfCtrl,
                      decoration: const InputDecoration(
                        labelText: 'A resident of *',
                        hintText: 'e.g. Brgy. Lower Lamac, Oroquieta City',
                      ),
                      validator: _required,
                    ),
                    section('Issuance'),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date issued *',
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat.yMMMMd().format(_dateIssued),
                            ),
                          ),
                          TextButton(
                            onPressed: _pickDate,
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _priestCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Signing priest *',
                      ),
                      validator: _required,
                    ),
                    section('Office use (not printed)'),
                    TextFormField(
                      controller: _purposeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Requested for',
                        hintText:
                            'e.g. marriage preparation, late registration',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _remarksCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Remarks'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _staffNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Prepared by / staff name',
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
