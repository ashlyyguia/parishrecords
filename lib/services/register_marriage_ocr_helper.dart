import 'package:uuid/uuid.dart';

import '../models/register_marriage_entry.dart';
import '../models/register_ocr_entry.dart';
import 'register_ocr_parser.dart';

/// OCR → marriage register table (Man + Woman rows per No.).
class RegisterMarriageOcrHelper {
  RegisterMarriageOcrHelper._();

  static const _uuid = Uuid();

  static int? _lineNoInt(String? lineNo) {
    if (lineNo == null || lineNo.trim().isEmpty) return null;
    final m = RegExp(r'\d+').firstMatch(lineNo.trim());
    return m == null ? null : int.tryParse(m.group(0)!);
  }

  static bool _partyHasData(MarriagePartyInfo p) =>
      p.name.trim().isNotEmpty ||
      p.legalStatus.trim().isNotEmpty ||
      p.actualAddress.trim().isNotEmpty ||
      p.datesPlaceOfBirth.trim().isNotEmpty ||
      p.datesPlaceOfBaptism.trim().isNotEmpty ||
      p.parents.trim().isNotEmpty ||
      p.sponsors.trim().isNotEmpty;

  static bool entryHasData(RegisterMarriageEntry e) =>
      e.isReadyToSave ||
      e.dateOfMarriage.trim().isNotEmpty ||
      e.minister.trim().isNotEmpty ||
      e.licenseNumber.trim().isNotEmpty ||
      _partyHasData(e.groom) ||
      _partyHasData(e.bride);

  /// Builds marriage rows from baptism-shaped OCR rows (grouped by register No.).
  static List<RegisterMarriageEntry> fromOcrEntries(
    List<RegisterOcrEntry> ocrRows,
  ) {
    if (ocrRows.isEmpty) return [];

    final byNo = <int, List<RegisterOcrEntry>>{};
    final noKey = <RegisterOcrEntry>[];

    for (final e in ocrRows.where(_ocrRowMeaningful)) {
      final n = _lineNoInt(e.lineNo);
      if (n != null) {
        byNo.putIfAbsent(n, () => []).add(e);
      } else {
        noKey.add(e);
      }
    }

    final out = <RegisterMarriageEntry>[];

    final keys = byNo.keys.toList()..sort();
    for (final n in keys) {
      out.add(_entryFromOcrGroup(n, byNo[n]!));
    }

    for (var i = 0; i < noKey.length; i++) {
      out.add(_entryFromOcrGroup(i + 1, [noKey[i]]));
    }

    if (out.isEmpty) {
      for (var i = 0; i < ocrRows.length; i++) {
        if (_ocrRowMeaningful(ocrRows[i])) {
          out.add(_entryFromOcrGroup(i + 1, [ocrRows[i]]));
        }
      }
    }

    return autofillForTable(out);
  }

  static bool _ocrRowMeaningful(RegisterOcrEntry e) =>
      e.name.trim().isNotEmpty ||
      e.placeAndBirthDate.trim().isNotEmpty ||
      e.parents.trim().isNotEmpty ||
      e.residentsOf.trim().isNotEmpty ||
      e.baptismDateText.trim().isNotEmpty ||
      e.minister.trim().isNotEmpty ||
      e.sponsors.trim().isNotEmpty;

  static RegisterMarriageEntry _entryFromOcrGroup(
    int lineNo,
    List<RegisterOcrEntry> rows,
  ) {
    final entry = RegisterMarriageEntry(
      id: _uuid.v4(),
      lineNo: '$lineNo',
      selected: true,
    );

    if (rows.isEmpty) return entry;

    _mapOcrToParty(rows.first, entry.groom);
    if (rows.length >= 2) {
      _mapOcrToParty(rows[1], entry.bride);
    } else {
      _splitDualName(rows.first.name, entry);
    }

    for (final r in rows) {
      _mergeSharedFromOcr(entry, r);
    }

    return entry;
  }

  static void _splitDualName(String name, RegisterMarriageEntry entry) {
    final t = name.trim();
    if (t.isEmpty) return;
    for (final sep in [' & ', ' AND ', ' and ', '/']) {
      final i = t.indexOf(sep);
      if (i > 0) {
        entry.groom.name = t.substring(0, i).trim();
        entry.bride.name = t.substring(i + sep.length).trim();
        return;
      }
    }
  }

  static void _mapOcrToParty(RegisterOcrEntry ocr, MarriagePartyInfo party) {
    if (party.name.trim().isEmpty) party.name = ocr.name.trim();
    if (party.datesPlaceOfBirth.trim().isEmpty) {
      party.datesPlaceOfBirth = ocr.placeAndBirthDate.trim();
    }
    if (party.actualAddress.trim().isEmpty) {
      party.actualAddress = ocr.residentsOf.trim();
    }
    if (party.parents.trim().isEmpty) party.parents = ocr.parents.trim();
    if (party.sponsors.trim().isEmpty) party.sponsors = ocr.sponsors.trim();
  }

  static void _mergeSharedFromOcr(RegisterMarriageEntry entry, RegisterOcrEntry ocr) {
    if (entry.minister.trim().isEmpty) entry.minister = ocr.minister.trim();
    if (entry.dateOfMarriage.trim().isEmpty) {
      entry.dateOfMarriage = ocr.baptismDateText.trim();
    }
    final res = ocr.residentsOf.trim();
    if (entry.licenseNumber.trim().isEmpty && RegExp(r'^\d{5,}$').hasMatch(res)) {
      entry.licenseNumber = res;
    }
  }

  static void _mergeMarriageFields(
    RegisterMarriageEntry into,
    RegisterMarriageEntry from,
  ) {
    _mergeParty(into.groom, from.groom);
    _mergeParty(into.bride, from.bride);
    if (into.dateOfMarriage.trim().isEmpty) {
      into.dateOfMarriage = from.dateOfMarriage;
    }
    if (into.minister.trim().isEmpty) into.minister = from.minister;
    if (into.licenseNumber.trim().isEmpty) {
      into.licenseNumber = from.licenseNumber;
    }
    if (into.observations.trim().isEmpty) {
      into.observations = from.observations;
    }
  }

  static void _mergeParty(MarriagePartyInfo into, MarriagePartyInfo from) {
    if (into.name.trim().isEmpty) into.name = from.name;
    if (into.legalStatus.trim().isEmpty) into.legalStatus = from.legalStatus;
    if (into.actualAddress.trim().isEmpty) into.actualAddress = from.actualAddress;
    if (into.datesPlaceOfBirth.trim().isEmpty) {
      into.datesPlaceOfBirth = from.datesPlaceOfBirth;
    }
    if (into.datesPlaceOfBaptism.trim().isEmpty) {
      into.datesPlaceOfBaptism = from.datesPlaceOfBaptism;
    }
    if (into.parents.trim().isEmpty) into.parents = from.parents;
    if (into.sponsors.trim().isEmpty) into.sponsors = from.sponsors;
  }

  static List<RegisterMarriageEntry> ensureUniqueEntryIds(
    List<RegisterMarriageEntry> entries,
  ) {
    final seen = <String>{};
    final out = <RegisterMarriageEntry>[];
    for (var i = 0; i < entries.length; i++) {
      var id = entries[i].id.trim();
      if (id.isEmpty || seen.contains(id)) {
        id = '${_uuid.v4()}-$i';
      }
      seen.add(id);
      out.add(id == entries[i].id ? entries[i] : entries[i].copyWith(id: id));
    }
    return out;
  }

  static List<RegisterMarriageEntry> autofillForTable(
    List<RegisterMarriageEntry> entries,
  ) {
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.lineNo == null || e.lineNo!.trim().isEmpty) {
        e.lineNo = '${i + 1}';
      }
      e.selected = entryHasData(e);
    }
    return entries;
  }

  static List<RegisterMarriageEntry> resolveTableRows({
    required String ocrText,
    required List<RegisterOcrEntry> parsedOcr,
  }) {
    var entries = autofillForTable(fromOcrEntries(parsedOcr));

    if (entries.isEmpty && ocrText.trim().isNotEmpty) {
      entries = autofillForTable(
        RegisterOcrParser.parseMarriageRegister(ocrText).entries,
      );
    }

    if (entries.isEmpty) {
      entries = [
        RegisterMarriageEntry(
          id: _uuid.v4(),
          lineNo: '1',
          selected: true,
        ),
      ];
    }

    return entries;
  }

  /// Merges a new register photo (left then right page) by register No.
  static List<RegisterMarriageEntry> appendPageEntries(
    List<RegisterMarriageEntry> existing,
    List<RegisterMarriageEntry> fromPage,
  ) {
    final base = existing.where(entryHasData).toList();
    final added = autofillForTable(fromPage.where(entryHasData).toList());
    if (base.isEmpty) return added;
    if (added.isEmpty) return base;

    final byNo = <int, RegisterMarriageEntry>{};
    for (final e in base) {
      final n = _lineNoInt(e.lineNo);
      if (n != null) byNo[n] = e;
    }

    for (final e in added) {
      final n = _lineNoInt(e.lineNo);
      if (n != null && byNo.containsKey(n)) {
        _mergeMarriageFields(byNo[n]!, e);
      } else if (n != null) {
        byNo[n] = e;
      } else {
        base.add(e);
      }
    }

    final merged = byNo.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return autofillForTable(merged.map((e) => e.value).toList());
  }

  /// Apply OCR scan onto an open manual register form.
  static List<RegisterMarriageEntry> mergeIntoForm({
    required List<RegisterMarriageEntry> current,
    required List<RegisterMarriageEntry> scanned,
  }) {
    if (current.every((e) => !entryHasData(e)) && scanned.isNotEmpty) {
      return scanned;
    }
    return appendPageEntries(current, scanned);
  }
}
