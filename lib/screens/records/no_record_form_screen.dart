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

/// Entry form for a Certificate of No Record, printed as a typed
/// "CERTIFICATION" letter (see [LetterCertificate.noRecord]):
///
///   This is to certify that the [Baptismal] record of [FULL NAME],
///   [daughter/son] of [father] and [mother], and was supposed to have been
///   [baptized] in this parish, could not be found in the Records of
///   [Baptism].
///   This certification is issued upon the request of the above-mentioned
///   name for [purpose].
///   Given and sealed this [date] …            [signing priest, position]
///
/// The register searched follows the certificate the client requested
/// (baptism, marriage, confirmation or death). Saved as a `no_record_records`
/// record; its notes hold the fields under `noRecord`.
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

  static const defaultPurpose = 'any legal purposes';

  @override
  ConsumerState<NoRecordFormScreen> createState() => _NoRecordFormScreenState();
}

class _NoRecordFormScreenState extends ConsumerState<NoRecordFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  late String _recordId;

  NoRecordRegister _register = NoRecordRegister.baptism;
  final _nameCtrl = TextEditingController();
  String? _sex;
  final _fatherCtrl = TextEditingController();
  final _motherCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController(
    text: NoRecordFormScreen.defaultPurpose,
  );
  DateTime _dateIssued = DateTime.now();
  final _priestCtrl = TextEditingController(
    text: kCertificateSignatories[1].name,
  );
  final _positionCtrl = TextEditingController(
    text: kCertificateSignatories[1].position,
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
      final nr = decoded['noRecord'];
      if (nr is Map) {
        String s(String k) => (nr[k] ?? '').toString().trim();
        _register = NoRecordRegisterText.fromId(s('register'));
        if (s('fullName').isNotEmpty) _nameCtrl.text = s('fullName');
        final sex = s('sex');
        _sex = sex == 'daughter' || sex == 'son' ? sex : null;
        _fatherCtrl.text = s('father');
        _motherCtrl.text = s('mother');
        if (s('purpose').isNotEmpty) _purposeCtrl.text = s('purpose');
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
        'register': _register.id,
        'fullName': name,
        'sex': _sex,
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
                      'Everything except the office-use fields is printed on '
                      'the certificate. Fields marked * are required.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    section('Record searched'),
                    DropdownButtonFormField<NoRecordRegister>(
                      initialValue: _register,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Register searched *',
                        helperText:
                            'The certificate the client requested, e.g. '
                            'Baptism → "the Baptismal record … could not be '
                            'found in the Records of Baptism"',
                        helperMaxLines: 2,
                      ),
                      items: [
                        for (final r in NoRecordRegister.values)
                          DropdownMenuItem(value: r, child: Text(r.label)),
                      ],
                      onChanged: (v) => setState(
                        () => _register = v ?? NoRecordRegister.baptism,
                      ),
                    ),
                    section('Person'),
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full name *',
                        hintText: 'e.g. Florida A. Nuqui',
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
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText:
                            'Issued upon the request of the above-mentioned name for *',
                        hintText: 'e.g. any legal purposes',
                      ),
                      validator: requiredField,
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
