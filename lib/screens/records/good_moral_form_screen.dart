import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/record.dart';
import '../../providers/records_provider.dart';
import '../../widgets/record_form_theme.dart';

/// Entry form for a Certificate of Good Moral Character.
///
/// The fields follow the parish's printed form, blank by blank:
///
///   That Mr./Ms./Mx. [full name]
///   a resident of [residence]
///   is a person of [character]
///   and has been known to the Parish Administration and clergy as having
///   [standing]
///   and is therefore a fit person for [purpose].
///
/// Everything the certificate prints is required; the date issued and the
/// signing priest default to today and the parish priest. Saved as a
/// `good_moral_records` record; its notes hold the fields under `goodMoral`.
class GoodMoralFormScreen extends ConsumerStatefulWidget {
  final ParishRecord? existing;
  final bool fromAdmin;
  final bool fromStaff;

  const GoodMoralFormScreen({
    super.key,
    this.existing,
    this.fromAdmin = false,
    this.fromStaff = false,
  });

  /// Titles the form offers ("Mr./Ms./Mx."); the chosen one is circled on the
  /// printed certificate.
  static const titles = ['Mr.', 'Ms.', 'Mx.'];

  static const defaultPersonOf = 'good moral character';
  // Short enough to print at full size on its blank.
  static const defaultKnownAs = 'good standing in the parish';
  static const defaultPriest = 'FR. DANILO B. RUDINAS';

  /// Common purposes, offered as quick picks; any text may be typed.
  static const purposes = [
    'employment',
    'scholarship',
    'school admission',
    'marriage',
    'local or overseas travel',
    'any legal purpose',
  ];

  @override
  ConsumerState<GoodMoralFormScreen> createState() =>
      _GoodMoralFormScreenState();
}

class _GoodMoralFormScreenState extends ConsumerState<GoodMoralFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  late String _recordId;

  String _title = GoodMoralFormScreen.titles.first;
  final _nameCtrl = TextEditingController();
  final _residentOfCtrl = TextEditingController();
  final _personOfCtrl = TextEditingController(
    text: GoodMoralFormScreen.defaultPersonOf,
  );
  final _knownAsCtrl = TextEditingController(
    text: GoodMoralFormScreen.defaultKnownAs,
  );
  final _purposeCtrl = TextEditingController();
  DateTime _dateIssued = DateTime.now();
  final _priestCtrl = TextEditingController(
    text: GoodMoralFormScreen.defaultPriest,
  );
  final _remarksCtrl = TextEditingController();
  final _staffNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _recordId =
        'HRP-GM-${DateFormat('yyyyMMdd').format(DateTime.now())}-${const Uuid().v4()}';
    final existing = widget.existing;
    if (existing == null) return;
    _nameCtrl.text = existing.name;
    _dateIssued = existing.date;
    try {
      final decoded = json.decode(existing.notes ?? '');
      if (decoded is! Map<String, dynamic>) return;
      final gm = decoded['goodMoral'];
      if (gm is Map) {
        String s(String k) => (gm[k] ?? '').toString();
        if (GoodMoralFormScreen.titles.contains(s('title'))) {
          _title = s('title');
        }
        if (s('fullName').isNotEmpty) _nameCtrl.text = s('fullName');
        _residentOfCtrl.text = s('residentOf');
        _personOfCtrl.text = s('personOf');
        _knownAsCtrl.text = s('knownAs');
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
      _personOfCtrl,
      _knownAsCtrl,
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

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete the required fields')),
      );
      return;
    }
    final name = _nameCtrl.text.trim();
    final nowIso = DateTime.now().toIso8601String();
    final details = {
      'goodMoral': {
        'title': _title,
        'fullName': name,
        'residentOf': _residentOfCtrl.text.trim(),
        'personOf': _personOfCtrl.text.trim(),
        'knownAs': _knownAsCtrl.text.trim(),
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
          RecordType.goodMoral,
          name,
          _dateIssued,
          notes: json.encode(details),
        );
      } else {
        await notifier.updateRecord(
          widget.existing!.id,
          type: RecordType.goodMoral,
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
                ? 'Good Moral certificate record saved'
                : 'Good Moral certificate record updated',
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
        title: const Text('Good Moral Certificate'),
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
                              for (final t in GoodMoralFormScreen.titles)
                                DropdownMenuItem(value: t, child: Text(t)),
                            ],
                            onChanged: (v) => setState(
                              () => _title =
                                  v ?? GoodMoralFormScreen.titles.first,
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
                    section('Character'),
                    TextFormField(
                      controller: _personOfCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Is a person of *',
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _knownAsCtrl,
                      minLines: 1,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText:
                            'Known to the Parish Administration and clergy as having *',
                      ),
                      validator: _required,
                    ),
                    section('Purpose'),
                    TextFormField(
                      controller: _purposeCtrl,
                      minLines: 1,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Is therefore a fit person for *',
                        hintText: 'e.g. employment',
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in GoodMoralFormScreen.purposes)
                          ActionChip(
                            label: Text(p),
                            onPressed: () =>
                                setState(() => _purposeCtrl.text = p),
                          ),
                      ],
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
