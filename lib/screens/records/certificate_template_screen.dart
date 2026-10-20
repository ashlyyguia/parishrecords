import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/record.dart';
import '../../providers/records_provider.dart';
import '../../services/register_ocr_parser.dart';
import '../../utils/manual_register_notes.dart';
import '../../utils/register_text_parsing.dart';
import 'certificate_layouts.dart';
import 'certificate_zoom_view.dart';
import 'letter_certificate.dart';

/// Certificate data model for form editing
class CertificateData {
  String personName;
  String fatherName;
  String motherName;
  String birthplace;
  DateTime? birthDate;
  DateTime? sacramentDate;
  String ministerName;
  String sponsorName;
  String parishName;
  String parishLocation;
  String registryBook;
  String registryPage;
  String registryVolume;
  String registrySeries;
  DateTime? issueDate;
  String parishPriest;
  String? notes;

  // Good Moral certificate blanks (see GoodMoralFormScreen).
  String title;
  String residentOf;
  String personOf;
  String knownAs;
  String purpose;

  CertificateData({
    this.personName = '',
    this.fatherName = '',
    this.motherName = '',
    this.birthplace = '',
    this.birthDate,
    this.sacramentDate,
    this.ministerName = '',
    this.sponsorName = '',
    this.parishName = 'HOLY ROSARY PARISH',
    this.parishLocation = 'Oroquieta City',
    this.registryBook = '',
    this.registryPage = '',
    this.registryVolume = '',
    this.registrySeries = '',
    this.issueDate,
    this.parishPriest = 'FR. DANILO B. RUDINAS',
    this.notes,
    this.title = '',
    this.residentOf = '',
    this.personOf = '',
    this.knownAs = '',
    this.purpose = '',
  });

  factory CertificateData.fromRecord(
    ParishRecord record,
    Map<String, dynamic>? decodedNotes,
  ) {
    final data = CertificateData();

    // Extract data based on record type
    switch (record.type) {
      case RecordType.baptism:
        _extractBaptismData(data, record, decodedNotes);
        break;
      case RecordType.confirmation:
        _extractConfirmationData(data, record, decodedNotes);
        break;
      case RecordType.marriage:
        _extractMarriageData(data, record, decodedNotes);
        break;
      case RecordType.funeral:
        _extractFuneralData(data, record, decodedNotes);
        break;
      case RecordType.goodMoral:
        _extractGoodMoralData(data, record, decodedNotes);
        break;
      case RecordType.noRecord:
        _extractGoodMoralData(data, record, decodedNotes, key: 'noRecord');
        break;
    }

    return data;
  }

  /// Fields of an office-issued certificate (Good Moral, or No Record with
  /// [key] 'noRecord'), stored by its entry form under [key] in the notes.
  static void _extractGoodMoralData(
    CertificateData data,
    ParishRecord record,
    Map<String, dynamic>? notes, {
    String key = 'goodMoral',
  }) {
    data.personName = record.name;
    data.issueDate = record.date;
    final gm = _asMap(notes?[key]);
    if (gm == null) return;
    String s(String k) => (gm[k] ?? '').toString().trim();
    if (s('fullName').isNotEmpty) data.personName = s('fullName');
    data.title = s('title');
    data.residentOf = s('residentOf');
    data.personOf = s('personOf');
    data.knownAs = s('knownAs');
    data.purpose = s('purpose');
    if (s('parishPriest').isNotEmpty) data.parishPriest = s('parishPriest');
    data.issueDate = DateTime.tryParse(s('dateIssued')) ?? record.date;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static void _splitParentsIntoCertificate(
    dynamic parentsValue,
    CertificateData data,
  ) {
    if (parentsValue is String && parentsValue.trim().isNotEmpty) {
      final parts = parentsValue
          .split('/')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        data.fatherName = parts.first;
        data.motherName = parts.sublist(1).join(' / ');
      } else {
        data.fatherName = parentsValue.trim();
      }
      return;
    }
    final parents = _asMap(parentsValue);
    if (parents != null) {
      data.fatherName = parents['father']?.toString() ?? '';
      data.motherName = parents['mother']?.toString() ?? '';
    }
  }

  static void _applyParishFromRecord(
    CertificateData data,
    ParishRecord record,
  ) {
    final parish = (record.parish ?? '').trim();
    const defaults = {'manual register', 'register_ocr', 'register ocr', 'app'};
    if (parish.isEmpty || defaults.contains(parish.toLowerCase())) {
      data.parishName = data.parishName.isEmpty
          ? 'HOLY ROSARY PARISH'
          : data.parishName;
      return;
    }
    if (parish.toUpperCase().contains('PARISH')) {
      data.parishName = parish;
    } else {
      data.parishName = 'HOLY ROSARY PARISH';
      if (data.parishLocation.isEmpty ||
          data.parishLocation == 'Oroquieta City') {
        data.parishLocation = parish;
      }
    }
  }

  /// Manual register + OCR bulk JSON → certificate fields.
  static void _applyFlatRegisterNotes(
    CertificateData data,
    ParishRecord record,
    Map<String, dynamic> notes,
  ) {
    _applyParishFromRecord(data, record);
    data.issueDate ??= DateTime.now();

    final childName = ManualRegisterNotes.fieldAny(notes, [
      'nameOfChild',
      'name',
      'fullName',
    ]);
    if (childName.isNotEmpty) {
      data.personName = childName;
    } else if (record.name.trim().isNotEmpty) {
      data.personName = record.name.trim();
    }

    _parsePlaceAndBirthDate(
      ManualRegisterNotes.fieldAny(notes, [
        'placeAndBirthDate',
        'place_and_birth_date',
        'placeOfBirth',
      ]),
      data,
    );

    _splitParentsIntoCertificate(notes['parents'], data);

    final residents = ManualRegisterNotes.fieldAny(notes, [
      'residentsOf',
      'residents_of',
      'residentOf',
    ]);
    if (residents.isNotEmpty) {
      data.parishLocation = residents;
    }

    final sacramentText = ManualRegisterNotes.fieldAny(notes, [
      'dateOfBaptism',
      'date_of_baptism',
      'baptismDateText',
      'confirmationDate',
      'date',
    ]);
    if (sacramentText.isNotEmpty) {
      data.sacramentDate =
          RegisterOcrParser.parseDate(sacramentText) ?? data.sacramentDate;
    } else if (record.date != DateTime.fromMillisecondsSinceEpoch(0)) {
      data.sacramentDate ??= record.date;
    }

    data.ministerName = ManualRegisterNotes.fieldAny(notes, [
      'minister',
      'officiant',
    ]);
    data.sponsorName = ManualRegisterNotes.fieldAny(notes, [
      'sponsors',
      'sponsor',
      'godparents',
    ]);

    data.registryVolume = ManualRegisterNotes.fieldAny(notes, [
      'volNo',
      'vol_number',
      'volume',
      'vol',
    ]);
    data.registrySeries = ManualRegisterNotes.fieldAny(notes, [
      'seriesNo',
      'series_number',
      'series',
    ]);
    data.registryPage = ManualRegisterNotes.fieldAny(notes, [
      'lineNo',
      'line_no',
      'pageNo',
      'page',
    ]);
  }

  static void _applyRegistryMap(
    CertificateData data,
    Map<String, dynamic>? registry,
  ) {
    if (registry == null) return;
    data.registryPage = ManualRegisterNotes.fieldAny(registry, [
      'pageNo',
      'page',
    ]);
    data.registryVolume = ManualRegisterNotes.fieldAny(registry, [
      'registryNo',
      'volume',
      'volNo',
      'vol',
    ]);
    data.registrySeries = ManualRegisterNotes.fieldAny(registry, [
      'lineNo',
      'series',
      'seriesNo',
    ]);
  }

  static void _applyMetaRegistry(
    CertificateData data,
    Map<String, dynamic>? meta,
  ) {
    if (meta == null) return;
    if (data.registryPage.isEmpty) {
      data.registryPage = ManualRegisterNotes.fieldAny(meta, [
        'pageNo',
        'page',
      ]);
    }
    if (data.registryVolume.isEmpty) {
      data.registryVolume = ManualRegisterNotes.fieldAny(meta, [
        'volume',
        'volNo',
        'bookNo',
      ]);
    }
    if (data.registrySeries.isEmpty) {
      data.registrySeries = ManualRegisterNotes.fieldAny(meta, [
        'lineNo',
        'series',
        'seriesNo',
      ]);
    }
    final priest = ManualRegisterNotes.fieldAny(meta, ['staffName', 'priest']);
    if (priest.isNotEmpty) {
      data.parishPriest = priest;
    }
    final issued = meta['certificateIssued']?.toString();
    if (issued != null && issued.isNotEmpty) {
      data.issueDate = DateTime.tryParse(issued) ?? data.issueDate;
    }
  }

  static void _parsePlaceAndBirthDate(String text, CertificateData data) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final slashParts = trimmed
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    final parts = slashParts.toList();
    if (parts.length >= 2) {
      final last = parts.last;
      final date = RegisterOcrParser.parseDate(last);
      if (date != null) {
        data.birthDate = date;
        data.birthplace = parts.sublist(0, parts.length - 1).join(' / ');
        return;
      }
    }

    final date = RegisterOcrParser.parseDate(trimmed);
    if (date != null) {
      data.birthDate = date;
    } else {
      data.birthplace = trimmed;
    }
  }

  static void _extractBaptismData(
    CertificateData data,
    ParishRecord record,
    Map<String, dynamic>? notes,
  ) {
    data.personName = record.name.trim();
    data.parishName = 'HOLY ROSARY PARISH';
    data.sacramentDate = record.date;
    data.issueDate ??= DateTime.now();
    _applyParishFromRecord(data, record);

    if (notes == null) return;

    if (ManualRegisterNotes.usesFlatRegisterLayout(notes)) {
      _applyFlatRegisterNotes(data, record, notes);
      return;
    }

    final child = _asMap(notes['child']);
    final godparents = _asMap(notes['godparents']);
    final baptism = _asMap(notes['baptism']);
    final registry = _asMap(notes['registry']);
    final metadata = _asMap(notes['metadata']);

    if (child != null) {
      data.personName = child['fullName']?.toString() ?? record.name;
      if (child['dateOfBirth'] != null) {
        data.birthDate = DateTime.tryParse(child['dateOfBirth'].toString());
      }
      data.birthplace = child['placeOfBirth']?.toString() ?? '';
      final addr = child['address']?.toString() ?? '';
      if (addr.isNotEmpty && data.parishLocation == 'Oroquieta City') {
        data.parishLocation = addr;
      }
    }

    _splitParentsIntoCertificate(notes['parents'], data);

    if (godparents != null) {
      final godfather = godparents['godfather1']?.toString() ?? '';
      final godmother = godparents['godmother1']?.toString() ?? '';
      data.sponsorName = [
        godfather,
        godmother,
      ].where((s) => s.isNotEmpty).join(', ');
    }

    if (baptism != null) {
      data.ministerName = baptism['minister']?.toString() ?? '';
      if (baptism['date'] != null) {
        data.sacramentDate = DateTime.tryParse(baptism['date'].toString());
      }
      final place = baptism['place']?.toString() ?? '';
      if (place.isNotEmpty) data.parishLocation = place;
    }

    _applyRegistryMap(data, registry);
    _applyMetaRegistry(data, metadata);
  }

  static void _extractConfirmationData(
    CertificateData data,
    ParishRecord record,
    Map<String, dynamic>? notes,
  ) {
    data.personName = record.name.trim();
    data.parishName = 'HOLY ROSARY PARISH';
    data.sacramentDate = record.date;
    data.issueDate ??= DateTime.now();
    _applyParishFromRecord(data, record);

    if (notes == null) return;

    if (ManualRegisterNotes.usesFlatRegisterLayout(notes)) {
      _applyFlatRegisterNotes(data, record, notes);
      return;
    }

    final confirmand = _asMap(notes['confirmand']);
    final confirmation = _asMap(notes['confirmation']);
    final registry = _asMap(notes['registry']);
    final metadata = _asMap(notes['metadata']);
    final meta = _asMap(notes['meta']);
    final sponsor = _asMap(notes['sponsor']);

    if (confirmand != null) {
      data.personName = confirmand['fullName']?.toString() ?? record.name;
      if (confirmand['dateOfBirth'] != null) {
        data.birthDate = DateTime.tryParse(
          confirmand['dateOfBirth'].toString(),
        );
      }
      data.birthplace = confirmand['placeOfBirth']?.toString() ?? '';
    }

    _splitParentsIntoCertificate(notes['parents'], data);

    if (sponsor != null) {
      data.sponsorName = ManualRegisterNotes.fieldAny(sponsor, [
        'fullName',
        'name',
      ]);
    }

    if (confirmation != null) {
      data.ministerName = ManualRegisterNotes.fieldAny(confirmation, [
        'minister',
        'officiant',
      ]);
      if (confirmation['date'] != null) {
        data.sacramentDate = DateTime.tryParse(confirmation['date'].toString());
      }
      final place = confirmation['place']?.toString() ?? '';
      if (place.isNotEmpty) data.parishLocation = place;
    }

    _applyRegistryMap(data, registry);
    _applyMetaRegistry(data, metadata);
    _applyMetaRegistry(data, meta);
  }

  static void _extractMarriageData(
    CertificateData data,
    ParishRecord record,
    Map<String, dynamic>? notes,
  ) {
    data.parishName = record.parish ?? 'HOLY ROSARY PARISH';
    data.sacramentDate = record.date;
    data.issueDate ??= DateTime.now();

    if (notes == null) {
      if (record.name.trim().isNotEmpty) data.personName = record.name.trim();
      return;
    }

    // Flat marriage register (manual register + OCR) stores party names under
    // `groom.name`/`bride.name`, not the full-form `groom.fullName`. Handle it
    // explicitly so the couple resolves instead of rendering "null & null".
    if (ManualRegisterNotes.usesFlatMarriageRegisterLayout(notes)) {
      _applyFlatMarriageNotes(data, record, notes);
      return;
    }

    // Full marriage form JSON (nested groom/bride/marriage/witnesses).
    final groom = _asMap(notes['groom']);
    final bride = _asMap(notes['bride']);
    final marriage = _asMap(notes['marriage']);
    final witnesses = _asMap(notes['witnesses']);

    final groomName = groom?['fullName']?.toString() ?? '';
    final brideName = bride?['fullName']?.toString() ?? '';
    final combined = [
      groomName,
      brideName,
    ].where((s) => s.trim().isNotEmpty).join(' & ');
    if (combined.isNotEmpty) {
      data.personName = combined;
    } else if (record.name.trim().isNotEmpty) {
      data.personName = record.name.trim();
    }
    data.fatherName = groom?['father']?.toString() ?? '';
    data.motherName = groom?['mother']?.toString() ?? '';

    if (marriage != null) {
      data.ministerName = marriage['officiant']?.toString() ?? '';
      data.birthplace = marriage['place']?.toString() ?? '';
    }

    if (witnesses != null) {
      final w1 = witnesses['witness1']?.toString() ?? '';
      final w2 = witnesses['witness2']?.toString() ?? '';
      data.sponsorName = [w1, w2].where((s) => s.isNotEmpty).join(', ');
    }
  }

  /// Flat marriage register (manual + OCR) → certificate fields.
  static void _applyFlatMarriageNotes(
    CertificateData data,
    ParishRecord record,
    Map<String, dynamic> notes,
  ) {
    _applyParishFromRecord(data, record);

    final groom = _asMap(notes['groom']);
    final bride = _asMap(notes['bride']);

    final groomName = groom == null
        ? ''
        : ManualRegisterNotes.fieldAny(groom, ['name', 'fullName']);
    final brideName = bride == null
        ? ''
        : ManualRegisterNotes.fieldAny(bride, ['name', 'fullName']);
    final combined = [
      groomName,
      brideName,
    ].where((s) => s.isNotEmpty).join(' & ');
    if (combined.isNotEmpty) {
      data.personName = combined;
    } else {
      final summary = ManualRegisterNotes.fieldAny(notes, [
        'contractingParties',
      ]);
      data.personName = summary.isNotEmpty ? summary : record.name.trim();
    }

    // Groom's parents fill "Child of" (mother) and "and" (father); his date
    // and place of birth fill "born in" / "on the __ day of __".
    if (groom != null) {
      final parentsText = ManualRegisterNotes.fieldAny(groom, ['parents']);
      if (parentsText.isNotEmpty) {
        final surname = groomName.trim().isEmpty
            ? ''
            : groomName.trim().split(RegExp(r'\s+')).last;
        final p = motherAndFather(parentsText, familySurname: surname);
        data.motherName = p.mother;
        data.fatherName = p.father;
      } else {
        _splitParentsIntoCertificate(groom['parents'], data);
      }
      final birth = ManualRegisterNotes.fieldAny(groom, [
        'datesPlaceOfBirth',
        'placeAndDateOfBirth',
        'birth',
      ]);
      if (birth.isNotEmpty) {
        final split = splitPlaceAndDate(birth);
        data.birthDate = split.date ?? data.birthDate;
        if (split.place.isNotEmpty) data.birthplace = split.place;
      }
    }

    final sacramentText = ManualRegisterNotes.fieldAny(notes, [
      'dateOfMarriage',
      'date',
    ]);
    if (sacramentText.isNotEmpty) {
      data.sacramentDate =
          RegisterOcrParser.parseDate(sacramentText) ?? data.sacramentDate;
    }

    data.ministerName = ManualRegisterNotes.fieldAny(notes, [
      'minister',
      'officiant',
    ]);

    // Sponsors (Ninong/Ninang) — combine both parties' entries.
    final sponsors = <String>[];
    for (final party in [groom, bride]) {
      if (party == null) continue;
      final s = ManualRegisterNotes.fieldAny(party, [
        'sponsors',
        'sponsorsOfMarriage',
      ]);
      if (s.isNotEmpty) sponsors.add(s);
    }
    data.sponsorName = sponsors.join(', ');

    data.registryVolume = ManualRegisterNotes.fieldAny(notes, [
      'volNo',
      'volume',
      'vol',
    ]);
    data.registrySeries = ManualRegisterNotes.fieldAny(notes, [
      'seriesNo',
      'series',
    ]);
    data.registryPage = ManualRegisterNotes.fieldAny(notes, [
      'lineNo',
      'pageNo',
      'page',
    ]);
  }

  static void _extractFuneralData(
    CertificateData data,
    ParishRecord record,
    Map<String, dynamic>? notes,
  ) {
    data.personName = record.name;
    data.parishName = record.parish ?? 'HOLY ROSARY PARISH';
    data.sacramentDate = record.date;

    if (notes != null) {
      final deceased = notes['deceased'] as Map<String, dynamic>?;
      final funeral = notes['funeral'] as Map<String, dynamic>?;

      if (deceased != null) {
        if (deceased['dateOfBirth'] != null) {
          data.birthDate = DateTime.tryParse(
            deceased['dateOfBirth'].toString(),
          );
        }
        data.birthplace = deceased['placeOfBirth']?.toString() ?? '';
      }

      if (funeral != null) {
        data.ministerName = funeral['minister']?.toString() ?? '';
        data.birthplace = funeral['place']?.toString() ?? data.birthplace;
      }
    }
  }
}

/// Main certificate template screen
class CertificateTemplateScreen extends ConsumerStatefulWidget {
  final String recordId;
  final RecordType recordType;

  const CertificateTemplateScreen({
    super.key,
    required this.recordId,
    required this.recordType,
  });

  @override
  ConsumerState<CertificateTemplateScreen> createState() =>
      _CertificateTemplateScreenState();
}

class _CertificateTemplateScreenState
    extends ConsumerState<CertificateTemplateScreen> {
  late CertificateData _certificateData;

  /// Marriage certificates list the mother on "Child of" and the father on
  /// the "and" line, as the parish marriage register does.
  bool get _motherFirst => widget.recordType == RecordType.marriage;
  bool _isLoading = true;
  bool _isGenerating = false;
  bool _recordApplied = false;
  ParishRecord? _record;

  /// Good Moral and No Record certificates are typed letters on A4 bond
  /// paper (see letter_certificate.dart), not values printed on a form.
  bool get _isLetter =>
      widget.recordType == RecordType.goodMoral ||
      widget.recordType == RecordType.noRecord;

  LetterCertificate? get _letter {
    final r = _record;
    return _isLetter && r != null ? LetterCertificate.fromRecord(r) : null;
  }

  double get _pageAspect => _isLetter
      ? PdfPageFormat.a4.width / PdfPageFormat.a4.height
      : certificatePageFormat.width / certificatePageFormat.height;

  Widget _buildPage() {
    if (!_isLetter) return _buildCertificatePreview();
    final letter = _letter;
    if (letter == null) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(child: Text('Record not found')),
      );
    }
    return LetterCertificatePage(certificate: letter);
  }

  // Controllers
  late final TextEditingController _nameCtrl;
  late final TextEditingController _fatherCtrl;
  late final TextEditingController _motherCtrl;
  late final TextEditingController _birthplaceCtrl;
  late final TextEditingController _ministerCtrl;
  late final TextEditingController _sponsorCtrl;
  late final TextEditingController _parishCtrl;
  late final TextEditingController _parishLocationCtrl;
  late final TextEditingController _bookCtrl;
  late final TextEditingController _pageCtrl;
  late final TextEditingController _volumeCtrl;
  late final TextEditingController _seriesCtrl;
  late final TextEditingController _priestCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _certificateData = CertificateData();
    _initControllers();
    _loadRecordData();
  }

  void _applyRecordToForm(ParishRecord record, {bool fromSearch = false}) {
    final decodedNotes = ManualRegisterNotes.tryDecode(record.notes);
    final type = fromSearch ? record.type : widget.recordType;

    CertificateData extracted;
    switch (type) {
      case RecordType.baptism:
        extracted = CertificateData();
        CertificateData._extractBaptismData(extracted, record, decodedNotes);
        break;
      case RecordType.confirmation:
        extracted = CertificateData();
        CertificateData._extractConfirmationData(
          extracted,
          record,
          decodedNotes,
        );
        break;
      case RecordType.marriage:
        extracted = CertificateData();
        CertificateData._extractMarriageData(extracted, record, decodedNotes);
        break;
      case RecordType.funeral:
        extracted = CertificateData();
        CertificateData._extractFuneralData(extracted, record, decodedNotes);
        break;
      case RecordType.goodMoral:
        extracted = CertificateData();
        CertificateData._extractGoodMoralData(extracted, record, decodedNotes);
        break;
      case RecordType.noRecord:
        extracted = CertificateData();
        CertificateData._extractGoodMoralData(
          extracted,
          record,
          decodedNotes,
          key: 'noRecord',
        );
        break;
    }

    setState(() {
      _record = record;
      _certificateData = extracted;
      _updateControllersFromData();
      _recordApplied = true;
    });
  }

  void _updateControllersFromData() {
    _nameCtrl.text = _certificateData.personName;
    _fatherCtrl.text = _certificateData.fatherName;
    _motherCtrl.text = _certificateData.motherName;
    _birthplaceCtrl.text = _certificateData.birthplace;
    _ministerCtrl.text = _certificateData.ministerName;
    _sponsorCtrl.text = _certificateData.sponsorName;
    _parishCtrl.text = _certificateData.parishName;
    _parishLocationCtrl.text = _certificateData.parishLocation;
    _bookCtrl.text = _certificateData.registryBook;
    _pageCtrl.text = _certificateData.registryPage;
    _volumeCtrl.text = _certificateData.registryVolume;
    _seriesCtrl.text = _certificateData.registrySeries;
    _priestCtrl.text = _certificateData.parishPriest;
    _notesCtrl.text = _certificateData.notes ?? '';
  }

  void _initControllers() {
    _nameCtrl = TextEditingController();
    _fatherCtrl = TextEditingController();
    _motherCtrl = TextEditingController();
    _birthplaceCtrl = TextEditingController();
    _ministerCtrl = TextEditingController();
    _sponsorCtrl = TextEditingController();
    _parishCtrl = TextEditingController(text: 'HOLY ROSARY PARISH');
    _parishLocationCtrl = TextEditingController(text: 'Oroquieta City');
    _bookCtrl = TextEditingController();
    _pageCtrl = TextEditingController();
    _volumeCtrl = TextEditingController();
    _seriesCtrl = TextEditingController();
    _priestCtrl = TextEditingController(text: 'FR. DANILO B. RUDINAS');
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _fatherCtrl.dispose();
    _motherCtrl.dispose();
    _birthplaceCtrl.dispose();
    _ministerCtrl.dispose();
    _sponsorCtrl.dispose();
    _parishCtrl.dispose();
    _parishLocationCtrl.dispose();
    _bookCtrl.dispose();
    _pageCtrl.dispose();
    _volumeCtrl.dispose();
    _seriesCtrl.dispose();
    _priestCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _updateDataFromControllers() {
    _certificateData.personName = _nameCtrl.text;
    _certificateData.fatherName = _fatherCtrl.text;
    _certificateData.motherName = _motherCtrl.text;
    _certificateData.birthplace = _birthplaceCtrl.text;
    _certificateData.ministerName = _ministerCtrl.text;
    _certificateData.sponsorName = _sponsorCtrl.text;
    _certificateData.parishName = _parishCtrl.text;
    _certificateData.parishLocation = _parishLocationCtrl.text;
    _certificateData.registryBook = _bookCtrl.text;
    _certificateData.registryPage = _pageCtrl.text;
    _certificateData.registryVolume = _volumeCtrl.text;
    _certificateData.registrySeries = _seriesCtrl.text;
    _certificateData.parishPriest = _priestCtrl.text;
    _certificateData.notes = _notesCtrl.text.isEmpty ? null : _notesCtrl.text;
  }

  ParishRecord? _findRecord(List<ParishRecord> records) {
    final byId = records.where((r) => r.id == widget.recordId);
    final typed = byId.where((r) => r.type == widget.recordType);
    return typed.firstOrNull ?? byId.firstOrNull;
  }

  Future<void> _loadRecordData() async {
    try {
      var records = ref.read(recordsProvider);
      var record = _findRecord(records);
      if (record == null) {
        // Refreshing the shared list can be rejected when this screen mounts
        // during the widget-tree build (Riverpod forbids mutating a provider
        // then). Isolate that failure so it can't skip the getById fallback
        // below — which is what actually resolves the record when we arrive
        // from a screen that never populated recordsProvider.
        try {
          await ref.read(recordsProvider.notifier).load();
          records = ref.read(recordsProvider);
          record = _findRecord(records);
        } catch (e, st) {
          debugPrint('Certificate provider load skipped: $e\n$st');
        }
      }

      // Fallback: the in-memory list can be empty when we arrive from a screen
      // that never populates recordsProvider (e.g. the admin Records page loads
      // into its own local list). Resolve the record directly by id so the form
      // still fills in.
      if (record == null && widget.recordId.trim().isNotEmpty) {
        record = await ref
            .read(recordsRepositoryProvider)
            .getById(widget.recordId);
      }

      if (record != null && mounted) {
        _applyRecordToForm(record);
      }
    } catch (e, st) {
      debugPrint('Certificate load failed: $e\n$st');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String get _certificateTitle {
    switch (widget.recordType) {
      case RecordType.baptism:
        return 'Certificate of Baptism';
      case RecordType.confirmation:
        return 'Certificate of Confirmation';
      case RecordType.marriage:
        return 'Certificate of Marriage';
      case RecordType.funeral:
        return 'Certificate of Funeral Rites';
      case RecordType.goodMoral:
        return 'Certificate of Good Moral Character';
      case RecordType.noRecord:
        return 'Certificate of No Record';
    }
  }

  Future<void> _generateAndPrint() async {
    _updateDataFromControllers();

    setState(() => _isGenerating = true);

    try {
      final pdf = await _generatePdf();

      if (!mounted) return;

      // Show print preview
      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name:
            '${_certificateTitle.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating certificate: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _saveAsPdf() async {
    _updateDataFromControllers();

    setState(() => _isGenerating = true);

    try {
      final pdf = await _generatePdf();
      final fileName =
          '${_certificateTitle.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';

      await Printing.sharePdf(bytes: await pdf.save(), filename: fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Certificate downloaded successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving certificate: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  /// The form these certificates are printed on.
  CertificateLayout get _layout => CertificateLayout.of(widget.recordType);

  /// The text for each blank on the form, from the certificate data.
  Map<String, String> _slotValues(CertificateData d) {
    if (widget.recordType == RecordType.goodMoral) return _goodMoralValues(d);
    if (widget.recordType == RecordType.noRecord) {
      return {
        'name': d.personName.toUpperCase(),
        'residentOf': d.residentOf,
        'dated': d.issueDate == null
            ? ''
            : 'Dated: ${_formatDate(d.issueDate)}',
        'priest': d.parishPriest.toUpperCase(),
      };
    }
    String day(DateTime? t) => t == null ? '' : _ordinalDay(t.day);
    String month(DateTime? t) => t == null ? '' : DateFormat('MMMM').format(t);
    String year(DateTime? t) => t?.year.toString() ?? '';

    final values = <String, String>{
      'name': d.personName.toUpperCase(),
      'childOf': _motherFirst ? d.motherName : d.fatherName,
      'and': _motherFirst ? d.fatherName : d.motherName,
      'bornIn': d.birthplace,
      'birthDay': day(d.birthDate),
      'birthMonth': month(d.birthDate),
      'birthYear': year(d.birthDate),
      'sacDay': day(d.sacramentDate),
      'sacMonth': month(d.sacramentDate),
      'sacYear': year(d.sacramentDate),
      'minister': d.ministerName.toUpperCase(),
      'dated': _formatDate(d.issueDate),
      'page': d.registryPage,
      'volume': d.registryVolume,
      'series': d.registrySeries,
      'priest': d.parishPriest.toUpperCase(),
    };

    // Sponsors fill as many lines as the form has (three on the baptismal
    // form), keeping each name whole on one line.
    final lines = _layout.sponsorLines;
    final names = d.sponsorName
        .split(RegExp(r'\s*[;,\n]\s*|\s+&\s+|\s+and\s+', caseSensitive: false))
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (lines <= 1 || names.length <= 1) {
      values['sponsor1'] = names.isEmpty
          ? d.sponsorName.trim()
          : names.join(', ');
    } else {
      final per = (names.length / lines).ceil();
      for (var i = 0; i < lines; i++) {
        final chunk = names.skip(i * per).take(per).toList();
        values['sponsor${i + 1}'] = chunk.join(', ');
      }
    }
    return values;
  }

  /// The Good Moral form's blanks. The purpose runs on from its short blank
  /// onto the full-width line below it when it does not fit.
  Map<String, String> _goodMoralValues(CertificateData d) {
    final words = d.purpose.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final first = StringBuffer();
    final rest = StringBuffer();
    for (final w in words) {
      final target = rest.isEmpty && first.length + w.length + 1 <= 26
          ? first
          : rest;
      if (target.isNotEmpty) target.write(' ');
      target.write(w);
    }
    return {
      'name': d.personName.toUpperCase(),
      'residentOf': d.residentOf,
      'personOf': d.personOf,
      'knownAs': d.knownAs,
      'fitFor': first.toString(),
      'fitFor2': rest.toString(),
      'dated': d.issueDate == null ? '' : 'Dated: ${_formatDate(d.issueDate)}',
      'priest': d.parishPriest.toUpperCase(),
    };
  }

  /// Blanks whose value is centred on the line rather than written from its
  /// start: the short date parts and the priest's signature line.
  static const _centredSlots = {
    'birthDay',
    'birthMonth',
    'birthYear',
    'sacDay',
    'sacMonth',
    'sacYear',
    'priest',
  };

  /// Value text size as a fraction of the page height (about 10 pt on A5).
  static const double _valueFontFraction = 0.0175;

  /// On forms with a single sponsor line, four or more sponsors shrunk onto
  /// one line were unreadable, so that line wraps onto a second line above it
  /// (the blank space under "The Sponsor(s) being") at a slightly smaller size.
  static const double _wrappedFontScale = 0.85;
  bool _wrapsOnTwoLines(String key, CertificateLayout layout) =>
      key == 'sponsor1' && layout.sponsorLines == 1;

  Future<pw.Document> _generatePdf() async {
    if (_isLetter) {
      final letter = _letter;
      if (letter == null) throw StateError('Record not found');
      return letter.buildPdf();
    }
    final pdf = pw.Document();
    final bold = pw.Font.helveticaBold();
    final layout = _layout;
    final background = pw.MemoryImage(
      (await rootBundle.load(layout.background)).buffer.asUint8List(),
    );
    final values = _slotValues(_certificateData);
    final format = certificatePageFormat;
    final pageW = format.width;
    final pageH = format.height;
    final fontSize = pageH * _valueFontFraction;
    final boxH = fontSize * 1.3;

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.SizedBox(
          width: pageW,
          height: pageH,
          child: pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.Image(background, fit: pw.BoxFit.fill),
              ),
              if (layout.marks[_certificateData.title] case final m?)
                pw.Positioned(
                  left: m.x0 * pageW,
                  top: m.y0 * pageH,
                  child: pw.Container(
                    width: (m.x1 - m.x0) * pageW,
                    height: (m.y1 - m.y0) * pageH,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 0.9),
                      borderRadius: pw.BorderRadius.all(
                        pw.Radius.elliptical(
                          (m.x1 - m.x0) * pageW / 2,
                          (m.y1 - m.y0) * pageH / 2,
                        ),
                      ),
                    ),
                  ),
                ),
              for (final entry in layout.slots.entries)
                if ((values[entry.key] ?? '').trim().isNotEmpty)
                  if (_wrapsOnTwoLines(entry.key, layout))
                    pw.Positioned(
                      left: entry.value.x0 * pageW + 2,
                      top: entry.value.y * pageH - 2 * boxH - pageH * 0.003,
                      child: pw.SizedBox(
                        width: (entry.value.x1 - entry.value.x0) * pageW - 4,
                        height: 2 * boxH,
                        child: pw.Align(
                          alignment: pw.Alignment.bottomLeft,
                          child: pw.Text(
                            values[entry.key]!.trim(),
                            maxLines: 2,
                            style: pw.TextStyle(
                              font: bold,
                              fontSize: fontSize * _wrappedFontScale,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    pw.Positioned(
                      left: entry.value.x0 * pageW + 2,
                      top: entry.value.y * pageH - boxH - pageH * 0.003,
                      child: pw.SizedBox(
                        width: (entry.value.x1 - entry.value.x0) * pageW - 4,
                        height: boxH,
                        child: pw.FittedBox(
                          fit: pw.BoxFit.scaleDown,
                          alignment: _centredSlots.contains(entry.key)
                              ? pw.Alignment.bottomCenter
                              : pw.Alignment.bottomLeft,
                          child: pw.Text(
                            values[entry.key]!.trim(),
                            style: pw.TextStyle(font: bold, fontSize: fontSize),
                          ),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );

    return pdf;
  }

  String _ordinalDay(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    switch (day % 10) {
      case 1:
        return '${day}st';
      case 2:
        return '${day}nd';
      case 3:
        return '${day}rd';
      default:
        return '${day}th';
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('MMMM d, yyyy').format(date);
  }

  bool _isAdminRecordsContext(BuildContext context) {
    return GoRouterState.of(context).uri.path.startsWith('/admin/records');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final showPrint = !_isAdminRecordsContext(context);

    ref.listen<List<ParishRecord>>(recordsProvider, (previous, next) {
      if (_recordApplied || widget.recordId.isEmpty || _isLoading) return;
      final record = _findRecord(next);
      if (record != null && mounted) {
        _applyRecordToForm(record);
      }
    });

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(_certificateTitle),
        actions: [
          if (_isGenerating)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            if (showPrint)
              IconButton(
                icon: const Icon(Icons.print),
                tooltip: 'Print',
                onPressed: _generateAndPrint,
              ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Save as PDF',
              onPressed: _saveAsPdf,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          // Preview only: certificate details come from the parish record
          // and are not edited here.
          : Container(
              color: Colors.grey[200],
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: colorScheme.surface,
                    child: Row(
                      children: [
                        Icon(Icons.preview, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Certificate Preview',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: CertificateZoomView(
                      aspectRatio: _pageAspect,
                      pageBuilder: (_) => _buildPage(),
                      onFullscreen: _openFullscreenPreview,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// Full-screen certificate preview with the same zoom controls.
  void _openFullscreenPreview() {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (ctx, _, _) => Scaffold(
          backgroundColor: const Color(0xFF1F2937),
          body: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.of(ctx).maybePop(),
            },
            child: Focus(
              autofocus: true,
              child: SafeArea(
                child: CertificateZoomView(
                  aspectRatio: _pageAspect,
                  pageBuilder: (_) => _buildPage(),
                  fullscreen: true,
                  onFullscreen: () => Navigator.of(ctx).maybePop(),
                ),
              ),
            ),
          ),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Widget _buildCertificatePreview() {
    _updateDataFromControllers();
    final layout = _layout;
    final values = _slotValues(_certificateData);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final fontSize = h * _valueFontFraction;
        final boxH = fontSize * 1.3;
        return Stack(
          children: [
            Positioned.fill(
              child: Image.asset(layout.background, fit: BoxFit.fill),
            ),
            if (layout.marks[_certificateData.title] case final m?)
              Positioned(
                left: m.x0 * w,
                top: m.y0 * h,
                width: (m.x1 - m.x0) * w,
                height: (m.y1 - m.y0) * h,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black, width: 1.2),
                    borderRadius: BorderRadius.all(
                      Radius.elliptical(
                        (m.x1 - m.x0) * w / 2,
                        (m.y1 - m.y0) * h / 2,
                      ),
                    ),
                  ),
                ),
              ),
            for (final entry in layout.slots.entries)
              if ((values[entry.key] ?? '').trim().isNotEmpty)
                if (_wrapsOnTwoLines(entry.key, layout))
                  Positioned(
                    left: entry.value.x0 * w + 2,
                    top: entry.value.y * h - 2 * boxH - h * 0.003,
                    width: (entry.value.x1 - entry.value.x0) * w - 4,
                    height: 2 * boxH,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        values[entry.key]!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: fontSize * _wrappedFontScale,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          height: 1.15,
                        ),
                      ),
                    ),
                  )
                else
                  Positioned(
                    left: entry.value.x0 * w + 2,
                    top: entry.value.y * h - boxH - h * 0.003,
                    width: (entry.value.x1 - entry.value.x0) * w - 4,
                    height: boxH,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: _centredSlots.contains(entry.key)
                          ? Alignment.bottomCenter
                          : Alignment.bottomLeft,
                      child: Text(
                        values[entry.key]!.trim(),
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }
}
