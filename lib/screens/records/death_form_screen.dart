import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../models/record.dart';
import '../../providers/records_provider.dart';
import '../ocr/ocr_scan_screen.dart';

class DeathFormScreen extends ConsumerStatefulWidget {
  final ParishRecord? existing;
  final bool fromAdmin;
  final bool startWithOcr;

  const DeathFormScreen({
    super.key,
    this.existing,
    this.fromAdmin = false,
    this.startWithOcr = false,
  });

  @override
  ConsumerState<DeathFormScreen> createState() => _DeathFormScreenState();
}

class _DeathFormScreenState extends ConsumerState<DeathFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _recordId;

  // Registry (book/page/line)
  final _bookNoCtrl = TextEditingController();
  final _pageNoCtrl = TextEditingController();
  final _lineNoCtrl = TextEditingController();

  // Deceased
  final _nameCtrl = TextEditingController();
  String _gender = 'Male';
  final _ageCtrl = TextEditingController();
  DateTime? _dob; // optional
  DateTime? _dod;
  final _placeOfDeathCtrl = TextEditingController();
  final _causeOfDeathCtrl = TextEditingController();
  final _civilStatusCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // Family
  final _fatherCtrl = TextEditingController();
  final _motherCtrl = TextEditingController();
  final _spouseCtrl = TextEditingController();

  // Representative
  final _representativeNameCtrl = TextEditingController();
  final _representativeRelationCtrl = TextEditingController();

  // Burial
  DateTime? _burialDate;
  final _burialPlaceCtrl = TextEditingController();
  final _officiantCtrl = TextEditingController();

  // Remarks
  final _remarksCtrl = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  String? _attachmentPath;
  bool _attachPsaDeathCertificate = false;
  bool _attachRepresentativeId = false;
  String? _encoderSignaturePath;
  String? _priestSignaturePath;
  String? _ocrRawText;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final datePart = DateFormat('yyyyMMdd').format(now);
    _recordId = 'HRP-DEATH-$datePart-${const Uuid().v4()}';

    if (_burialPlaceCtrl.text.isEmpty) {
      _burialPlaceCtrl.text = 'Holy Rosary Parish – Oroquieta City';
    }

    // Prefill from existing record if editing
    final existing = widget.existing;
    if (existing != null) {
      try {
        final raw = existing.notes;
        if (raw != null && raw.isNotEmpty) {
          final decoded = json.decode(raw) as Map<String, dynamic>;

          final deceased = decoded['deceased'] as Map<String, dynamic>?;
          final family = decoded['family'] as Map<String, dynamic>?;
          final representative =
              decoded['representative'] as Map<String, dynamic>?;
          final burial = decoded['burial'] as Map<String, dynamic>?;
          final remarks = decoded['remarks'];
          final attachments = decoded['attachments'] as List<dynamic>?;
          final meta = decoded['meta'] as Map<String, dynamic>?;

          if (deceased != null) {
            _nameCtrl.text = (deceased['fullName'] ?? '').toString();
            _gender = (deceased['gender'] ?? _gender).toString();
            _ageCtrl.text = (deceased['age'] ?? '').toString();
            final dobRaw = deceased['dateOfBirth']?.toString();
            if (dobRaw != null && dobRaw.isNotEmpty) {
              _dob = DateTime.tryParse(dobRaw);
            }
            final dodRaw = deceased['dateOfDeath']?.toString();
            if (dodRaw != null && dodRaw.isNotEmpty) {
              _dod = DateTime.tryParse(dodRaw);
            }
            _placeOfDeathCtrl.text = (deceased['placeOfDeath'] ?? '')
                .toString();
            _causeOfDeathCtrl.text = (deceased['causeOfDeath'] ?? '')
                .toString();
            _civilStatusCtrl.text = (deceased['civilStatus'] ?? '').toString();
            _addressCtrl.text = (deceased['address'] ?? '').toString();
          }

          if (family != null) {
            _fatherCtrl.text = (family['father'] ?? '').toString();
            _motherCtrl.text = (family['mother'] ?? '').toString();
            _spouseCtrl.text = (family['spouse'] ?? '').toString();
          }

          if (representative != null) {
            _representativeNameCtrl.text = (representative['name'] ?? '')
                .toString();
            _representativeRelationCtrl.text =
                (representative['relationship'] ?? '').toString();
          }

          if (burial != null) {
            final burialDateRaw = burial['date']?.toString();
            if (burialDateRaw != null && burialDateRaw.isNotEmpty) {
              _burialDate = DateTime.tryParse(burialDateRaw);
            }
            _burialPlaceCtrl.text = (burial['place'] ?? _burialPlaceCtrl.text)
                .toString();
            _officiantCtrl.text = (burial['officiant'] ?? '').toString();
          }

          if (remarks != null) {
            _remarksCtrl.text = remarks.toString();
          }

          if (attachments != null && attachments.isNotEmpty) {
            final first = attachments.first as Map<String, dynamic>?;
            _attachmentPath = first?['path']?.toString();
          }

          if (meta != null) {
            final ocrText = meta['ocrRawText']?.toString();
            if (ocrText != null && ocrText.isNotEmpty) {
              _ocrRawText = ocrText;
            }

            final bookNo = meta['bookNo']?.toString();
            if (bookNo != null && bookNo.isNotEmpty) {
              _bookNoCtrl.text = bookNo;
            }
            final pageNo = meta['pageNo']?.toString();
            if (pageNo != null && pageNo.isNotEmpty) {
              _pageNoCtrl.text = pageNo;
            }
            final lineNo = meta['lineNo']?.toString();
            if (lineNo != null && lineNo.isNotEmpty) {
              _lineNoCtrl.text = lineNo;
            }
          }
        }
      } catch (_) {
        // ignore parse errors and fall back to defaults
      }
    }

    if (widget.existing == null && widget.startWithOcr) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scanOcr();
      });
    }
  }

  Future<void> _scanOcr() async {
    try {
      final result = await Navigator.of(
        context,
      ).push<String>(MaterialPageRoute(builder: (_) => const OcrScanScreen()));
      if (!mounted || result == null) {
        return;
      }
      final trimmed = result.trim();
      if (trimmed.isEmpty) return;

      setState(() {
        _ocrRawText = trimmed;
        if (_nameCtrl.text.trim().isEmpty) {
          final firstLine = trimmed
              .split('\n')
              .map((e) => e.trim())
              .firstWhere((e) => e.isNotEmpty, orElse: () => '');
          if (firstLine.isNotEmpty) {
            _nameCtrl.text = firstLine;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to scan text from camera')),
      );
    }
  }

  @override
  void dispose() {
    _bookNoCtrl.dispose();
    _pageNoCtrl.dispose();
    _lineNoCtrl.dispose();
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _placeOfDeathCtrl.dispose();
    _causeOfDeathCtrl.dispose();
    _civilStatusCtrl.dispose();
    _addressCtrl.dispose();
    _fatherCtrl.dispose();
    _motherCtrl.dispose();
    _spouseCtrl.dispose();
    _representativeNameCtrl.dispose();
    _representativeRelationCtrl.dispose();
    _burialPlaceCtrl.dispose();
    _officiantCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(
    BuildContext ctx,
    void Function(DateTime) set, {
    DateTime? initial,
  }) async {
    final picked = await showDatePicker(
      context: ctx,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(1800),
      lastDate: DateTime(2100),
    );
    if (picked != null) set(picked);
  }

  Future<void> _pickAttachment() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (file != null) setState(() => _attachmentPath = file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Attachment error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _pickEncoderSignature() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (file != null) {
        setState(() {
          _encoderSignaturePath = file.path;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signature error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _pickPriestSignature() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (file != null) {
        setState(() {
          _priestSignaturePath = file.path;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signature error: ${e.toString()}')),
        );
      }
    }
  }

  Future<List<ParishRecord>> _findPossibleDuplicates() async {
    final records = ref.read(recordsProvider);
    final name = _nameCtrl.text.trim().toLowerCase();
    final dod = _dod;
    final bookNo = _bookNoCtrl.text.trim();
    final pageNo = _pageNoCtrl.text.trim();
    final lineNo = _lineNoCtrl.text.trim();

    if (name.isEmpty) return const [];

    bool matchesRegistry(ParishRecord r) {
      if (r.notes == null || r.notes!.isEmpty) return false;
      try {
        final decoded = json.decode(r.notes!);
        if (decoded is! Map<String, dynamic>) return false;
        final meta = decoded['meta'] as Map<String, dynamic>?;
        if (meta == null) return false;
        bool eq(String a, dynamic b) =>
            a.isNotEmpty && b != null && a == b.toString().trim();
        if (eq(bookNo, meta['bookNo']) &&
            eq(pageNo, meta['pageNo']) &&
            eq(lineNo, meta['lineNo'])) {
          return true;
        }
      } catch (_) {
        return false;
      }
      return false;
    }

    bool closeDate(DateTime a, DateTime b) {
      final diff = a.difference(b).inDays.abs();
      return diff <= 7;
    }

    return records.where((r) {
      if (widget.existing != null && r.id == widget.existing!.id) {
        return false;
      }
      if (r.type != RecordType.funeral) {
        return false;
      }
      final rName = r.name.trim().toLowerCase();
      if (rName != name) {
        return false;
      }
      if (bookNo.isNotEmpty || pageNo.isNotEmpty || lineNo.isNotEmpty) {
        if (matchesRegistry(r)) {
          return true;
        }
      }
      if (dod != null && closeDate(dod, r.date)) {
        return true;
      }
      return false;
    }).toList();
  }

  Future<bool> _confirmDuplicates(List<ParishRecord> dups) async {
    if (dups.isEmpty) return true;
    final df = DateFormat.yMMMMd();
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Possible duplicate death/burial records'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Records with the same name and similar date of death or registry info already exist. Review them before saving to avoid duplicates.',
                    ),
                    const SizedBox(height: 12),
                    ...dups.map(
                      (r) => ListTile(
                        dense: true,
                        title: Text(r.name),
                        subtitle: Text(df.format(r.date)),
                        trailing: IconButton(
                          icon: const Icon(Icons.open_in_new, size: 18),
                          onPressed: () {
                            Navigator.of(ctx).pop(false);
                            context.push('/records/${r.id}');
                          },
                        ),
                      ),
                    ),
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
                  child: const Text('Proceed anyway'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete required fields')),
      );
      return;
    }
    final name = _nameCtrl.text.trim();
    final d = _dod ?? DateTime.now();

    // Duplicate check
    final duplicates = await _findPossibleDuplicates();
    final proceed = await _confirmDuplicates(duplicates);
    if (!proceed) {
      return;
    }

    final dfIso = DateFormat('yyyy-MM-dd');

    final nowIso = DateTime.now().toIso8601String();

    final details = {
      'deceased': {
        'fullName': name,
        'gender': _gender,
        'age': _ageCtrl.text.trim(),
        'dateOfBirth': _dob == null ? null : dfIso.format(_dob!),
        'dateOfDeath': dfIso.format(d),
        'placeOfDeath': _placeOfDeathCtrl.text.trim(),
        'causeOfDeath': _causeOfDeathCtrl.text.trim(),
        'civilStatus': _civilStatusCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
      },
      'family': {
        'father': _fatherCtrl.text.trim(),
        'mother': _motherCtrl.text.trim(),
        'spouse': _spouseCtrl.text.trim(),
      },
      'representative': {
        'name': _representativeNameCtrl.text.trim(),
        'relationship': _representativeRelationCtrl.text.trim(),
      },
      'burial': {
        'date': _burialDate == null ? null : dfIso.format(_burialDate!),
        'place': _burialPlaceCtrl.text.trim(),
        'officiant': _officiantCtrl.text.trim(),
      },
      'remarks': _remarksCtrl.text.trim(),
      'attachments': _attachmentPath == null
          ? []
          : [
              {'type': 'image', 'path': _attachmentPath},
            ],
      'meta': {
        'createdAt': nowIso,
        'dateEncoded': nowIso,
        'recordId': _recordId,
        'bookNo': _bookNoCtrl.text.trim(),
        'pageNo': _pageNoCtrl.text.trim(),
        'lineNo': _lineNoCtrl.text.trim(),
        'attachmentsChecklist': {
          'psaDeathCertificate': _attachPsaDeathCertificate,
          'representativeId': _attachRepresentativeId,
        },
        'encoderSignaturePath': _encoderSignaturePath,
        'priestSignaturePath': _priestSignaturePath,
        'ocrRawText': _ocrRawText,
      },
    };

    try {
      final notifier = ref.read(recordsProvider.notifier);
      if (widget.existing == null) {
        await notifier.addRecord(
          RecordType.funeral,
          name,
          d,
          imagePath: _attachmentPath,
          notes: json.encode(details),
        );
      } else {
        await notifier.updateRecord(
          widget.existing!.id,
          type: RecordType.funeral,
          name: name,
          date: d,
          imagePath: _attachmentPath,
          notes: json.encode(details),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existing == null
                  ? 'Death/Burial record saved'
                  : 'Death/Burial record updated',
            ),
          ),
        );
        final target = widget.fromAdmin ? '/admin/records' : '/records';
        context.go(target);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: ${e.toString()}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.yMMMMd();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Death / Burial Record Entry'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _bookNoCtrl,
                      decoration: const InputDecoration(labelText: 'Book No'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _pageNoCtrl,
                      decoration: const InputDecoration(labelText: 'Page No'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _lineNoCtrl,
                      decoration: const InputDecoration(labelText: 'Line No'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Deceased Information'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full name of deceased',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                ],
                onChanged: (v) => setState(() => _gender = v ?? 'Male'),
                decoration: const InputDecoration(labelText: 'Gender'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _ageCtrl,
                decoration: const InputDecoration(labelText: 'Age'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Date of birth: ${_dob == null ? 'Unknown' : df.format(_dob!)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () => _pickDate(
                      context,
                      (d) => setState(() => _dob = d),
                      initial: _dob ?? DateTime.now(),
                    ),
                    child: const Text('Pick date'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Date of death: ${_dod == null ? 'Not set' : df.format(_dod!)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () => _pickDate(
                      context,
                      (d) => setState(() => _dod = d),
                      initial: _dod ?? DateTime.now(),
                    ),
                    child: const Text('Pick date'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _placeOfDeathCtrl,
                decoration: const InputDecoration(labelText: 'Place of death'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _causeOfDeathCtrl,
                decoration: const InputDecoration(labelText: 'Cause of death'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _civilStatusCtrl,
                decoration: const InputDecoration(labelText: 'Civil status'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address / residence',
                ),
              ),

              const SizedBox(height: 16),
              const Text('Family Information'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _fatherCtrl,
                decoration: const InputDecoration(
                  labelText: "Father's name (optional)",
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _motherCtrl,
                decoration: const InputDecoration(
                  labelText: "Mother's name (optional)",
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _spouseCtrl,
                decoration: const InputDecoration(
                  labelText: "Spouse's name (if married)",
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _representativeNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Family representative name',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _representativeRelationCtrl,
                decoration: const InputDecoration(
                  labelText: 'Relationship to deceased',
                ),
              ),

              const SizedBox(height: 16),
              const Text('Burial Details'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Date of burial: ${_burialDate == null ? 'Not set' : df.format(_burialDate!)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () => _pickDate(
                      context,
                      (d) => setState(() => _burialDate = d),
                      initial: _burialDate ?? DateTime.now(),
                    ),
                    child: const Text('Pick date'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _burialPlaceCtrl,
                decoration: const InputDecoration(labelText: 'Place of burial'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _officiantCtrl,
                decoration: const InputDecoration(
                  labelText: 'Officiating priest',
                ),
              ),

              if (widget.existing != null && !widget.fromAdmin) ...[
                const SizedBox(height: 16),
                const Text('Remarks'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _remarksCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notes / remarks',
                  ),
                ),

                const SizedBox(height: 12),
                Text(
                  _ocrRawText == null || _ocrRawText!.isEmpty
                      ? 'No OCR text captured'
                      : 'OCR text captured (${_ocrRawText!.length} chars)',
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _scanOcr,
                    icon: const Icon(Icons.document_scanner),
                    label: const Text('Scan from certificate'),
                  ),
                ),

                const SizedBox(height: 16),
                const Text('Uploads'),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _attachPsaDeathCertificate,
                  onChanged: (v) =>
                      setState(() => _attachPsaDeathCertificate = v ?? false),
                  title: const Text('PSA Death Certificate'),
                ),
                CheckboxListTile(
                  value: _attachRepresentativeId,
                  onChanged: (v) =>
                      setState(() => _attachRepresentativeId = v ?? false),
                  title: const Text('ID of representative'),
                ),

                const SizedBox(height: 16),
                const Text('Signatures'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _encoderSignaturePath == null
                            ? 'Encoder signature: none'
                            : 'Encoder signature: selected',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _pickEncoderSignature,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Encoder'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _priestSignaturePath == null
                            ? 'Priest signature: none'
                            : 'Priest signature: selected',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _pickPriestSignature,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Priest'),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Text('Scanned Certificate (optional)'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _attachmentPath == null
                            ? 'No file selected'
                            : _attachmentPath!,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickAttachment,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Attach'),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
