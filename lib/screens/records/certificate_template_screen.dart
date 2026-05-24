import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/record.dart';
import '../../providers/records_provider.dart';
import '../../services/register_ocr_parser.dart';
import '../../utils/manual_register_notes.dart';

/// Japan Post standard postcard (郵便ハガキ): 100 × 148 mm, portrait.
final _japanesePostcardFormat = PdfPageFormat(
  100 * PdfPageFormat.mm,
  148 * PdfPageFormat.mm,
);

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
    }

    return data;
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

  static void _applyParishFromRecord(CertificateData data, ParishRecord record) {
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

    final slashParts =
        trimmed.split('/').map((s) => s.trim()).where((s) => s.isNotEmpty);
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
        data.sacramentDate = DateTime.tryParse(
          confirmation['date'].toString(),
        );
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

    if (notes != null) {
      final groom = notes['groom'] as Map<String, dynamic>?;
      final bride = notes['bride'] as Map<String, dynamic>?;
      final marriage = notes['marriage'] as Map<String, dynamic>?;
      final witnesses = notes['witnesses'] as Map<String, dynamic>?;

      if (groom != null && bride != null) {
        data.personName = '${groom['fullName']} & ${bride['fullName']}';
        data.fatherName = groom['father']?.toString() ?? '';
        data.motherName = groom['mother']?.toString() ?? '';
      }

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
  bool _isLoading = true;
  bool _isGenerating = false;
  bool _recordApplied = false;
  final _formKey = GlobalKey<FormState>();

  // Auto-fill search
  List<ParishRecord> _searchResults = [];
  bool _showSuggestions = false;
  final FocusNode _nameFocusNode = FocusNode();

  Uint8List? _archdioceseLogoBytes;
  Uint8List? _parishLogoBytes;

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
    _setupNameListener();
    _loadRecordData();
    _loadCertificateLogos();
  }

  Future<void> _loadCertificateLogos() async {
    if (!_usesCertificateLogos) return;
    try {
      final archdiocese = await rootBundle.load('assets/images/image1.png');
      final parish = await rootBundle.load('assets/images/image2.png');
      if (!mounted) return;
      setState(() {
        _archdioceseLogoBytes = archdiocese.buffer.asUint8List();
        _parishLogoBytes = parish.buffer.asUint8List();
      });
    } catch (_) {
      // Logos optional — header falls back to text-only.
    }
  }

  void _setupNameListener() {
    _nameCtrl.addListener(() {
      final query = _nameCtrl.text.trim();
      if (query.length >= 2) {
        _searchRecords(query);
      } else {
        setState(() {
          _searchResults = [];
          _showSuggestions = false;
        });
      }
    });

    _nameFocusNode.addListener(() {
      if (!_nameFocusNode.hasFocus) {
        setState(() => _showSuggestions = false);
      }
    });
  }

  void _searchRecords(String query) {
    final records = ref.read(recordsProvider);
    final lowerQuery = query.toLowerCase();

    final matches = records
        .where((r) => r.type == widget.recordType)
        .where((r) => r.name.toLowerCase().contains(lowerQuery))
        .take(5)
        .toList();

    setState(() {
      _searchResults = matches;
      _showSuggestions = matches.isNotEmpty;
    });
  }

  void _fillFromRecord(ParishRecord record) {
    _applyRecordToForm(record, fromSearch: true);
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
    }

    setState(() {
      _certificateData = extracted;
      _updateControllersFromData();
      _showSuggestions = false;
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
    _nameFocusNode.dispose();
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
      if (_findRecord(records) == null) {
        await ref.read(recordsProvider.notifier).load();
        records = ref.read(recordsProvider);
      }

      final record = _findRecord(records);
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
    }
  }

  String get _sacramentLabel {
    switch (widget.recordType) {
      case RecordType.baptism:
        return 'Was Baptized';
      case RecordType.confirmation:
        return 'Was Confirmed';
      case RecordType.marriage:
        return 'Were United in Holy Matrimony';
      case RecordType.funeral:
        return 'Funeral Rites Were Celebrated';
    }
  }

  bool get _usesCertificateLogos =>
      widget.recordType == RecordType.baptism ||
      widget.recordType == RecordType.confirmation;

  String get _registerLabel {
    switch (widget.recordType) {
      case RecordType.baptism:
        return 'Baptismal';
      case RecordType.confirmation:
        return 'Confirmation';
      case RecordType.marriage:
        return 'Marriage';
      case RecordType.funeral:
        return 'Funeral';
    }
  }

  Future<void> _selectDate(BuildContext context, bool isBirthDate) async {
    final initialDate = isBirthDate
        ? (_certificateData.birthDate ?? DateTime.now())
        : (_certificateData.sacramentDate ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        if (isBirthDate) {
          _certificateData.birthDate = picked;
        } else {
          _certificateData.sacramentDate = picked;
        }
      });
    }
  }

  Future<void> _selectIssueDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _certificateData.issueDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        _certificateData.issueDate = picked;
      });
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

  Future<pw.Document> _generatePdf() async {
    final pdf = pw.Document();

    final ttfRegular = pw.Font.helvetica();
    final ttfBold = pw.Font.helveticaBold();
    final ttfItalic = pw.Font.helveticaOblique();

    pw.MemoryImage? archdioceseLogo;
    pw.MemoryImage? parishLogo;
    if (_usesCertificateLogos) {
      try {
        final archBytes = _archdioceseLogoBytes ??
            (await rootBundle.load('assets/images/image1.png'))
                .buffer
                .asUint8List();
        final parishBytes = _parishLogoBytes ??
            (await rootBundle.load('assets/images/image2.png'))
                .buffer
                .asUint8List();
        if (archBytes.isNotEmpty) {
          archdioceseLogo = pw.MemoryImage(archBytes);
        }
        if (parishBytes.isNotEmpty) {
          parishLogo = pw.MemoryImage(parishBytes);
        }
      } catch (_) {}
    }

    pdf.addPage(
      pw.Page(
        pageFormat: _japanesePostcardFormat,
        margin: const pw.EdgeInsets.all(14),
        build: (context) => _buildCertificatePage(
          ttfRegular,
          ttfBold,
          ttfItalic,
          archdioceseLogo: archdioceseLogo,
          parishLogo: parishLogo,
        ),
      ),
    );

    return pdf;
  }

  pw.Widget _buildCertificatePage(
    pw.Font regular,
    pw.Font bold,
    pw.Font italic, {
    pw.MemoryImage? archdioceseLogo,
    pw.MemoryImage? parishLogo,
  }) {
    final headerSmall = pw.TextStyle(font: regular, fontSize: 8);
    final headerStrong = pw.TextStyle(font: bold, fontSize: 12);
    final certifyBold = pw.TextStyle(font: bold, fontSize: 8);
    final bodyFontSize = 8.0;

    pw.Widget parishHeaderBlock() {
      return pw.Center(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text('ARCHDIOCESE OF OZAMIS', style: headerSmall),
            pw.SizedBox(height: 2),
            pw.Text(
              _certificateData.parishName.toUpperCase(),
              style: headerStrong,
              textAlign: pw.TextAlign.center,
            ),
            pw.Text(
              _certificateData.parishLocation,
              style: headerSmall,
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      );
    }

    pw.Widget titleWithLogosBlock() {
      final titleTextStyle = pw.TextStyle(
        font: bold,
        fontSize: widget.recordType == RecordType.confirmation ? 16 : 14,
      );
      final titleWidget = pw.Text(
        _certificateTitle,
        style: titleTextStyle,
        textAlign: pw.TextAlign.center,
      );

      if (archdioceseLogo != null && parishLogo != null) {
        const logoBox = 44.0;
        const titleWidth = 168.0;

        pw.Widget logoCell(pw.MemoryImage image) => pw.SizedBox(
              width: logoBox,
              height: logoBox,
              child: pw.Center(
                child: pw.Image(image, fit: pw.BoxFit.contain),
              ),
            );

        return pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: logoCell(archdioceseLogo),
              ),
            ),
            pw.SizedBox(
              width: titleWidth,
              child: pw.Center(child: titleWidget),
            ),
            pw.Expanded(
              child: pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: logoCell(parishLogo),
              ),
            ),
          ],
        );
      }

      return pw.Center(child: titleWidget);
    }

    pw.Widget watermark() {
      return pw.Positioned.fill(
        child: pw.Center(
          child: pw.Opacity(
            opacity: 0.03,
            child: pw.Transform.scale(
              scale: 6.0,
              child: _buildCross(thick: false),
            ),
          ),
        ),
      );
    }

    pw.Widget signatureBlock() {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          if (widget.recordType == RecordType.confirmation)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(
                'NOTE: FOR MARRIAGE PURPOSE',
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 7,
                  color: PdfColors.red,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Rev.', style: pw.TextStyle(font: italic, fontSize: 8)),
              pw.SizedBox(width: 4),
              pw.Container(
                width: 110,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.black, width: 1),
                  ),
                ),
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text(
                  _certificateData.parishPriest.toUpperCase(),
                  style: pw.TextStyle(font: bold, fontSize: 8),
                  textAlign: pw.TextAlign.center,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Parish Priest / VICAR',
            style: pw.TextStyle(font: bold, fontSize: 7),
            textAlign: pw.TextAlign.right,
          ),
        ],
      );
    }

    return pw.Stack(
      children: [
        watermark(),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 1.5),
          ),
          padding: const pw.EdgeInsets.all(5),
          child: pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1),
            ),
            padding: const pw.EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                parishHeaderBlock(),
                pw.SizedBox(height: 6),
                titleWithLogosBlock(),
                pw.SizedBox(height: 8),

                pw.Center(
                  child: pw.Text(
                    'This is to Certify:',
                    style: certifyBold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 6),

                _buildCertRow(
                  'That',
                  _certificateData.personName.toUpperCase(),
                  regular,
                  bold,
                  fontSize: bodyFontSize,
                ),
                pw.SizedBox(height: 4),
                _buildCertRow(
                  'Child of',
                  _certificateData.fatherName,
                  regular,
                  bold,
                  fontSize: bodyFontSize,
                ),
                pw.SizedBox(height: 2),
                _buildCertRow(
                  'and',
                  _certificateData.motherName,
                  regular,
                  bold,
                  fontSize: bodyFontSize,
                ),
                pw.SizedBox(height: 4),
                _buildCertRow(
                  'born in',
                  _certificateData.birthplace,
                  regular,
                  bold,
                  fontSize: bodyFontSize,
                ),
                pw.SizedBox(height: 4),

                _buildPdfDateRow(
                  regular,
                  bold,
                  _certificateData.birthDate,
                  bodyFontSize,
                ),

                pw.SizedBox(height: 10),

                pw.Center(
                  child: pw.Text(
                    _sacramentLabel.toUpperCase(),
                    style: pw.TextStyle(font: bold, fontSize: 11),
                  ),
                ),
                pw.SizedBox(height: 8),

                _buildPdfDateRow(
                  regular,
                  bold,
                  _certificateData.sacramentDate,
                  bodyFontSize,
                ),

                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    'According to the Rite of the Roman Catholic Church',
                    style: certifyBold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 6),

                _buildCertRow(
                  'by the Rev. Fr.',
                  _certificateData.ministerName.toUpperCase(),
                  regular,
                  bold,
                  fontSize: bodyFontSize,
                ),
                pw.SizedBox(height: 4),

                _buildCertRow(
                  'The Sponsor(s) being',
                  _certificateData.sponsorName,
                  regular,
                  bold,
                  labelWidth: 72,
                  fontSize: bodyFontSize,
                  labelFont: italic,
                ),

                pw.Spacer(),

                pw.Center(
                  child: pw.Text(
                    'as appears from the $_registerLabel Register of this Church',
                    style: certifyBold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 6),

                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildRegistryRow(
                          'Dated :',
                          _formatDate(_certificateData.issueDate),
                          regular,
                          bold,
                        ),
                        _buildRegistryRow(
                          'Page  :',
                          _certificateData.registryPage,
                          regular,
                          bold,
                        ),
                        _buildRegistryRow(
                          'Vol.  :',
                          _certificateData.registryVolume,
                          regular,
                          bold,
                        ),
                        _buildRegistryRow(
                          'Series :',
                          _certificateData.registrySeries,
                          regular,
                          bold,
                        ),
                      ],
                    ),
                    pw.Spacer(),
                    pw.SizedBox(width: 150, child: signatureBlock()),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildCross({bool thick = true}) {
    return pw.Container(
      width: thick ? 30 : 50,
      height: thick ? 40 : 65,
      child: pw.CustomPaint(
        painter: (canvas, size) {
          final sw = size.x;
          final sh = size.y;
          final midX = sw / 2;

          if (thick) {
            canvas.moveTo(midX - 4, 0);
            canvas.lineTo(midX + 4, 0);
            canvas.lineTo(midX + 4, sh * 0.3);
            canvas.lineTo(sw, sh * 0.3);
            canvas.lineTo(sw, sh * 0.45);
            canvas.lineTo(midX + 4, sh * 0.45);
            canvas.lineTo(midX + 4, sh);
            canvas.lineTo(midX - 4, sh);
            canvas.lineTo(midX - 4, sh * 0.45);
            canvas.lineTo(0, sh * 0.45);
            canvas.lineTo(0, sh * 0.3);
            canvas.lineTo(midX - 4, sh * 0.3);
            canvas.lineTo(midX - 4, 0);
            canvas.setStrokeColor(PdfColors.black);
            canvas.setLineWidth(1);
            canvas.strokePath();
          } else {
            // Outline cross style as seen in confirmation photo
            final strokeWidth = 1.0;
            final barWidth = sw * 0.25;

            // Vertical bar
            canvas.drawRect(midX - barWidth / 2, 0, barWidth, sh);
            // Horizontal bar
            canvas.drawRect(0, sh * 0.25, sw, sh * 0.2);

            canvas.setStrokeColor(PdfColors.black);
            canvas.setLineWidth(strokeWidth);
            canvas.strokePath();
          }
        },
      ),
    );
  }

  static const double _formLabelWidth = 52;

  pw.Widget _buildUnderlinedText(
    String text, {
    required double width,
    required pw.Font font,
    double fontSize = 8,
    pw.TextAlign align = pw.TextAlign.center,
  }) {
    return pw.Container(
      width: width,
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.black, width: 0.8),
        ),
      ),
      padding: const pw.EdgeInsets.only(bottom: 2),
      alignment: pw.Alignment.bottomCenter,
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: fontSize),
        textAlign: align,
      ),
    );
  }

  pw.Widget _buildPdfDateRow(
    pw.Font regular,
    pw.Font bold,
    DateTime? date,
    double fontSize,
  ) {
    final day = date != null ? _ordinalDay(date.day) : '';
    final month = date != null ? DateFormat('MMMM').format(date) : '';
    final year = date?.year.toString() ?? '';

    pw.Widget plain(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(right: 4, bottom: 2),
          child: pw.Text(
            text,
            style: pw.TextStyle(font: regular, fontSize: fontSize),
          ),
        );

    return pw.Center(
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          plain('on the'),
          _buildUnderlinedText(day, width: 34, font: bold, fontSize: fontSize),
          plain('day of'),
          _buildUnderlinedText(
            month,
            width: 78,
            font: bold,
            fontSize: fontSize,
          ),
          plain(','),
          _buildUnderlinedText(year, width: 40, font: bold, fontSize: fontSize),
        ],
      ),
    );
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

  pw.Widget _buildCertRow(
    String label,
    String value,
    pw.Font regular,
    pw.Font bold, {
    double labelWidth = _formLabelWidth,
    double fontSize = 8,
    pw.Font? labelFont,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.SizedBox(
          width: labelWidth,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              font: labelFont ?? regular,
              fontSize: fontSize,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.black, width: 0.8),
              ),
            ),
            padding: const pw.EdgeInsets.only(bottom: 2, left: 2),
            child: pw.Text(
              value,
              style: pw.TextStyle(font: bold, fontSize: fontSize),
              textAlign: pw.TextAlign.left,
              maxLines: 2,
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildRegistryRow(
    String label,
    String value,
    pw.Font regular,
    pw.Font bold,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.SizedBox(
            width: 38,
            child: pw.Text(
              label,
              style: pw.TextStyle(font: regular, fontSize: 7),
            ),
          ),
          pw.SizedBox(width: 3),
          pw.Container(
            width: 72,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.black, width: 0.8),
              ),
            ),
            child: pw.Text(
              value,
              style: pw.TextStyle(font: bold, fontSize: 7),
              textAlign: pw.TextAlign.left,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildCoatOfArms() {
    // Simple coat of arms representation (shield shape)
    return pw.Container(
      width: 40,
      height: 50,
      child: pw.CustomPaint(
        painter: (canvas, size) {
          final centerX = size.x / 2;
          final topY = 5.0;
          final bottomY = size.y - 5;
          final width = size.x - 10;
          final halfWidth = width / 2;

          // Draw shield outline
          final path = [
            [centerX - halfWidth, topY + 8], // Top left
            [centerX - halfWidth, topY + 15], // Upper left side
            [centerX - halfWidth * 0.7, bottomY - 12], // Lower left side
            [centerX, bottomY], // Bottom point
            [centerX + halfWidth * 0.7, bottomY - 12], // Lower right side
            [centerX + halfWidth, topY + 15], // Upper right side
            [centerX + halfWidth, topY + 8], // Top right
          ];

          // Draw shield border
          for (int i = 0; i < path.length - 1; i++) {
            canvas.drawLine(
              path[i][0],
              path[i][1],
              path[i + 1][0],
              path[i + 1][1],
            );
          }
          canvas.drawLine(path.last[0], path.last[1], path[0][0], path[0][1]);

          // Cross inside shield (simple +)
          canvas.drawLine(centerX, topY + 18, centerX, bottomY - 8);
          canvas.drawLine(centerX - 8, topY + 28, centerX + 8, topY + 28);

          // Crown on top
          canvas.drawLine(centerX - 8, topY + 8, centerX + 8, topY + 8);
          canvas.drawLine(centerX - 6, topY, centerX - 6, topY + 8);
          canvas.drawLine(centerX, topY - 3, centerX, topY + 8);
          canvas.drawLine(centerX + 6, topY, centerX + 6, topY + 8);
        },
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('MMMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
          : Row(
              children: [
                // Left panel - Form
                Expanded(
                  flex: 1,
                  child: Container(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Certificate Details',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Edit the information below to update the certificate',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Person Information
                            _buildSectionHeader(context, 'Person Information'),
                            const SizedBox(height: 12),
                            // Name field with autocomplete
                            Stack(
                              children: [
                                _buildTextField(
                                  controller: _nameCtrl,
                                  label: 'Full Name',
                                  icon: Icons.person,
                                  focusNode: _nameFocusNode,
                                ),
                                if (_showSuggestions)
                                  Positioned(
                                    top: 58,
                                    left: 0,
                                    right: 0,
                                    child: Material(
                                      elevation: 4,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        constraints: const BoxConstraints(
                                          maxHeight: 200,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        child: ListView.builder(
                                          shrinkWrap: true,
                                          itemCount: _searchResults.length,
                                          itemBuilder: (context, index) {
                                            final record =
                                                _searchResults[index];
                                            return ListTile(
                                              dense: true,
                                              leading: Icon(
                                                _getTypeIcon(record.type),
                                                size: 20,
                                                color: _getTypeColor(
                                                  record.type,
                                                ),
                                              ),
                                              title: Text(
                                                record.name,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                ),
                                              ),
                                              subtitle: Text(
                                                '${record.type.value} • ${DateFormat('MMM d, yyyy').format(record.date)}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              onTap: () =>
                                                  _fillFromRecord(record),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    controller: _fatherCtrl,
                                    label: 'Father\'s Name',
                                    icon: Icons.man,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildTextField(
                                    controller: _motherCtrl,
                                    label: 'Mother\'s Name',
                                    icon: Icons.woman,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _birthplaceCtrl,
                              label: 'Place of Birth',
                              icon: Icons.location_on,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildDateField(
                                    label: 'Date of Birth',
                                    date: _certificateData.birthDate,
                                    onTap: () => _selectDate(context, true),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildDateField(
                                    label:
                                        widget.recordType == RecordType.marriage
                                        ? 'Marriage Date'
                                        : widget.recordType ==
                                              RecordType.funeral
                                        ? 'Date of Death'
                                        : '${_certificateTitle.replaceAll("Certificate of ", "")} Date',
                                    date: _certificateData.sacramentDate,
                                    onTap: () => _selectDate(context, false),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // Sacrament Details
                            _buildSectionHeader(context, 'Sacrament Details'),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _ministerCtrl,
                              label: 'Minister (Rev. Fr.)',
                              icon: Icons.church,
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _sponsorCtrl,
                              label: widget.recordType == RecordType.marriage
                                  ? 'Witnesses'
                                  : 'Sponsor/Godparent(s)',
                              icon: Icons.people,
                            ),

                            const SizedBox(height: 24),

                            // Parish Information
                            _buildSectionHeader(context, 'Parish Information'),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _parishCtrl,
                              label: 'Parish Name',
                              icon: Icons.account_balance,
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _parishLocationCtrl,
                              label: 'Parish Location',
                              icon: Icons.location_city,
                            ),

                            const SizedBox(height: 24),

                            // Registry Information
                            _buildSectionHeader(
                              context,
                              'Registry Information',
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    controller: _pageCtrl,
                                    label: 'Page',
                                    icon: Icons.article,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildTextField(
                                    controller: _volumeCtrl,
                                    label: 'Volume',
                                    icon: Icons.folder,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _seriesCtrl,
                              label: 'Series',
                              icon: Icons.format_list_numbered,
                            ),
                            const SizedBox(height: 12),
                            _buildDateField(
                              label: 'Date Issued',
                              date: _certificateData.issueDate,
                              onTap: () => _selectIssueDate(context),
                            ),

                            const SizedBox(height: 24),

                            // Parish Priest
                            _buildSectionHeader(context, 'Authorization'),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _priestCtrl,
                              label: 'Parish Priest/Vicar',
                              icon: Icons.person_outline,
                            ),

                            const SizedBox(height: 24),

                            // Notes
                            _buildSectionHeader(context, 'Additional Notes'),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _notesCtrl,
                              label: 'Notes (optional)',
                              icon: Icons.notes,
                              maxLines: 3,
                            ),

                            const SizedBox(height: 32),

                            // Create Button
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _isGenerating
                                    ? null
                                    : () async {
                                        if (_formKey.currentState?.validate() ??
                                            false) {
                                          await _generateAndPrint();
                                        }
                                      },
                                icon: _isGenerating
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.card_membership),
                                label: Text(
                                  _isGenerating
                                      ? 'Generating...'
                                      : 'Create Certificate',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Right panel - Preview
                Expanded(
                  flex: 1,
                  child: Container(
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
                          child: Center(
                            child: Container(
                              margin: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: AspectRatio(
                                aspectRatio: 100 / 148,
                                child: _buildCertificatePreview(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    FocusNode? focusNode,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Color _getTypeColor(RecordType type) {
    switch (type) {
      case RecordType.baptism:
        return Colors.blue;
      case RecordType.marriage:
        return Colors.pink;
      case RecordType.confirmation:
        return Colors.purple;
      case RecordType.funeral:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(RecordType type) {
    switch (type) {
      case RecordType.baptism:
        return Icons.water_drop;
      case RecordType.marriage:
        return Icons.favorite;
      case RecordType.confirmation:
        return Icons.church;
      case RecordType.funeral:
        return Icons.diamond_outlined;
    }
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date != null
                        ? DateFormat.yMMMMd().format(date)
                        : 'Select date',
                    style: TextStyle(
                      fontWeight: date != null
                          ? FontWeight.w500
                          : FontWeight.normal,
                      color: date != null
                          ? colorScheme.onSurface
                          : colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCertificatePreview() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 2),
      ),
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPreviewParishText(),
            const SizedBox(height: 8),
            _buildPreviewTitleWithLogos(),
            const SizedBox(height: 14),

            Center(
              child: Text(
                'This is to Certify:',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 10),

            // Person details
            _buildPreviewRow('That', _nameCtrl.text.toUpperCase()),
            const SizedBox(height: 6),
            _buildPreviewRow('Child of', _fatherCtrl.text),
            const SizedBox(height: 2),
            _buildPreviewRow('and', _motherCtrl.text),
            const SizedBox(height: 6),
            _buildPreviewRow('born in', _birthplaceCtrl.text),
            const SizedBox(height: 6),

            // Birth date row
            _buildPreviewDateRow(
              'on the',
              _certificateData.birthDate != null
                  ? _ordinalDay(_certificateData.birthDate!.day)
                  : '__',
              'day of',
              _certificateData.birthDate != null
                  ? DateFormat('MMMM').format(_certificateData.birthDate!)
                  : '',
              _certificateData.birthDate?.year.toString() ?? '',
            ),

            const SizedBox(height: 12),

            // Sacrament statement
            Center(
              child: Text(
                _sacramentLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 10),

            // Sacrament date
            _buildPreviewDateRow(
              'on the',
              _certificateData.sacramentDate != null
                  ? _ordinalDay(_certificateData.sacramentDate!.day)
                  : '__',
              'day of',
              _certificateData.sacramentDate != null
                  ? DateFormat('MMMM').format(_certificateData.sacramentDate!)
                  : '',
              _certificateData.sacramentDate?.year.toString() ?? '',
            ),

            const SizedBox(height: 6),

            Center(
              child: Text(
                'According to the Rite of the Roman Catholic Church',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 9,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 6),

            // Minister
            _buildPreviewMinisterRow(_ministerCtrl.text.toUpperCase()),

            const SizedBox(height: 10),

            // Sponsor
            _buildPreviewSponsorRow(_sponsorCtrl.text),

            const SizedBox(height: 16),

            Center(
              child: Text(
                'as appears from the $_registerLabel Register of this Church',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 8,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 12),

            // Registry info
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    _buildPreviewRegistryRow(
                      'Dated :',
                      _formatDate(_certificateData.issueDate),
                    ),
                    _buildPreviewRegistryRow('Page  :', _pageCtrl.text),
                    _buildPreviewRegistryRow('Vol.  :', _volumeCtrl.text),
                    _buildPreviewRegistryRow('Series :', _seriesCtrl.text),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (widget.recordType == RecordType.confirmation) ...[
                      Text(
                        'NOTE: FOR MARRIAGE PURPOSE',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 8,
                          color: Colors.red,
                        ),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Rev.  ', style: TextStyle(fontSize: 8)),
                        Text(
                          _priestCtrl.text.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Parish Priest /Vicar',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 7,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewLogo(Uint8List? bytes, {double size = 44}) {
    if (bytes == null || bytes.isEmpty) {
      return SizedBox(width: size, height: size);
    }
    return Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
    );
  }

  Widget _buildPreviewParishText() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ARCHDIOCESE OF OZAMIS',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            _parishCtrl.text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            _parishLocationCtrl.text,
            style: TextStyle(fontSize: 9),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewTitleWithLogos() {
    final title = Text(
      _certificateTitle,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: widget.recordType == RecordType.confirmation ? 13 : 12,
      ),
      textAlign: TextAlign.center,
      maxLines: 2,
    );

    if (!_usesCertificateLogos ||
        (_archdioceseLogoBytes == null && _parishLogoBytes == null)) {
      return Center(child: title);
    }

    const logoSize = 52.0;
    const titleWidth = 125.0;

    Widget logoCell(Uint8List? bytes) => SizedBox(
          width: logoSize,
          height: logoSize,
          child: Center(
            child: _buildPreviewLogo(bytes, size: logoSize),
          ),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: logoCell(_archdioceseLogoBytes),
          ),
        ),
        SizedBox(
          width: titleWidth,
          child: Center(child: title),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: logoCell(_parishLogoBytes),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewCross() {
    return Container(
      width: 20,
      height: 28,
      child: CustomPaint(painter: CrossPainter()),
    );
  }

  Widget _buildPreviewCoatOfArms() {
    return Container(
      width: 28,
      height: 36,
      child: CustomPaint(painter: CoatOfArmsPainter()),
    );
  }

  static const double _previewLabelWidth = _formLabelWidth;

  Widget _buildPreviewRow(
    String label,
    String value, {
    double labelWidth = _previewLabelWidth,
    TextStyle? labelStyle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: labelStyle ?? TextStyle(fontSize: 9),
          ),
        ),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.black)),
            ),
            padding: const EdgeInsets.only(bottom: 2, left: 2),
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
              textAlign: TextAlign.left,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewUnderlined(
    String text,
    double width, {
    bool bold = false,
  }) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black)),
      ),
      padding: const EdgeInsets.only(bottom: 2),
      alignment: Alignment.bottomCenter,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildPreviewDateRow(
    String prefix,
    String day,
    String middle,
    String month,
    String year,
  ) {
    Widget plain(String text) => Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 2),
          child: Text(text, style: TextStyle(fontSize: 9)),
        );

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          plain(prefix),
          _buildPreviewUnderlined(day, 26, bold: true),
          plain(middle),
          _buildPreviewUnderlined(month, 58, bold: true),
          plain(','),
          _buildPreviewUnderlined(year, 32, bold: true),
        ],
      ),
    );
  }

  Widget _buildPreviewMinisterRow(String value) {
    return _buildPreviewRow('by the Rev. Fr.', value, labelWidth: 72);
  }

  Widget _buildPreviewSponsorRow(String value) {
    return _buildPreviewRow(
      'The Sponsor(s) being',
      value,
      labelWidth: 72,
      labelStyle: TextStyle(fontStyle: FontStyle.italic, fontSize: 9),
    );
  }

  Widget _buildPreviewRegistryRow(String label, String value) {
    return Row(
      children: [
        SizedBox(width: 40, child: Text(label, style: TextStyle(fontSize: 8))),
        Container(
          width: 60,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.black)),
          ),
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 8),
            textAlign: TextAlign.left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Custom painter for the cross decoration
class CrossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.5;

    // Vertical line
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );

    // Horizontal line
    canvas.drawLine(
      Offset(size.width / 2 - 7, size.height * 0.35),
      Offset(size.width / 2 + 7, size.height * 0.35),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for the coat of arms decoration (for baptism certificates)
class CoatOfArmsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.2;

    final centerX = size.width / 2;
    final topY = 3.0;
    final bottomY = size.height - 3;
    final width = size.width - 6;
    final halfWidth = width / 2;

    // Draw shield outline
    final path = Path()
      ..moveTo(centerX - halfWidth, topY + 5)
      ..lineTo(centerX - halfWidth, topY + 10)
      ..lineTo(centerX - halfWidth * 0.7, bottomY - 8)
      ..lineTo(centerX, bottomY)
      ..lineTo(centerX + halfWidth * 0.7, bottomY - 8)
      ..lineTo(centerX + halfWidth, topY + 10)
      ..lineTo(centerX + halfWidth, topY + 5)
      ..close();

    canvas.drawPath(path, paint..style = PaintingStyle.stroke);

    // Cross inside shield
    paint.strokeWidth = 1;
    // Vertical line of cross
    canvas.drawLine(
      Offset(centerX, topY + 12),
      Offset(centerX, bottomY - 6),
      paint,
    );
    // Horizontal line of cross
    canvas.drawLine(
      Offset(centerX - 6, topY + 20),
      Offset(centerX + 6, topY + 20),
      paint,
    );

    // Crown on top (3 lines)
    paint.strokeWidth = 1;
    // Base of crown
    canvas.drawLine(
      Offset(centerX - 6, topY + 5),
      Offset(centerX + 6, topY + 5),
      paint,
    );
    // Left crown peak
    canvas.drawLine(
      Offset(centerX - 5, topY),
      Offset(centerX - 5, topY + 5),
      paint,
    );
    // Center crown peak
    canvas.drawLine(
      Offset(centerX, topY - 2),
      Offset(centerX, topY + 5),
      paint,
    );
    // Right crown peak
    canvas.drawLine(
      Offset(centerX + 5, topY),
      Offset(centerX + 5, topY + 5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
