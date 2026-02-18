import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../models/record.dart';
import '../../providers/records_provider.dart';
import '../../providers/auth_provider.dart';
import '../ocr/ocr_scan_screen.dart';

class EnhancedBaptismFormScreen extends ConsumerStatefulWidget {
  final ParishRecord? existing;
  final bool fromAdmin;
  final bool startWithOcr;

  const EnhancedBaptismFormScreen({
    super.key,
    this.existing,
    this.fromAdmin = false,
    this.startWithOcr = false,
  });

  @override
  ConsumerState<EnhancedBaptismFormScreen> createState() =>
      _EnhancedBaptismFormScreenState();
}

class _EnhancedBaptismFormScreenState
    extends ConsumerState<EnhancedBaptismFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _recordId;

  // Registry fields
  final _registryNoCtrl = TextEditingController();
  final _bookNoCtrl = TextEditingController();
  final _pageNoCtrl = TextEditingController();
  final _lineNoCtrl = TextEditingController();

  // Child Information
  final _nameCtrl = TextEditingController();
  DateTime? _dob;
  final _placeOfBirthCtrl = TextEditingController();
  String _gender = 'Male';
  final _addressCtrl = TextEditingController();
  // Parents
  final _fatherCtrl = TextEditingController();
  final _motherCtrl = TextEditingController();
  final _parentsMarriageCtrl = TextEditingController();

  // Godparents
  final _godfather1Ctrl = TextEditingController();
  final _godmother1Ctrl = TextEditingController();
  final _godfather2Ctrl = TextEditingController();
  final _godmother2Ctrl = TextEditingController();

  // Baptism details
  DateTime? _baptismDate;
  final _baptismTimeCtrl = TextEditingController();
  final _baptismPlaceCtrl = TextEditingController();
  final _ministerCtrl = TextEditingController();

  // Metadata
  final _remarksCtrl = TextEditingController();
  bool _certificateIssued = false;
  final _staffNameCtrl = TextEditingController();

  // Attachment
  String? _attachmentPath;
  bool _psaBirthCertificate = false;
  bool _parentsId = false;
  String? _encoderSignaturePath;
  String? _priestSignaturePath;
  String? _ocrRawText;

  @override
  void initState() {
    super.initState();
    // Auto-generate registry number for new records
    final now = DateTime.now();
    _registryNoCtrl.text =
        '${now.year}-${now.millisecondsSinceEpoch.toString().substring(8)}-B';

    // Generate Record ID for new records: HRP-BAP-YYYYMMDD-UUID
    final datePart = DateFormat('yyyyMMdd').format(now);
    _recordId = 'HRP-BAP-$datePart-${const Uuid().v4()}';

    // Auto-populate staff name (you can get this from auth context)
    final authState = ref.read(authProvider);
    final currentUser = authState.user;
    if (currentUser != null) {
      final displayName = (currentUser.displayName ?? '').trim();
      if (displayName.isNotEmpty) {
        _staffNameCtrl.text = displayName;
      } else if (currentUser.email.isNotEmpty) {
        _staffNameCtrl.text = currentUser.email;
      } else {
        _staffNameCtrl.text = 'Current Staff';
      }
    } else {
      _staffNameCtrl.text = 'Current Staff';
    }

    // If editing an existing record, prefill fields from its stored JSON notes
    final existing = widget.existing;
    if (existing != null) {
      try {
        final raw = existing.notes;
        if (raw != null && raw.isNotEmpty) {
          final decoded = json.decode(raw) as Map<String, dynamic>;

          final registry = decoded['registry'] as Map<String, dynamic>?;
          final child = decoded['child'] as Map<String, dynamic>?;
          final parents = decoded['parents'] as Map<String, dynamic>?;
          final godparents = decoded['godparents'] as Map<String, dynamic>?;
          final baptism = decoded['baptism'] as Map<String, dynamic>?;
          final metadata = decoded['metadata'] as Map<String, dynamic>?;
          final attachments = decoded['attachments'] as List<dynamic>?;

          if (registry != null) {
            _registryNoCtrl.text = (registry['registryNo'] ?? '').toString();
            _bookNoCtrl.text = (registry['bookNo'] ?? '').toString();
            _pageNoCtrl.text = (registry['pageNo'] ?? '').toString();
            _lineNoCtrl.text = (registry['lineNo'] ?? '').toString();
          }

          if (child != null) {
            _nameCtrl.text = (child['fullName'] ?? '').toString();
            final dobRaw = child['dateOfBirth']?.toString();
            if (dobRaw != null && dobRaw.isNotEmpty) {
              _dob = DateTime.tryParse(dobRaw);
            }
            _placeOfBirthCtrl.text = (child['placeOfBirth'] ?? '').toString();
            _gender = (child['gender'] ?? _gender).toString();
            _addressCtrl.text = (child['address'] ?? '').toString();
          }

          if (parents != null) {
            _fatherCtrl.text = (parents['father'] ?? '').toString();
            _motherCtrl.text = (parents['mother'] ?? '').toString();
            _parentsMarriageCtrl.text = (parents['marriageInfo'] ?? '')
                .toString();
          }

          if (godparents != null) {
            _godfather1Ctrl.text = (godparents['godfather1'] ?? '').toString();
            _godmother1Ctrl.text = (godparents['godmother1'] ?? '').toString();
            _godfather2Ctrl.text = (godparents['godfather2'] ?? '').toString();
            _godmother2Ctrl.text = (godparents['godmother2'] ?? '').toString();
          }

          if (baptism != null) {
            final baptDateRaw = baptism['date']?.toString();
            if (baptDateRaw != null && baptDateRaw.isNotEmpty) {
              _baptismDate = DateTime.tryParse(baptDateRaw);
            }
            _baptismTimeCtrl.text = (baptism['time'] ?? '').toString();
            _baptismPlaceCtrl.text = (baptism['place'] ?? '').toString();
            _ministerCtrl.text = (baptism['minister'] ?? '').toString();
          }

          if (metadata != null) {
            _remarksCtrl.text = (metadata['remarks'] ?? '').toString();
            _certificateIssued = metadata['certificateIssued'] == true;
            final staffName = (metadata['staffName'] ?? '').toString();
            if (staffName.isNotEmpty) {
              _staffNameCtrl.text = staffName;
            }
            final recordId = metadata['recordId']?.toString();
            if (recordId != null && recordId.isNotEmpty) {
              _recordId = recordId;
            }
            final attachmentsChecklist =
                metadata['attachmentsChecklist'] as Map<String, dynamic>?;
            if (attachmentsChecklist != null) {
              _psaBirthCertificate =
                  attachmentsChecklist['psaBirthCertificate'] == true;
              _parentsId = attachmentsChecklist['parentsId'] == true;
            }
            final encoderSig = metadata['encoderSignaturePath']?.toString();
            if (encoderSig != null && encoderSig.isNotEmpty) {
              _encoderSignaturePath = encoderSig;
            }
            final priestSig = metadata['priestSignaturePath']?.toString();
            if (priestSig != null && priestSig.isNotEmpty) {
              _priestSignaturePath = priestSig;
            }
            final ocrText = metadata['ocrRawText']?.toString();
            if (ocrText != null && ocrText.isNotEmpty) {
              _ocrRawText = ocrText;
            }
          }

          if (attachments != null && attachments.isNotEmpty) {
            final first = attachments.first as Map<String, dynamic>?;
            _attachmentPath = first?['path']?.toString();
          }
        }
      } catch (_) {
        // If parsing fails, fall back to defaults
      }
    }

    // Default place of baptism for new records
    if (widget.existing == null && _baptismPlaceCtrl.text.isEmpty) {
      _baptismPlaceCtrl.text = 'Holy Rosary Parish – Oroquieta City';
    }

    if (widget.existing == null && widget.startWithOcr) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scanOcr();
      });
    }
  }

  @override
  void dispose() {
    _registryNoCtrl.dispose();
    _bookNoCtrl.dispose();
    _pageNoCtrl.dispose();
    _lineNoCtrl.dispose();
    _nameCtrl.dispose();
    _placeOfBirthCtrl.dispose();
    _addressCtrl.dispose();
    _fatherCtrl.dispose();
    _motherCtrl.dispose();
    _parentsMarriageCtrl.dispose();
    _godfather1Ctrl.dispose();
    _godmother1Ctrl.dispose();
    _godfather2Ctrl.dispose();
    _godmother2Ctrl.dispose();
    _baptismTimeCtrl.dispose();
    _baptismPlaceCtrl.dispose();
    _ministerCtrl.dispose();
    _remarksCtrl.dispose();
    _staffNameCtrl.dispose();
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

  Future<void> _pickTime(BuildContext ctx) async {
    // Capture localizations before the async gap to avoid using BuildContext afterwards.
    final now = TimeOfDay.now();
    final localizations = MaterialLocalizations.of(ctx);
    final picked = await showTimePicker(context: ctx, initialTime: now);
    if (picked != null) {
      final formatted = localizations.formatTimeOfDay(picked);
      setState(() {
        _baptismTimeCtrl.text = formatted;
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

  Future<List<ParishRecord>> _findPossibleDuplicates() async {
    final records = ref.read(recordsProvider);
    final name = _nameCtrl.text.trim().toLowerCase();
    final baptDate = _baptismDate;
    final bookNo = _bookNoCtrl.text.trim();
    final pageNo = _pageNoCtrl.text.trim();
    final lineNo = _lineNoCtrl.text.trim();

    if (name.isEmpty) return const [];

    bool matchesRegistry(ParishRecord r) {
      if (r.notes == null || r.notes!.isEmpty) return false;
      try {
        final decoded = json.decode(r.notes!);
        if (decoded is! Map<String, dynamic>) return false;
        final registry = decoded['registry'] as Map<String, dynamic>?;
        if (registry == null) return false;
        bool eq(String a, dynamic b) =>
            a.isNotEmpty && b != null && a == b.toString().trim();
        if (eq(bookNo, registry['bookNo']) &&
            eq(pageNo, registry['pageNo']) &&
            eq(lineNo, registry['lineNo'])) {
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
      if (r.type != RecordType.baptism) {
        return false;
      }
      final rName = r.name.trim().toLowerCase();
      if (rName != name) {
        return false;
      }
      // Strong match on registry info
      if (bookNo.isNotEmpty || pageNo.isNotEmpty || lineNo.isNotEmpty) {
        if (matchesRegistry(r)) {
          return true;
        }
      }
      // Otherwise use close baptism date
      if (baptDate != null && closeDate(baptDate, r.date)) {
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
              title: const Text('Possible duplicate records found'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Records with the same name and similar date or registry info already exist. Review them before saving to avoid duplicates.',
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

    // Check for possible duplicates first
    final duplicates = await _findPossibleDuplicates();
    final proceed = await _confirmDuplicates(duplicates);
    if (!proceed) {
      return;
    }

    final name = _nameCtrl.text.trim();
    final baptDate = _baptismDate ?? DateTime.now();
    final dfIso = DateFormat("yyyy-MM-dd");

    final details = <String, dynamic>{
      'registry': {
        'registryNo': _registryNoCtrl.text.trim(),
        'bookNo': _bookNoCtrl.text.trim(),
        'pageNo': _pageNoCtrl.text.trim(),
        'lineNo': _lineNoCtrl.text.trim(),
      },
      'child': {
        'fullName': name,
        'dateOfBirth': _dob == null ? null : dfIso.format(_dob!),
        'placeOfBirth': _placeOfBirthCtrl.text.trim(),
        'gender': _gender,
        'address': _addressCtrl.text.trim(),
      },
      'parents': {
        'father': _fatherCtrl.text.trim(),
        'mother': _motherCtrl.text.trim(),
        'marriageInfo': _parentsMarriageCtrl.text.trim(),
      },
      'godparents': {
        'godfather1': _godfather1Ctrl.text.trim(),
        'godmother1': _godmother1Ctrl.text.trim(),
        'godfather2': _godfather2Ctrl.text.trim(),
        'godmother2': _godmother2Ctrl.text.trim(),
      },
      'baptism': {
        'date': dfIso.format(baptDate),
        'time': _baptismTimeCtrl.text.trim(),
        'place': _baptismPlaceCtrl.text.trim(),
        'minister': _ministerCtrl.text.trim(),
      },
      'metadata': {
        'remarks': _remarksCtrl.text.trim(),
        'certificateIssued': _certificateIssued,
        'staffName': _staffNameCtrl.text.trim(),
        'dateEncoded': DateTime.now().toIso8601String(),
        'recordId': _recordId,
        'attachmentsChecklist': {
          'psaBirthCertificate': _psaBirthCertificate,
          'parentsId': _parentsId,
        },
        'encoderSignaturePath': _encoderSignaturePath,
        'priestSignaturePath': _priestSignaturePath,
        'ocrRawText': _ocrRawText,
      },
      'attachments': _attachmentPath == null
          ? []
          : [
              {'type': 'image', 'path': _attachmentPath},
            ],
    };

    try {
      final notifier = ref.read(recordsProvider.notifier);
      if (widget.existing == null) {
        await notifier.addRecord(
          RecordType.baptism,
          name,
          baptDate,
          imagePath: _attachmentPath,
          notes: json.encode(details),
        );
      } else {
        await notifier.updateRecord(
          widget.existing!.id,
          type: RecordType.baptism,
          name: name,
          date: baptDate,
          imagePath: _attachmentPath,
          notes: json.encode(details),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existing == null
                  ? 'Baptism record saved successfully'
                  : 'Baptism record updated successfully',
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
        title: const Text('Baptism Record Entry'),
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
              // Registry Information (no visible Record ID)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Registry Information',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _bookNoCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Book No',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _pageNoCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Page No',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _lineNoCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Line No',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Child Information
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Child Information',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: "Child's Full Name",
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Date of Birth: ${_dob == null ? 'Not set' : df.format(_dob!)}',
                            ),
                          ),
                          TextButton(
                            onPressed: () => _pickDate(
                              context,
                              (d) => setState(() => _dob = d),
                              initial: _dob,
                            ),
                            child: const Text('Pick Date'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _placeOfBirthCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Place of Birth',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _gender,
                        items: const [
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(
                            value: 'Female',
                            child: Text('Female'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _gender = v ?? 'Male'),
                        decoration: const InputDecoration(labelText: 'Gender'),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _addressCtrl,
                        decoration: const InputDecoration(labelText: 'Address'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Parents Information
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Parents Information',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _fatherCtrl,
                        decoration: const InputDecoration(
                          labelText: "Father's Name",
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _motherCtrl,
                        decoration: const InputDecoration(
                          labelText: "Mother's Name",
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _parentsMarriageCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Parents Marriage Info (Place & Date)',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Godparents
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Godparents',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _godfather1Ctrl,
                        decoration: const InputDecoration(
                          labelText: 'Godfather #1',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _godmother1Ctrl,
                        decoration: const InputDecoration(
                          labelText: 'Godmother #1',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _godfather2Ctrl,
                        decoration: const InputDecoration(
                          labelText: 'Godfather #2 (Optional)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _godmother2Ctrl,
                        decoration: const InputDecoration(
                          labelText: 'Godmother #2 (Optional)',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Baptism Details
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Baptism Details',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Date of Baptism: ${_baptismDate == null ? 'Not set' : df.format(_baptismDate!)}',
                            ),
                          ),
                          TextButton(
                            onPressed: () => _pickDate(
                              context,
                              (d) => setState(() => _baptismDate = d),
                              initial: _baptismDate,
                            ),
                            child: const Text('Pick Date'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Time of Baptism: ${_baptismTimeCtrl.text.isEmpty ? 'Not set' : _baptismTimeCtrl.text}',
                            ),
                          ),
                          TextButton(
                            onPressed: () => _pickTime(context),
                            child: const Text('Pick Time'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _baptismPlaceCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Place of Baptism',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _ministerCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Minister',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (!widget.fromAdmin) ...[
                const SizedBox(height: 16),

                // Metadata
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Additional Information',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _remarksCtrl,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Remarks',
                          ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          title: const Text('Certificate Issued?'),
                          value: _certificateIssued,
                          onChanged: (v) =>
                              setState(() => _certificateIssued = v ?? false),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _staffNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Prepared By / Staff Name',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action buttons
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save Record'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
