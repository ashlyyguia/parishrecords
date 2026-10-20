import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../models/record.dart';
import '../../providers/records_provider.dart';
import '../../widgets/record_form_theme.dart';
import 'letter_certificate.dart';
import 'letter_form_parts.dart';

/// Entry form for a Certificate of Good Moral Character.
///
/// The certificate is a typed letter (see [LetterCertificate.goodMoral]):
///
///   This is to certify that [FULL NAME], a resident of [address], under the
///   jurisdiction of Holy Rosary Parish, and the [daughter/son] of [father]
///   and [mother], is known to be of Good Moral Character …
///   This certificate is issued upon the request of the interested party to
///   [purpose].
///   Given and sealed this [date] …            [signing priest, position]
///
/// Saved as a `good_moral_records` record; its notes hold the fields under
/// `goodMoral`.
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

  /// Common purposes, offered as quick picks; any text may be typed. Each
  /// completes "…upon the request of the interested party to".
  static const purposes = [
    'apply for employment',
    'apply for a scholarship',
    'enroll in school',
    'secure a passport',
    'use for any legal purpose',
  ];

  @override
  ConsumerState<GoodMoralFormScreen> createState() =>
      _GoodMoralFormScreenState();
}

class _GoodMoralFormScreenState extends ConsumerState<GoodMoralFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  late String _recordId;

  final _nameCtrl = TextEditingController();
  String? _sex;
  final _residentOfCtrl = TextEditingController();
  final _fatherCtrl = TextEditingController();
  final _motherCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  DateTime _dateIssued = DateTime.now();
  final _priestCtrl = TextEditingController(
    text: kCertificateSignatories[0].name,
  );
  final _positionCtrl = TextEditingController(
    text: kCertificateSignatories[0].position,
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
        String s(String k) => (gm[k] ?? '').toString().trim();
        if (s('fullName').isNotEmpty) _nameCtrl.text = s('fullName');
        final sex = s('sex');
        _sex = sex == 'daughter' || sex == 'son' ? sex : null;
        _residentOfCtrl.text = s('residentOf');
        _fatherCtrl.text = s('father');
        _motherCtrl.text = s('mother');
        // The old form's purpose completed "a fit person for …".
        _purposeCtrl.text = !gm.containsKey('sex') && s('purpose').isNotEmpty
            ? 'use for ${s('purpose')}'
            : s('purpose');
        if (s('parishPriest').isNotEmpty) _priestCtrl.text = s('parishPriest');
        _positionCtrl.text = LetterCertificate.positionFor(
          _priestCtrl.text,
          s('priestPosition'),
        );
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
      _fatherCtrl,
      _motherCtrl,
      _purposeCtrl,
      _priestCtrl,
      _positionCtrl,
      _remarksCtrl,
      _staffNameCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
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
        'fullName': name,
        'sex': _sex,
        'residentOf': _residentOfCtrl.text.trim(),
        'father': _fatherCtrl.text.trim(),
        'mother': _motherCtrl.text.trim(),
        'purpose': _purposeCtrl.text.trim(),
        'dateIssued': DateFormat('yyyy-MM-dd').format(_dateIssued),
        'parishPriest': _priestCtrl.text.trim(),
        'priestPosition': _positionCtrl.text.trim(),
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
                      'Everything except the office-use fields is printed on '
                      'the certificate. Fields marked * are required.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    section('Person'),
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full name *',
                        hintText: 'e.g. Julie An P. Alvarez',
                      ),
                      validator: requiredField,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _residentOfCtrl,
                      decoration: const InputDecoration(
                        labelText: 'A resident of *',
                        hintText:
                            'e.g. P-3 Upper Lancangan, Oroquieta City, '
                            'Misamis Occidental',
                      ),
                      validator: requiredField,
                    ),
                    const SizedBox(height: 8),
                    ChildOfField(
                      value: _sex,
                      onChanged: (v) => setState(() => _sex = v),
                    ),
                    const SizedBox(height: 8),
                    ParentsFields(father: _fatherCtrl, mother: _motherCtrl),
                    section('Purpose'),
                    TextFormField(
                      controller: _purposeCtrl,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText:
                            'Issued upon the request of the interested party to *',
                        hintText:
                            'e.g. avail youth Internship Program for Organic '
                            'Agriculture (YIPOA)',
                      ),
                      validator: requiredField,
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
                    DateIssuedField(
                      value: _dateIssued,
                      onChanged: (d) => setState(() => _dateIssued = d),
                    ),
                    const SizedBox(height: 8),
                    SignatoryFields(name: _priestCtrl, position: _positionCtrl),
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
