import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../models/record.dart';
import '../../providers/records_provider.dart';
import '../../services/requests_repository.dart';

/// Staff-facing certificate request form.
///
/// Creates a ParishRecord with notes JSON containing:
/// {
///   "requestType": "certificate_request",
///   "recordType": "Baptism" | "Marriage" | "Confirmation" | "Death" | "Parish Certification",
///   "requestId": "REQ-000001",
///   "request": { ... template-specific fields ... },
///   "attachmentsChecklist": { ... },
///   "signatureImagePath": "...", // optional
///   "submittedAt": "ISO8601..."
/// }
class CertificateRequestFormScreen extends ConsumerStatefulWidget {
  const CertificateRequestFormScreen({super.key});

  @override
  ConsumerState<CertificateRequestFormScreen> createState() =>
      _CertificateRequestFormScreenState();
}

class _CertificateRequestFormScreenState
    extends ConsumerState<CertificateRequestFormScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isSaving = false;

  // Common
  String _recordType = 'Baptism';
  final _purposeCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  DateTime? _preferredPickupDate;

  // Auto-generated request ID
  String? _requestId;

  // Baptism fields
  final _baptismChildNameCtrl = TextEditingController();
  DateTime? _baptismDob;
  final _baptismPlaceOfBirthCtrl = TextEditingController();
  String _baptismGender = 'Male';
  final _baptismFatherCtrl = TextEditingController();
  final _baptismMotherCtrl = TextEditingController();
  final _baptismAddressCtrl = TextEditingController();
  DateTime? _baptismDateOfBaptism;
  final _baptismOfficiantCtrl = TextEditingController();

  // Marriage fields
  final _marriageGroomNameCtrl = TextEditingController();
  final _marriageBrideNameCtrl = TextEditingController();
  DateTime? _marriageDate;
  final _marriagePlaceCtrl = TextEditingController(
    text: 'Holy Rosary Parish – Oroquieta City',
  );
  final _marriageOfficiantCtrl = TextEditingController();
  final _marriageAddressCtrl = TextEditingController();

  // Confirmation fields
  final _confFullNameCtrl = TextEditingController();
  DateTime? _confDob;
  final _confAddressCtrl = TextEditingController();
  DateTime? _confDate;
  final _confPlaceCtrl = TextEditingController(
    text: 'Holy Rosary Parish – Oroquieta City',
  );
  final _confOfficiantCtrl = TextEditingController();
  final _confFatherCtrl = TextEditingController();
  final _confMotherCtrl = TextEditingController();
  final _confSponsorCtrl = TextEditingController();

  // Death / Funeral fields
  final _deathFullNameCtrl = TextEditingController();
  DateTime? _deathDob;
  DateTime? _deathDod;
  final _deathPlaceOfDeathCtrl = TextEditingController();
  final _deathCauseCtrl = TextEditingController();
  DateTime? _deathFuneralDate;
  final _deathFuneralVenueCtrl = TextEditingController(
    text: 'Holy Rosary Parish – Oroquieta City',
  );
  final _deathOfficiantCtrl = TextEditingController();
  final _deathRequestorNameCtrl = TextEditingController();
  final _deathRelationshipCtrl = TextEditingController();
  final _deathAddressCtrl = TextEditingController();

  // Parish Certification fields
  final _certFullNameCtrl = TextEditingController();
  final _certAddressCtrl = TextEditingController();
  String _certType = 'No Baptism Record';
  final _certOtherTypeCtrl = TextEditingController();

  // Attachments checklist state
  bool _attachment1 = false;
  bool _attachment2 = false;
  bool _attachment3 = false;

  // Signature image
  final ImagePicker _picker = ImagePicker();
  String? _signatureImagePath;

  @override
  void initState() {
    super.initState();
    _initializeRequestId();
  }

  Future<void> _initializeRequestId() async {
    // Simple local auto-increment based on existing certificate_request records in memory
    // We look at notes.requestId or metadata.requestId if present.
    final records = ref.read(recordsProvider);
    int maxNumeric = 0;
    final regex = RegExp(r'(?:REQ-)?(\d+)');

    for (final r in records) {
      if (r.notes == null || r.notes!.isEmpty) continue;
      try {
        final decoded = json.decode(r.notes!);
        if (decoded is! Map<String, dynamic>) continue;
        final type =
            (decoded['requestType'] as String?) ??
            (decoded['request_type'] as String?);
        if (type != 'certificate_request') continue;
        final meta = decoded['metadata'] as Map<String, dynamic>?;
        final fromRoot = decoded['requestId']?.toString();
        final fromMeta = meta?['requestId']?.toString();
        final idStr = fromMeta?.isNotEmpty == true ? fromMeta : fromRoot;
        if (idStr == null || idStr.isEmpty) continue;
        final match = regex.firstMatch(idStr);
        if (match == null) continue;
        final num = int.tryParse(match.group(1)!);
        if (num != null && num > maxNumeric) {
          maxNumeric = num;
        }
      } catch (_) {}
    }

    final next = maxNumeric + 1;
    setState(() {
      _requestId = 'REQ-${next.toString().padLeft(6, '0')}';
    });
  }

  @override
  void dispose() {
    _purposeCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
    _baptismChildNameCtrl.dispose();
    _baptismPlaceOfBirthCtrl.dispose();
    _baptismFatherCtrl.dispose();
    _baptismMotherCtrl.dispose();
    _baptismAddressCtrl.dispose();
    _baptismOfficiantCtrl.dispose();
    _marriageGroomNameCtrl.dispose();
    _marriageBrideNameCtrl.dispose();
    _marriagePlaceCtrl.dispose();
    _marriageOfficiantCtrl.dispose();
    _marriageAddressCtrl.dispose();
    _confFullNameCtrl.dispose();
    _confAddressCtrl.dispose();
    _confPlaceCtrl.dispose();
    _confOfficiantCtrl.dispose();
    _confFatherCtrl.dispose();
    _confMotherCtrl.dispose();
    _confSponsorCtrl.dispose();
    _deathFullNameCtrl.dispose();
    _deathPlaceOfDeathCtrl.dispose();
    _deathCauseCtrl.dispose();
    _deathFuneralVenueCtrl.dispose();
    _deathOfficiantCtrl.dispose();
    _deathRequestorNameCtrl.dispose();
    _deathRelationshipCtrl.dispose();
    _deathAddressCtrl.dispose();
    _certFullNameCtrl.dispose();
    _certAddressCtrl.dispose();
    _certOtherTypeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(
    BuildContext context,
    void Function(DateTime) set, {
    DateTime? initial,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) set(picked);
  }

  Future<void> _pickSignatureImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() {
        _signatureImagePath = file.path;
      });
    }
  }

  Map<String, dynamic> _buildRequestBody() {
    final df = DateFormat('yyyy-MM-dd');
    final nowIso = DateTime.now().toIso8601String();

    Map<String, dynamic> specific = {};

    switch (_recordType) {
      case 'Baptism':
        specific = {
          'childName': _baptismChildNameCtrl.text.trim(),
          'dateOfBirth': _baptismDob == null ? null : df.format(_baptismDob!),
          'placeOfBirth': _baptismPlaceOfBirthCtrl.text.trim(),
          'gender': _baptismGender,
          'fatherName': _baptismFatherCtrl.text.trim(),
          'motherName': _baptismMotherCtrl.text.trim(),
          'address': _baptismAddressCtrl.text.trim(),
          'dateOfBaptism': _baptismDateOfBaptism == null
              ? null
              : df.format(_baptismDateOfBaptism!),
          'officiatingPriest': _baptismOfficiantCtrl.text.trim(),
        };
        break;
      case 'Marriage':
        specific = {
          'groomName': _marriageGroomNameCtrl.text.trim(),
          'brideName': _marriageBrideNameCtrl.text.trim(),
          'dateOfMarriage': _marriageDate == null
              ? null
              : df.format(_marriageDate!),
          'placeOfMarriage': _marriagePlaceCtrl.text.trim(),
          'officiatingPriest': _marriageOfficiantCtrl.text.trim(),
          'address': _marriageAddressCtrl.text.trim(),
        };
        break;
      case 'Confirmation':
        specific = {
          'fullName': _confFullNameCtrl.text.trim(),
          'dateOfBirth': _confDob == null ? null : df.format(_confDob!),
          'address': _confAddressCtrl.text.trim(),
          'dateOfConfirmation': _confDate == null
              ? null
              : df.format(_confDate!),
          'placeOfConfirmation': _confPlaceCtrl.text.trim(),
          'confirmingPriestOrBishop': _confOfficiantCtrl.text.trim(),
          'fatherName': _confFatherCtrl.text.trim(),
          'motherName': _confMotherCtrl.text.trim(),
          'sponsor': _confSponsorCtrl.text.trim(),
        };
        break;
      case 'Death':
        specific = {
          'fullNameOfDeceased': _deathFullNameCtrl.text.trim(),
          'dateOfBirth': _deathDob == null ? null : df.format(_deathDob!),
          'dateOfDeath': _deathDod == null ? null : df.format(_deathDod!),
          'placeOfDeath': _deathPlaceOfDeathCtrl.text.trim(),
          'causeOfDeath': _deathCauseCtrl.text.trim(),
          'dateOfFuneralService': _deathFuneralDate == null
              ? null
              : df.format(_deathFuneralDate!),
          'funeralMassVenue': _deathFuneralVenueCtrl.text.trim(),
          'officiatingPriest': _deathOfficiantCtrl.text.trim(),
          'requestorName': _deathRequestorNameCtrl.text.trim(),
          'relationshipToDeceased': _deathRelationshipCtrl.text.trim(),
          'address': _deathAddressCtrl.text.trim(),
        };
        break;
      case 'Parish Certification':
        specific = {
          'fullName': _certFullNameCtrl.text.trim(),
          'address': _certAddressCtrl.text.trim(),
          'certificationType': _certType,
          'otherCertificationType': _certType == 'Others'
              ? _certOtherTypeCtrl.text.trim()
              : null,
        };
        break;
    }

    Map<String, dynamic> attachmentsChecklist;
    switch (_recordType) {
      case 'Baptism':
        attachmentsChecklist = {
          'psaBirthCertificate': _attachment1,
          'parentsId': _attachment2,
        };
        break;
      case 'Marriage':
        attachmentsChecklist = {
          'groomId': _attachment1,
          'brideId': _attachment2,
        };
        break;
      case 'Confirmation':
        attachmentsChecklist = {
          'baptismCertificate': _attachment1,
          'id': _attachment2,
        };
        break;
      case 'Death':
        attachmentsChecklist = {
          'psaDeathCertificate': _attachment1,
          'requestorId': _attachment2,
        };
        break;
      case 'Parish Certification':
      default:
        attachmentsChecklist = {
          'validId': _attachment1,
          'barangayClearance': _attachment2,
          'others': _attachment3,
        };
        break;
    }

    return {
      'requestType': 'certificate_request',
      'recordType': _recordType,
      'requestId': _requestId,
      'request': specific,
      'purpose': _purposeCtrl.text.trim(),
      'contactNumber': _contactCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'preferredPickupDate': _preferredPickupDate == null
          ? null
          : df.format(_preferredPickupDate!),
      'attachmentsChecklist': attachmentsChecklist,
      'signatureImagePath': _signatureImagePath,
      'submittedAt': nowIso,
      'metadata': {'requestId': _requestId, 'submittedAt': nowIso},
    };
  }

  Future<void> _save() async {
    if (_isSaving) return;

    if (!(_formKey.currentState?.validate() ?? false)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete required fields')),
      );
      return;
    }

    final body = _buildRequestBody();
    final name = _resolveDisplayName();
    final now = DateTime.now();

    try {
      setState(() {
        _isSaving = true;
      });
      await ref
          .read(recordsProvider.notifier)
          .addRecord(
            // Use baptism type as generic; AdminCertificatesPage filters by notes.requestType
            RecordType.baptism,
            name,
            now,
            notes: json.encode(body),
          );

      // Also create a backend certificate request entry so that analytics and
      // admin tools backed by Cassandra can see it.
      try {
        final requestsRepo = RequestsRepository();
        final requestType = _mapRecordTypeToRequestType();
        await requestsRepo.create(
          requestType: requestType,
          requesterName: name,
          recordId: null,
          parishId: null,
        );
      } catch (_) {
        // Ignore backend request creation errors; the main ParishRecord is
        // already saved and used by the admin UI.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Certificate request submitted')),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final router = GoRouter.of(context);
        if (router.canPop()) {
          router.pop(true);
        } else {
          context.go('/records/certificates');
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit request: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _resolveDisplayName() {
    switch (_recordType) {
      case 'Baptism':
        return _baptismChildNameCtrl.text.trim();
      case 'Marriage':
        return '${_marriageGroomNameCtrl.text.trim()} & ${_marriageBrideNameCtrl.text.trim()}';
      case 'Confirmation':
        return _confFullNameCtrl.text.trim();
      case 'Death':
        return _deathFullNameCtrl.text.trim();
      case 'Parish Certification':
      default:
        return _certFullNameCtrl.text.trim();
    }
  }

  String _mapRecordTypeToRequestType() {
    switch (_recordType) {
      case 'Baptism':
        return 'baptism';
      case 'Marriage':
        return 'marriage';
      case 'Confirmation':
        return 'confirmation';
      case 'Death':
        return 'death';
      case 'Parish Certification':
        return 'parish_certification';
      default:
        return 'baptism';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final df = DateFormat('yMMMd');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Certificate Request'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Submit'),
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
              DropdownButtonFormField<String>(
                initialValue: _recordType,
                items: const [
                  DropdownMenuItem(
                    value: 'Baptism',
                    child: Text('Baptism Certificate'),
                  ),
                  DropdownMenuItem(
                    value: 'Marriage',
                    child: Text('Marriage Certificate'),
                  ),
                  DropdownMenuItem(
                    value: 'Confirmation',
                    child: Text('Confirmation Certificate'),
                  ),
                  DropdownMenuItem(
                    value: 'Death',
                    child: Text('Funeral / Death Certificate'),
                  ),
                  DropdownMenuItem(
                    value: 'Parish Certification',
                    child: Text('Parish Certification'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _recordType = v;
                    _attachment1 = false;
                    _attachment2 = false;
                    _attachment3 = false;
                  });
                },
                decoration: const InputDecoration(labelText: 'Request type'),
              ),
              const SizedBox(height: 16),
              _buildTypeSpecificSection(df, colorScheme),
              const SizedBox(height: 16),
              TextFormField(
                controller: _purposeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Purpose of request',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter purpose'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _contactCtrl,
                decoration: const InputDecoration(labelText: 'Contact number'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email address (optional)',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Preferred pick-up date: '
                      '${_preferredPickupDate == null ? 'Not set' : df.format(_preferredPickupDate!)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () => _pickDate(
                      context,
                      (d) => setState(() => _preferredPickupDate = d),
                      initial: _preferredPickupDate ?? DateTime.now(),
                    ),
                    child: const Text('Pick date'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Attached Requirements',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ..._buildAttachmentCheckboxes(),
              const SizedBox(height: 16),
              Text(
                'Signature of Requestor',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _signatureImagePath == null
                          ? 'No signature image selected'
                          : _signatureImagePath!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _pickSignatureImage,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Attach'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSpecificSection(DateFormat df, ColorScheme colorScheme) {
    switch (_recordType) {
      case 'Baptism':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _baptismChildNameCtrl,
              decoration: const InputDecoration(labelText: "Child's name"),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter child\'s name'
                  : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Date of birth: '
                    '${_baptismDob == null ? 'Not set' : df.format(_baptismDob!)}',
                  ),
                ),
                TextButton(
                  onPressed: () => _pickDate(
                    context,
                    (d) => setState(() => _baptismDob = d),
                    initial: _baptismDob ?? DateTime.now(),
                  ),
                  child: const Text('Pick date'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _baptismPlaceOfBirthCtrl,
              decoration: const InputDecoration(labelText: 'Place of birth'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _baptismGender,
              items: const [
                DropdownMenuItem(value: 'Male', child: Text('Male')),
                DropdownMenuItem(value: 'Female', child: Text('Female')),
              ],
              onChanged: (v) => setState(() => _baptismGender = v ?? 'Male'),
              decoration: const InputDecoration(labelText: 'Gender'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _baptismFatherCtrl,
              decoration: const InputDecoration(labelText: "Father's name"),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _baptismMotherCtrl,
              decoration: const InputDecoration(labelText: "Mother's name"),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _baptismAddressCtrl,
              decoration: const InputDecoration(labelText: "Address"),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Date of baptism: '
                    '${_baptismDateOfBaptism == null ? 'Not set' : df.format(_baptismDateOfBaptism!)}',
                  ),
                ),
                TextButton(
                  onPressed: () => _pickDate(
                    context,
                    (d) => setState(() => _baptismDateOfBaptism = d),
                    initial: _baptismDateOfBaptism ?? DateTime.now(),
                  ),
                  child: const Text('Pick date'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _baptismOfficiantCtrl,
              decoration: const InputDecoration(
                labelText: 'Officiating priest (if known)',
              ),
            ),
          ],
        );
      case 'Marriage':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _marriageGroomNameCtrl,
              decoration: const InputDecoration(labelText: "Groom's full name"),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter groom\'s name'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _marriageBrideNameCtrl,
              decoration: const InputDecoration(labelText: "Bride's full name"),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter bride\'s name'
                  : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Date of marriage: '
                    '${_marriageDate == null ? 'Not set' : df.format(_marriageDate!)}',
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
              controller: _marriagePlaceCtrl,
              decoration: const InputDecoration(labelText: 'Place of marriage'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _marriageOfficiantCtrl,
              decoration: const InputDecoration(
                labelText: 'Officiating priest (if known)',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _marriageAddressCtrl,
              decoration: const InputDecoration(labelText: "Couple's address"),
            ),
          ],
        );
      case 'Confirmation':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _confFullNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Full name of confirmand',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Please enter name' : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Date of birth: '
                    '${_confDob == null ? 'Not set' : df.format(_confDob!)}',
                  ),
                ),
                TextButton(
                  onPressed: () => _pickDate(
                    context,
                    (d) => setState(() => _confDob = d),
                    initial: _confDob ?? DateTime.now(),
                  ),
                  child: const Text('Pick date'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confAddressCtrl,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Date of confirmation: '
                    '${_confDate == null ? 'Not set' : df.format(_confDate!)}',
                  ),
                ),
                TextButton(
                  onPressed: () => _pickDate(
                    context,
                    (d) => setState(() => _confDate = d),
                    initial: _confDate ?? DateTime.now(),
                  ),
                  child: const Text('Pick date'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confPlaceCtrl,
              decoration: const InputDecoration(
                labelText: 'Place of confirmation',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confOfficiantCtrl,
              decoration: const InputDecoration(
                labelText: 'Confirming priest/bishop',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confFatherCtrl,
              decoration: const InputDecoration(labelText: "Father's name"),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confMotherCtrl,
              decoration: const InputDecoration(labelText: "Mother's name"),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confSponsorCtrl,
              decoration: const InputDecoration(
                labelText: 'Sponsor / Ninong / Ninang',
              ),
            ),
          ],
        );
      case 'Death':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _deathFullNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Full name of deceased',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Please enter name' : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Date of birth: '
                    '${_deathDob == null ? 'Not set' : df.format(_deathDob!)}',
                  ),
                ),
                TextButton(
                  onPressed: () => _pickDate(
                    context,
                    (d) => setState(() => _deathDob = d),
                    initial: _deathDob ?? DateTime.now(),
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
                    'Date of death: '
                    '${_deathDod == null ? 'Not set' : df.format(_deathDod!)}',
                  ),
                ),
                TextButton(
                  onPressed: () => _pickDate(
                    context,
                    (d) => setState(() => _deathDod = d),
                    initial: _deathDod ?? DateTime.now(),
                  ),
                  child: const Text('Pick date'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _deathPlaceOfDeathCtrl,
              decoration: const InputDecoration(labelText: 'Place of death'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _deathCauseCtrl,
              decoration: const InputDecoration(
                labelText: 'Cause of death (optional)',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Date of funeral service: '
                    '${_deathFuneralDate == null ? 'Not set' : df.format(_deathFuneralDate!)}',
                  ),
                ),
                TextButton(
                  onPressed: () => _pickDate(
                    context,
                    (d) => setState(() => _deathFuneralDate = d),
                    initial: _deathFuneralDate ?? DateTime.now(),
                  ),
                  child: const Text('Pick date'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _deathFuneralVenueCtrl,
              decoration: const InputDecoration(
                labelText: 'Funeral mass venue',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _deathOfficiantCtrl,
              decoration: const InputDecoration(
                labelText: 'Officiating priest',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _deathRequestorNameCtrl,
              decoration: const InputDecoration(labelText: 'Name of requestor'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _deathRelationshipCtrl,
              decoration: const InputDecoration(
                labelText: 'Relationship to deceased',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _deathAddressCtrl,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
          ],
        );
      case 'Parish Certification':
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _certFullNameCtrl,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Please enter name' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _certAddressCtrl,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _certType,
              items: const [
                DropdownMenuItem(
                  value: 'No Baptism Record',
                  child: Text('No Baptism Record'),
                ),
                DropdownMenuItem(
                  value: 'No Confirmation Record',
                  child: Text('No Confirmation Record'),
                ),
                DropdownMenuItem(
                  value: 'No Marriage Record',
                  child: Text('No Marriage Record'),
                ),
                DropdownMenuItem(
                  value: 'Parish Residency',
                  child: Text('Parish Residency'),
                ),
                DropdownMenuItem(
                  value: 'Parish Good Standing',
                  child: Text('Parish Good Standing'),
                ),
                DropdownMenuItem(value: 'Others', child: Text('Others')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _certType = v;
                });
              },
              decoration: const InputDecoration(
                labelText: 'Type of certification requested',
              ),
            ),
            if (_certType == 'Others') ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _certOtherTypeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Specify other type',
                ),
              ),
            ],
          ],
        );
    }
  }

  List<Widget> _buildAttachmentCheckboxes() {
    final List<Widget> boxes = [];

    void add(String label, int index) {
      bool value;
      switch (index) {
        case 1:
          value = _attachment1;
          break;
        case 2:
          value = _attachment2;
          break;
        case 3:
        default:
          value = _attachment3;
          break;
      }
      boxes.add(
        CheckboxListTile(
          value: value,
          onChanged: (v) {
            setState(() {
              switch (index) {
                case 1:
                  _attachment1 = v ?? false;
                  break;
                case 2:
                  _attachment2 = v ?? false;
                  break;
                case 3:
                default:
                  _attachment3 = v ?? false;
                  break;
              }
            });
          },
          title: Text(label),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      );
    }

    switch (_recordType) {
      case 'Baptism':
        add('PSA Birth Certificate', 1);
        add("Parent's ID", 2);
        break;
      case 'Marriage':
        add("Groom's ID", 1);
        add("Bride's ID", 2);
        break;
      case 'Confirmation':
        add('Baptism Certificate', 1);
        add('ID', 2);
        break;
      case 'Death':
        add('PSA Death Certificate', 1);
        add("Requestor's Valid ID", 2);
        break;
      case 'Parish Certification':
      default:
        add('Valid ID', 1);
        add('Barangay Clearance', 2);
        add('Others', 3);
        break;
    }

    if (boxes.isEmpty) {
      boxes.add(
        Text(
          'No specific requirements configured for this type.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return boxes;
  }
}
