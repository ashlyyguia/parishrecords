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

class MarriageFormScreen extends ConsumerStatefulWidget {
  final ParishRecord? existing;
  final bool fromAdmin;
  final bool startWithOcr;

  const MarriageFormScreen({
    super.key,
    this.existing,
    this.fromAdmin = false,
    this.startWithOcr = false,
  });

  @override
  ConsumerState<MarriageFormScreen> createState() => _MarriageFormScreenState();
}

class _MarriageFormScreenState extends ConsumerState<MarriageFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _recordId;

  // Marriage details
  DateTime? _marriageDate;
  final _marriagePlaceCtrl = TextEditingController();
  final _officiantCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();

  // Registry (book/page/line)
  final _bookNoCtrl = TextEditingController();
  final _pageNoCtrl = TextEditingController();
  final _lineNoCtrl = TextEditingController();

  // Groom
  final _groomNameCtrl = TextEditingController();
  final _groomDobOrAgeCtrl = TextEditingController();
  final _groomCivilStatusCtrl = TextEditingController();
  final _groomReligionCtrl = TextEditingController();
  final _groomAddressCtrl = TextEditingController();
  final _groomFatherCtrl = TextEditingController();
  final _groomMotherCtrl = TextEditingController();

  // Bride
  final _brideNameCtrl = TextEditingController();
  final _brideDobOrAgeCtrl = TextEditingController();
  final _brideCivilStatusCtrl = TextEditingController();
  final _brideReligionCtrl = TextEditingController();
  final _brideAddressCtrl = TextEditingController();
  final _brideFatherCtrl = TextEditingController();
  final _brideMotherCtrl = TextEditingController();

  // Witnesses
  final _witness1Ctrl = TextEditingController();
  final _witness2Ctrl = TextEditingController();

  // Remarks
  final _remarksCtrl = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  String? _attachmentPath;
  bool _attachMarriageContract = false;
  bool _attachIds = false;
  String? _encoderSignaturePath;
  String? _priestSignaturePath;
  String? _ocrRawText;

  @override
  void dispose() {
    _marriagePlaceCtrl.dispose();
    _officiantCtrl.dispose();
    _licenseCtrl.dispose();
    _bookNoCtrl.dispose();
    _pageNoCtrl.dispose();
    _lineNoCtrl.dispose();
    _groomNameCtrl.dispose();
    _groomDobOrAgeCtrl.dispose();
    _groomCivilStatusCtrl.dispose();
    _groomReligionCtrl.dispose();
    _groomAddressCtrl.dispose();
    _groomFatherCtrl.dispose();
    _groomMotherCtrl.dispose();
    _brideNameCtrl.dispose();
    _brideDobOrAgeCtrl.dispose();
    _brideCivilStatusCtrl.dispose();
    _brideReligionCtrl.dispose();
    _brideAddressCtrl.dispose();
    _brideFatherCtrl.dispose();
    _brideMotherCtrl.dispose();
    _witness1Ctrl.dispose();
    _witness2Ctrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final datePart = DateFormat('yyyyMMdd').format(now);
    _recordId = 'HRP-MARR-$datePart-${const Uuid().v4()}';

    final existing = widget.existing;
    if (existing != null) {
      try {
        final raw = existing.notes;
        if (raw != null && raw.isNotEmpty) {
          final decoded = json.decode(raw) as Map<String, dynamic>;

          final marriage = decoded['marriage'] as Map<String, dynamic>?;
          final groom = decoded['groom'] as Map<String, dynamic>?;
          final bride = decoded['bride'] as Map<String, dynamic>?;
          final witnesses = decoded['witnesses'] as Map<String, dynamic>?;
          final remarks = decoded['remarks'];
          final attachments = decoded['attachments'] as List<dynamic>?;
          final meta = decoded['meta'] as Map<String, dynamic>?;

          if (marriage != null) {
            final dateRaw = marriage['date']?.toString();
            if (dateRaw != null && dateRaw.isNotEmpty) {
              _marriageDate = DateTime.tryParse(dateRaw);
            }
            _marriagePlaceCtrl.text = (marriage['place'] ?? '').toString();
            _officiantCtrl.text = (marriage['officiant'] ?? '').toString();
            _licenseCtrl.text = (marriage['licenseNumber'] ?? '').toString();
          }

          if (groom != null) {
            _groomNameCtrl.text = (groom['fullName'] ?? '').toString();
            _groomDobOrAgeCtrl.text = (groom['ageOrDob'] ?? '').toString();
            _groomCivilStatusCtrl.text = (groom['civilStatus'] ?? '')
                .toString();
            _groomReligionCtrl.text = (groom['religion'] ?? '').toString();
            _groomAddressCtrl.text = (groom['address'] ?? '').toString();
            _groomFatherCtrl.text = (groom['father'] ?? '').toString();
            _groomMotherCtrl.text = (groom['mother'] ?? '').toString();
          }

          if (bride != null) {
            _brideNameCtrl.text = (bride['fullName'] ?? '').toString();
            _brideDobOrAgeCtrl.text = (bride['ageOrDob'] ?? '').toString();
            _brideCivilStatusCtrl.text = (bride['civilStatus'] ?? '')
                .toString();
            _brideReligionCtrl.text = (bride['religion'] ?? '').toString();
            _brideAddressCtrl.text = (bride['address'] ?? '').toString();
            _brideFatherCtrl.text = (bride['father'] ?? '').toString();
            _brideMotherCtrl.text = (bride['mother'] ?? '').toString();
          }

          if (witnesses != null) {
            _witness1Ctrl.text = (witnesses['witness1'] ?? '').toString();
            _witness2Ctrl.text = (witnesses['witness2'] ?? '').toString();
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

    if (_marriagePlaceCtrl.text.isEmpty) {
      _marriagePlaceCtrl.text = 'Holy Rosary Parish – Oroquieta City';
    }

    if (widget.existing == null && widget.startWithOcr) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scanOcr();
      });
    }
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
        final lines = trimmed
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (_groomNameCtrl.text.trim().isEmpty && lines.isNotEmpty) {
          _groomNameCtrl.text = lines[0];
        }
        if (_brideNameCtrl.text.trim().isEmpty && lines.length > 1) {
          _brideNameCtrl.text = lines[1];
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to scan text from camera')),
      );
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
    final groom = _groomNameCtrl.text.trim().toLowerCase();
    final bride = _brideNameCtrl.text.trim().toLowerCase();
    final date = _marriageDate;
    final bookNo = _bookNoCtrl.text.trim();
    final pageNo = _pageNoCtrl.text.trim();
    final lineNo = _lineNoCtrl.text.trim();

    if (groom.isEmpty || bride.isEmpty) return const [];

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
      if (r.type != RecordType.marriage) {
        return false;
      }
      final parts = r.name.toLowerCase().split('&');
      if (parts.length != 2) return false;
      final rGroom = parts[0].trim();
      final rBride = parts[1].trim();
      if (rGroom != groom || rBride != bride) {
        return false;
      }
      if (bookNo.isNotEmpty || pageNo.isNotEmpty || lineNo.isNotEmpty) {
        if (matchesRegistry(r)) {
          return true;
        }
      }
      if (date != null && closeDate(date, r.date)) {
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
              title: const Text('Possible duplicate marriage records'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Marriage records with the same couple and similar date or registry info already exist. Review them before saving to avoid duplicates.',
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
    final name =
        '${_groomNameCtrl.text.trim()} & ${_brideNameCtrl.text.trim()}';
    final d = _marriageDate ?? DateTime.now();

    // Duplicate check
    final duplicates = await _findPossibleDuplicates();
    final proceed = await _confirmDuplicates(duplicates);
    if (!proceed) {
      return;
    }

    final dfIso = DateFormat('yyyy-MM-dd');

    final nowIso = DateTime.now().toIso8601String();

    final details = {
      'marriage': {
        'date': dfIso.format(d),
        'place': _marriagePlaceCtrl.text.trim(),
        'officiant': _officiantCtrl.text.trim(),
        'licenseNumber': _licenseCtrl.text.trim(),
      },
      'groom': {
        'fullName': _groomNameCtrl.text.trim(),
        'ageOrDob': _groomDobOrAgeCtrl.text.trim(),
        'civilStatus': _groomCivilStatusCtrl.text.trim(),
        'religion': _groomReligionCtrl.text.trim(),
        'address': _groomAddressCtrl.text.trim(),
        'father': _groomFatherCtrl.text.trim(),
        'mother': _groomMotherCtrl.text.trim(),
      },
      'bride': {
        'fullName': _brideNameCtrl.text.trim(),
        'ageOrDob': _brideDobOrAgeCtrl.text.trim(),
        'civilStatus': _brideCivilStatusCtrl.text.trim(),
        'religion': _brideReligionCtrl.text.trim(),
        'address': _brideAddressCtrl.text.trim(),
        'father': _brideFatherCtrl.text.trim(),
        'mother': _brideMotherCtrl.text.trim(),
      },
      'witnesses': {
        'witness1': _witness1Ctrl.text.trim(),
        'witness2': _witness2Ctrl.text.trim(),
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
          'marriageContract': _attachMarriageContract,
          'ids': _attachIds,
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
          RecordType.marriage,
          name,
          d,
          imagePath: _attachmentPath,
          notes: json.encode(details),
        );
      } else {
        await notifier.updateRecord(
          widget.existing!.id,
          type: RecordType.marriage,
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
                  ? 'Marriage record saved'
                  : 'Marriage record updated',
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
        title: const Text('Marriage Record Entry'),
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
              const Text('Marriage Details'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Date of marriage: ${_marriageDate == null ? 'Not set' : df.format(_marriageDate!)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () => _pickDate(
                      context,
                      (d) => setState(() => _marriageDate = d),
                      initial: _marriageDate ?? DateTime.now(),
                    ),
                    child: const Text('Pick date'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Place of marriage',
                ),
                controller: _marriagePlaceCtrl,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Officiating priest',
                ),
                controller: _officiantCtrl,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Marriage license number',
                ),
                controller: _licenseCtrl,
              ),

              const SizedBox(height: 16),
              const Text('Groom Information'),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: "Groom's full name",
                ),
                controller: _groomNameCtrl,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Age or date of birth',
                ),
                controller: _groomDobOrAgeCtrl,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Civil status before marriage',
                ),
                controller: _groomCivilStatusCtrl,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Religion'),
                controller: _groomReligionCtrl,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Address'),
                controller: _groomAddressCtrl,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: "Father's full name",
                ),
                controller: _groomFatherCtrl,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: "Mother's full name",
                ),
                controller: _groomMotherCtrl,
              ),

              const SizedBox(height: 16),
              const Text('Bride Information'),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: "Bride's full name",
                ),
                controller: _brideNameCtrl,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Age or date of birth',
                ),
                controller: _brideDobOrAgeCtrl,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Civil status before marriage',
                ),
                controller: _brideCivilStatusCtrl,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Religion'),
                controller: _brideReligionCtrl,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Address'),
                controller: _brideAddressCtrl,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: "Father's full name",
                ),
                controller: _brideFatherCtrl,
              ),
              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: "Mother's full name",
                ),
                controller: _brideMotherCtrl,
              ),

              const SizedBox(height: 8),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Witness #2'),
                controller: _witness2Ctrl,
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
                  value: _attachMarriageContract,
                  onChanged: (v) =>
                      setState(() => _attachMarriageContract = v ?? false),
                  title: const Text('Marriage Contract'),
                ),
                CheckboxListTile(
                  value: _attachIds,
                  onChanged: (v) => setState(() => _attachIds = v ?? false),
                  title: const Text('IDs'),
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
