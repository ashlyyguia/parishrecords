import 'package:uuid/uuid.dart';

import '../models/register_marriage_entry.dart';
import '../models/register_ocr_entry.dart';

/// Loads register rows from a Firestore OCR job (stored entries or raw_text).
List<RegisterOcrEntry> registerEntriesForJob(Map<String, dynamic> job) {
  final stored = RegisterOcrEntry.listFromJobData(job);
  if (stored.isNotEmpty) return stored;

  final raw = job['raw_text']?.toString() ?? '';
  if (raw.trim().isEmpty) return [];

  return RegisterOcrParser.parse(
    raw,
    recordType: job['type']?.toString() ?? 'baptism',
  ).entries;
}

List<Map<String, dynamic>> registerEntriesToMaps(List<RegisterOcrEntry> entries) =>
    entries.map((e) => e.toMap()).toList();

/// Parses OCR text from a parish register page into individual entries.
class RegisterOcrParser {
  static const _uuid = Uuid();

  static final _datePattern = RegExp(
    r'(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})|(\d{4})-(\d{1,2})-(\d{1,2})',
  );

  static final _writtenDatePattern = RegExp(
    r'(\d{1,2})\s+'
    r'(January|February|March|April|May|June|July|August|September|October|November|December)'
    r'\s+(\d{4})',
    caseSensitive: false,
  );

  static final _lineNoPrefix = RegExp(r'^\s*(\d{1,4})[\.\)\:\s]+');
  static final _recordStartLine = RegExp(r'^\s*(\d{1,4})(?:[\.\)\:\s]|$)');

  static final _headerWords = {
    'register', 'registry', 'book', 'page', 'line', 'name', 'date',
    'father', 'mother', 'sponsor', 'godparent', 'minister', 'parish',
    'sacrament', 'baptism', 'marriage', 'confirmation', 'death', 'burial',
    'remarks', 'no.', 'no', 'child', 'birth', 'parents', 'residents', 'place',
  };

  static const _baptismHeaderHints = {
    'name of child',
    'place & date of birth',
    'place and date of birth',
    'residents of',
    'date of baptism',
    'sponsors',
  };

  /// Returns parsed entries and count of lines skipped as noise/headers.
  static ({List<RegisterOcrEntry> entries, int skippedLines}) parse(
    String rawText, {
    String recordType = 'baptism',
  }) {
    final type = recordType.toLowerCase();
    if (type == 'baptism') {
      final baptism = parseBaptismRegister(rawText);
      if (baptism.entries.isNotEmpty) return baptism;
    }
    if (type == 'marriage') {
      final marriage = parseMarriageRegister(rawText);
      if (marriage.entries.isNotEmpty) {
        return (
          entries: marriage.entries
              .map(
                (m) => RegisterOcrEntry(
                  id: _uuid.v4(),
                  name: m.recordDisplayName,
                  lineNo: m.lineNo,
                  placeAndBirthDate: m.groom.datesPlaceOfBirth,
                  parents: m.groom.parents,
                  residentsOf: m.groom.actualAddress,
                  baptismDateText: m.dateOfMarriage,
                  minister: m.minister,
                  sponsors: m.groom.sponsors,
                  rawLine: _marriageAsRawLine(m),
                  selected: true,
                ),
              )
              .toList(),
          skippedLines: marriage.skippedLines,
        );
      }
    }
    return _parseLegacy(rawText);
  }

  /// Lighter parser for post-camera scans (keeps UI responsive).
  static ({List<RegisterOcrEntry> entries, int skippedLines}) parseFast(
    String rawText,
  ) {
    final lines = _normalizeLines(rawText);
    if (lines.isEmpty) {
      return (entries: <RegisterOcrEntry>[], skippedLines: 0);
    }

    final strategies = [
      _parseDelimitedRows,
      _parseByRecordBlocks,
      _parseVerticalByAnchors,
      _parseLooseRowBlocks,
      _parseHorizontalRows,
    ];

    ({List<RegisterOcrEntry> entries, int skippedLines})? best;
    var bestScore = -1;

    for (final strategy in strategies) {
      final result = strategy(lines);
      final score = _scoreEntries(result.entries);
      if (score > bestScore) {
        bestScore = score;
        best = result;
      }
    }

    if (best != null && best.entries.isNotEmpty) return best;
    return (entries: <RegisterOcrEntry>[], skippedLines: lines.length);
  }

  /// Parses baptism register tables (8 columns) — multiple records per scan.
  static ({List<RegisterOcrEntry> entries, int skippedLines}) parseBaptismRegister(
    String rawText,
  ) {
    final lines = _normalizeLines(rawText);
    if (lines.isEmpty) {
      return (entries: <RegisterOcrEntry>[], skippedLines: 0);
    }

    final strategies = [
      _parseDelimitedRows,
      _parseByRecordBlocks,
      _parseVerticalByAnchors,
      _parseVerticalChunks,
      _parseHorizontalRows,
      _parseFullTextRecords,
      _parseInlineMultiRecord,
      _parseLooseRowBlocks,
    ];

    ({List<RegisterOcrEntry> entries, int skippedLines})? best;
    var bestScore = -1;

    for (final strategy in strategies) {
      final result = strategy(lines);
      final score = _scoreEntries(result.entries);
      if (score > bestScore) {
        bestScore = score;
        best = result;
      }
    }

    if (best != null && best.entries.isNotEmpty) return best;
    return (entries: <RegisterOcrEntry>[], skippedLines: lines.length);
  }

  static bool hasWrittenDate(String text) =>
      _writtenDatePattern.hasMatch(text) || _datePattern.hasMatch(text);

  static int _scoreEntries(List<RegisterOcrEntry> entries) {
    if (entries.isEmpty) return 0;
    var score = entries.length * 4;
    for (final e in entries) {
      if (e.name.trim().length >= 2) score += 3;
      if (e.date != null) score += 3;
      if (e.baptismDateText.isNotEmpty) score += 2;
      if (e.placeAndBirthDate.isNotEmpty) score += 2;
      if (e.parents.contains('/')) score += 2;
      if (e.minister.isNotEmpty) score += 2;
      if (e.sponsors.isNotEmpty) score += 1;
      if (e.residentsOf.isNotEmpty) score += 1;
    }
    return score;
  }

  /// Parse one register row line (any format).
  static RegisterOcrEntry? tryParseBaptismRow(
    String rowText, {
    String? rawLine,
  }) {
    final trimmed = rowText.trim();
    if (trimmed.length < 4) return null;

    String? lineNo;
    var body = trimmed;
    final m = _recordStartLine.firstMatch(trimmed);
    if (m != null) {
      lineNo = m.group(1);
      body = trimmed.substring(m.end).trim();
    }

    return _parseAccurateBaptismBody(lineNo, body, rawLine ?? trimmed);
  }

  /// Build entry from column-aligned OCR cells (0=No … 7=Sponsors).
  static RegisterOcrEntry? entryFromColumnTexts(
    List<String> cols, {
    required String rawLine,
    required String id,
  }) {
    final padded = List<String>.from(cols);
    while (padded.length < 8) {
      padded.add('');
    }
    return _entryFromColumns(padded, rawLine, id: id);
  }

  static List<String> _normalizeLines(String rawText) {
    return rawText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  static ({List<RegisterOcrEntry> entries, int skippedLines}) _parseDelimitedRows(
    List<String> lines,
  ) {
    final entries = <RegisterOcrEntry>[];
    var skipped = 0;

    for (final line in lines) {
      if (_isHeaderLine(line) || _isBaptismHeaderLine(line)) {
        skipped++;
        continue;
      }

      List<String> cols;
      if (line.contains('\t')) {
        cols = line.split('\t').map((c) => c.trim()).toList();
      } else if (line.contains('|')) {
        cols = line.split('|').map((c) => c.trim()).toList();
      } else if (line.contains('  ')) {
        // Multiple spaces often separate OCR columns on one row
        cols = line.split(RegExp(r'\s{2,}')).map((c) => c.trim()).toList();
        if (cols.length < 4) continue;
      } else {
        final parsed = tryParseBaptismRow(line, rawLine: line);
        if (parsed != null) {
          entries.add(parsed);
        } else {
          skipped++;
        }
        continue;
      }

      final entry = _entryFromColumns(cols, line);
      if (entry != null) {
        entries.add(entry);
      } else {
        final accurate = tryParseBaptismRow(line, rawLine: line);
        if (accurate != null) {
          entries.add(accurate);
        } else {
          skipped++;
        }
      }
    }

    return (entries: entries, skippedLines: skipped);
  }

  /// Groups lines that start with a row number (1, 2, 3…) into one record each.
  static ({List<RegisterOcrEntry> entries, int skippedLines}) _parseByRecordBlocks(
    List<String> lines,
  ) {
    final blocks = <List<String>>[];
    List<String>? current;
    var skipped = 0;

    for (final line in lines) {
      if (_isHeaderLine(line) || _isBaptismHeaderLine(line)) {
        skipped++;
        continue;
      }

      final startsRecord = _recordStartLine.hasMatch(line);
      if (startsRecord) {
        if (current != null && current.isNotEmpty) blocks.add(current);
        current = [line];
      } else if (current != null) {
        current.add(line);
      }
    }
    if (current != null && current.isNotEmpty) blocks.add(current);

    final entries = <RegisterOcrEntry>[];
    for (final block in blocks) {
      final joined = block.join(' ');
      final lineNoMatch = _recordStartLine.firstMatch(block.first);
      final lineNo = lineNoMatch?.group(1);
      final body = lineNoMatch != null
          ? block.first.substring(lineNoMatch.end).trim() +
              (block.length > 1 ? ' ${block.sublist(1).join(' ')}' : '')
          : joined;

      final entry = _parseAccurateBaptismBody(
        lineNo,
        body,
        block.join('\n'),
      );
      if (entry != null) {
        entries.add(entry);
        continue;
      }

      if (block.length >= 2) {
        final fromCols = _entryFromColumns(block, block.join('\n'));
        if (fromCols != null) entries.add(fromCols);
      }
    }

    return (entries: entries, skippedLines: skipped);
  }

  /// OCR often reads one table cell per line; group by line-no anchors.
  static ({List<RegisterOcrEntry> entries, int skippedLines}) _parseVerticalByAnchors(
    List<String> lines,
  ) {
    final dataLines = <String>[];
    var skipped = 0;

    for (final line in lines) {
      if (_isHeaderLine(line) || _isBaptismHeaderLine(line)) {
        skipped++;
      } else {
        dataLines.add(line);
      }
    }

    final entries = <RegisterOcrEntry>[];
    var i = 0;
    while (i < dataLines.length) {
      final line = dataLines[i];
      final isLineNoOnly = RegExp(r'^\d{1,4}$').hasMatch(line);
      final startsWithNo = _recordStartLine.hasMatch(line);

      if (!isLineNoOnly && !startsWithNo) {
        i++;
        continue;
      }

      final chunk = <String>[];
      if (isLineNoOnly) {
        chunk.add(line);
        i++;
      } else {
        final m = _recordStartLine.firstMatch(line)!;
        chunk.add(m.group(1)!);
        final rest = line.substring(m.end).trim();
        if (rest.isNotEmpty) chunk.add(rest);
        i++;
      }

      while (i < dataLines.length &&
          chunk.length < 12 &&
          !RegExp(r'^\d{1,3}$').hasMatch(dataLines[i]) &&
          !_recordStartLine.hasMatch(dataLines[i])) {
        chunk.add(dataLines[i]);
        i++;
      }

      if (chunk.length >= 2) {
        final entry = _entryFromColumns(chunk, chunk.join('\n')) ??
            _parseAccurateBaptismBody(
              chunk.first,
              chunk.sublist(1).join(' '),
              chunk.join('\n'),
            );
        if (entry != null) entries.add(entry);
      } else if (chunk.length == 1 && chunk.first.length > 12) {
        final entry = tryParseBaptismRow(chunk.first, rawLine: chunk.first);
        if (entry != null) entries.add(entry);
      }
    }

    return (entries: entries, skippedLines: skipped);
  }

  static ({List<RegisterOcrEntry> entries, int skippedLines}) _parseVerticalChunks(
    List<String> lines,
  ) {
    final dataLines = <String>[];
    var skipped = 0;

    for (final line in lines) {
      if (_isHeaderLine(line) || _isBaptismHeaderLine(line)) {
        skipped++;
      } else {
        dataLines.add(line);
      }
    }

    if (dataLines.length < 4) {
      return (entries: <RegisterOcrEntry>[], skippedLines: skipped);
    }

    final entries = <RegisterOcrEntry>[];

    for (final chunkSize in [8, 7, 9, 6]) {
      if (dataLines.length < chunkSize) continue;
      if (dataLines.length % chunkSize != 0) continue;

      entries.clear();
      for (var i = 0; i < dataLines.length; i += chunkSize) {
        final chunk = dataLines.sublist(i, i + chunkSize);
        final entry = _entryFromColumns(chunk, chunk.join('\n'));
        if (entry != null) entries.add(entry);
      }
      if (entries.length >= 2) break;
      entries.clear();
    }

    return (entries: entries, skippedLines: skipped);
  }

  static ({List<RegisterOcrEntry> entries, int skippedLines}) _parseHorizontalRows(
    List<String> lines,
  ) {
    final entries = <RegisterOcrEntry>[];
    var skipped = 0;

    for (final line in lines) {
      if (_isHeaderLine(line) || _isBaptismHeaderLine(line)) {
        skipped++;
        continue;
      }

      final rowMatch = RegExp(r'^(\d{1,4})\s+(.+)$').firstMatch(line);
      if (rowMatch == null) {
        skipped++;
        continue;
      }

      final entry = _parseAccurateBaptismBody(
        rowMatch.group(1),
        rowMatch.group(2)!.trim(),
        line,
      );
      if (entry != null) {
        entries.add(entry);
      } else {
        skipped++;
      }
    }

    return (entries: entries, skippedLines: skipped);
  }

  /// Split full text at record boundaries when newlines are missing.
  static ({List<RegisterOcrEntry> entries, int skippedLines}) _parseFullTextRecords(
    List<String> lines,
  ) {
    final full = lines.join('\n');
    final parts = full.split(RegExp(r'(?=\n\s*\d{1,3}[\.\)\:\s])'));
    if (parts.length <= 1) {
      final inline = full.split(RegExp(r'(?<=\s)(?=\d{1,3}\s+[A-Za-z])'));
      if (inline.length <= 1) {
        return (entries: <RegisterOcrEntry>[], skippedLines: 0);
      }
      return _parsePartsAsRecords(inline);
    }
    return _parsePartsAsRecords(parts);
  }

  static ({List<RegisterOcrEntry> entries, int skippedLines}) _parsePartsAsRecords(
    List<String> parts,
  ) {
    final entries = <RegisterOcrEntry>[];
    var skipped = 0;

    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      if (_isHeaderLine(trimmed) || _isBaptismHeaderLine(trimmed)) {
        skipped++;
        continue;
      }

      final rowMatch = RegExp(r'^(\d{1,4})[\.\)\:\s]+(.+)$', dotAll: true)
          .firstMatch(trimmed);

      RegisterOcrEntry? entry;
      if (rowMatch != null) {
        entry = _parseAccurateBaptismBody(
          rowMatch.group(1),
          rowMatch.group(2)!.trim().replaceAll('\n', ' '),
          trimmed,
        );
      }
      entry ??= tryParseBaptismRow(trimmed, rawLine: trimmed);
      if (entry != null) {
        entries.add(entry);
      } else {
        skipped++;
      }
    }

    return (entries: entries, skippedLines: skipped);
  }

  /// Accurate field extraction using register layout (minister anchor, two dates).
  static RegisterOcrEntry? _parseAccurateBaptismBody(
    String? lineNo,
    String body,
    String rawLine,
  ) {
    var work = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (work.isEmpty) return null;

    if (lineNo == null) {
      final m = _recordStartLine.firstMatch(work);
      if (m != null) {
        lineNo = m.group(1);
        work = work.substring(m.end).trim();
      }
    }

    // 1) Minister + sponsors (right side anchors)
    final ministerMatch = RegExp(
      r'((?:Fr\.|Rev\.|Father|Msgr\.|Monsignor)\s+[A-Za-z][A-Za-z\.\s\-]+?)(?=\s+[A-Z][a-z]+\s*/|\s+[A-Z][a-z]{2,}\s+[A-Z]|\s*$)',
      caseSensitive: false,
    ).firstMatch(work);

    String minister = '';
    String sponsors = '';
    if (ministerMatch != null) {
      minister = ministerMatch.group(1)!.trim();
      sponsors = work.substring(ministerMatch.end).trim();
      work = work.substring(0, ministerMatch.start).trim();
    } else {
      final fallbackMinister = RegExp(
        r'(?:Fr\.|Rev\.|Father|Msgr\.)\s+[A-Za-z]+(?:\s+[A-Za-z]+)*',
        caseSensitive: false,
      ).firstMatch(work);
      if (fallbackMinister != null) {
        minister = fallbackMinister.group(0)!.trim();
        sponsors = work.substring(fallbackMinister.end).trim();
        work = work.substring(0, fallbackMinister.start).trim();
      }
    }

    sponsors = _normalizeSponsors(sponsors);

    // 2) Dates (birth = first, baptism = last in row)
    final dates = <_DateSpan>[];
    for (final m in _writtenDatePattern.allMatches(work)) {
      dates.add(_DateSpan(m.start, m.end, m.group(0)!));
    }
    for (final m in _datePattern.allMatches(work)) {
      if (!dates.any((d) => m.start >= d.start && m.start < d.end)) {
        dates.add(_DateSpan(m.start, m.end, m.group(0)!));
      }
    }
    dates.sort((a, b) => a.start.compareTo(b.start));
    if (dates.isEmpty) {
      return _parseBaptismBodyWithoutDates(lineNo, work, rawLine);
    }

    final birthDate = dates.first;
    final baptismDate = dates.length > 1 ? dates.last : dates.first;

    final beforeBirth = work.substring(0, birthDate.start).trim();
    final betweenDates = dates.length > 1
        ? work.substring(birthDate.end, baptismDate.start).trim()
        : '';
    final afterBaptism = work.substring(baptismDate.end).trim();

    // 3) Name + place & birth
    final name = _extractChildName(beforeBirth);
    var placePart = beforeBirth;
    if (name.isNotEmpty) {
      placePart = placePart.replaceFirst(name, '').trim();
    }
    var placeAndBirthDate = placePart.isEmpty
        ? birthDate.text
        : '${placePart.replaceAll(RegExp(r'\s*-\s*$'), '').trim()} - ${birthDate.text}';
    placeAndBirthDate = placeAndBirthDate.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 4) Parents + residents (between dates, or after baptism if no minister split)
    var parents = '';
    var residentsOf = '';
    if (betweenDates.isNotEmpty) {
      final split = _splitParentsResidents(betweenDates);
      parents = split.parents;
      residentsOf = split.residents;
    } else if (afterBaptism.isNotEmpty && minister.isEmpty) {
      final split = _splitParentsResidentsMinisterSponsors(afterBaptism);
      parents = split.parents;
      residentsOf = split.residentsOf;
      minister = split.minister;
      if (sponsors.isEmpty) sponsors = split.sponsors;
    }

    if (parents.isEmpty && betweenDates.contains('/')) {
      parents = betweenDates;
    }
    if (residentsOf.isEmpty && afterBaptism.isNotEmpty && minister.isEmpty) {
      residentsOf = afterBaptism;
    }

    parents = parents.replaceAll(RegExp(r'\s+'), ' ').trim();
    residentsOf = residentsOf.replaceAll(RegExp(r'\s+'), ' ').trim();
    minister = _normalizeMinister(minister);

    if (name.length < 2) return null;

    final parsedBaptism = parseDate(baptismDate.text);

    return RegisterOcrEntry(
      id: _uuid.v4(),
      lineNo: lineNo,
      name: name,
      placeAndBirthDate: placeAndBirthDate,
      parents: parents,
      residentsOf: residentsOf,
      baptismDateText: baptismDate.text,
      minister: minister,
      sponsors: sponsors,
      date: parsedBaptism ?? parseDate(birthDate.text),
      rawLine: rawLine,
      selected: parsedBaptism != null,
    );
  }

  static final _placeKeyword = RegExp(
    r'\b(Tuburan|Villaflor|Barangay|Brgy|Bgy|City|Hospital|Province|'
    r'Occidental|Misamis|Oroquieta|Calamba|Ozamiz|Tangub|Don\s*Victor|'
    r'Poblacion|Sitio|Zone|St\.|Street|Rd\.|P-\d)\b',
    caseSensitive: false,
  );

  static String _extractChildName(String beforeBirth) {
    if (beforeBirth.isEmpty) return '';

    final keyword = _placeKeyword.firstMatch(beforeBirth);
    if (keyword != null && keyword.start > 2) {
      return _cleanName(beforeBirth.substring(0, keyword.start));
    }

    final comma = beforeBirth.indexOf(',');
    if (comma > 2) {
      return _cleanName(beforeBirth.substring(0, comma));
    }

    final words = beforeBirth.split(RegExp(r'\s+'));
    if (words.length <= 4) return _cleanName(beforeBirth);

    return _cleanName(words.take(3).join(' '));
  }

  static ({String parents, String residents}) _splitParentsResidents(String text) {
    if (text.isEmpty) return (parents: '', residents: '');

    final parentPair = RegExp(
      r'^(.+?\s/\s.+?)(?=\s+(?:Tuburan|Villaflor|Barangay|Brgy|[A-Z][a-z]+(?:\s*,\s*|\s+)[A-Z]))',
      caseSensitive: false,
    ).firstMatch(text);

    if (parentPair != null) {
      return (
        parents: parentPair.group(1)!.trim(),
        residents: text.substring(parentPair.end).trim(),
      );
    }

    if (text.contains('/')) {
      final slashParts = text.split(RegExp(r'\s+/\s+'));
      if (slashParts.length >= 2) {
        final second = slashParts[1];
        final cityInSecond = _placeKeyword.firstMatch(second);
        if (cityInSecond != null && cityInSecond.start > 0) {
          return (
            parents: '${slashParts[0]} / ${second.substring(0, cityInSecond.start).trim()}',
            residents: second.substring(cityInSecond.start).trim(),
          );
        }
        return (
          parents: '${slashParts[0]} / ${slashParts[1]}'.trim(),
          residents: slashParts.length > 2 ? slashParts.sublist(2).join(' ') : '',
        );
      }
    }

    return (parents: text, residents: '');
  }

  static String _normalizeMinister(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _normalizeSponsors(String s) {
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.contains('/')) return s;
    final twoNames = RegExp(
      r'^([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)$',
    ).firstMatch(s);
    if (twoNames != null) {
      return '${twoNames.group(1)} / ${twoNames.group(2)}';
    }
    return s;
  }

  static _RowParts _splitParentsResidentsMinisterSponsors(String text) {
    final slashParts = text.split(RegExp(r'\s*/\s*'));
    if (slashParts.length >= 4) {
      return _RowParts(
        parents: '${slashParts[0]} / ${slashParts[1]}'.trim(),
        residentsOf: slashParts.length > 2 ? slashParts[2].trim() : '',
        minister: slashParts.length > 3 ? slashParts[3].trim() : '',
        sponsors: slashParts.length > 4
            ? slashParts.sublist(4).join(' / ').trim()
            : '',
      );
    }

    final ministerMatch = RegExp(
      r'(Fr\.|Rev\.|Father|Msgr\.|Monsignor)\s+[^/]+',
      caseSensitive: false,
    ).firstMatch(text);

    if (ministerMatch != null) {
      final before = text.substring(0, ministerMatch.start).trim();
      final minister = ministerMatch.group(0)!.trim();
      final after = text.substring(ministerMatch.end).trim();
      final beforeChunks = before.split(RegExp(r'\s{2,}|,\s*(?=[A-Z])'));
      return _RowParts(
        parents: beforeChunks.isNotEmpty ? beforeChunks.first.trim() : before,
        residentsOf: beforeChunks.length > 1
            ? beforeChunks.sublist(1).join(', ').trim()
            : '',
        minister: minister,
        sponsors: after,
      );
    }

    return _RowParts(parents: text);
  }

  static RegisterOcrEntry? _entryFromColumns(
    List<String> cols,
    String rawLine, {
    String? id,
  }) {
    final working = cols.map((c) => c.trim()).toList();
    if (working.every((c) => c.isEmpty)) return null;

    String? lineNo;
    var start = 0;

    if (working.isNotEmpty && RegExp(r'^\d{1,4}$').hasMatch(working[0])) {
      lineNo = working[0];
      start = 1;
    } else if (working.isNotEmpty) {
      final m = _lineNoPrefix.firstMatch(working[0]);
      if (m != null) {
        lineNo = m.group(1);
        working[0] = working[0].substring(m.end).trim();
        if (working[0].isEmpty) start = 1;
      }
    }

    while (start < working.length && working[start].isEmpty) {
      start++;
    }
    final fields = start < working.length ? working.sublist(start) : <String>[];

    if (fields.length >= 4) {
      final name = _cleanName(fields[0]);
      var place = fields.length > 1 ? fields[1] : '';
      final parents = fields.length > 2 ? fields[2] : '';
      final residents = fields.length > 3 ? fields[3] : '';
      var baptismText = fields.length > 4 ? fields[4] : '';
      var minister =
          fields.length > 5 ? _normalizeMinister(fields[5]) : '';
      var sponsors = fields.length > 6
          ? fields.sublist(6).where((s) => s.isNotEmpty).join(' / ')
          : '';

      if (fields.length == 4 && baptismText.isNotEmpty && minister.isEmpty) {
        final tail = baptismText;
        final minM = RegExp(
          r'((?:Fr\.|Rev\.|Father|Msgr\.)\s+[A-Za-z][A-Za-z\.\s\-]+)',
          caseSensitive: false,
        ).firstMatch(tail);
        if (minM != null) {
          minister = minM.group(1)!.trim();
          baptismText = tail.substring(0, minM.start).trim();
          sponsors = _normalizeSponsors(tail.substring(minM.end).trim());
        }
      }

      if (!hasWrittenDate(place)) {
        final birthInPlace = _writtenDatePattern.firstMatch(place);
        if (birthInPlace == null) {
          final fromRaw = _extractDateFromText(rawLine);
          if (fromRaw != null) {
            place = '$place - ${_formatWrittenDate(fromRaw)}';
          }
        }
      }

      final baptismDt =
          parseDate(baptismText) ?? _extractDateFromText(baptismText);

      return RegisterOcrEntry(
        id: id ?? _uuid.v4(),
        lineNo: lineNo,
        name: name,
        placeAndBirthDate: place.trim(),
        parents: parents,
        residentsOf: residents,
        baptismDateText: baptismText,
        minister: minister,
        sponsors: sponsors,
        date: baptismDt,
        rawLine: rawLine,
        selected: baptismDt != null && name.length >= 2,
      );
    }

    if (fields.length >= 2) {
      final joined = fields.join(' ');
      return _parseAccurateBaptismBody(lineNo, joined, rawLine);
    }

    return null;
  }

  static DateTime? _extractDateFromText(String text) {
    final written = _writtenDatePattern.firstMatch(text);
    if (written != null) return parseDate(written.group(0)!);
    final numeric = _datePattern.firstMatch(text);
    if (numeric != null) return parseDate(numeric.group(0)!);
    return null;
  }

  static ({List<RegisterOcrEntry> entries, int skippedLines}) _parseLegacy(
    String rawText,
  ) {
    final lines = _normalizeLines(rawText);
    final entries = <RegisterOcrEntry>[];
    var skipped = 0;

    for (final line in lines) {
      if (_isHeaderLine(line)) {
        skipped++;
        continue;
      }

      final parsed = _parseLine(line);
      if (parsed == null) {
        skipped++;
        continue;
      }

      entries.add(
        RegisterOcrEntry(
          id: _uuid.v4(),
          name: parsed.name,
          date: parsed.date,
          lineNo: parsed.lineNo,
          baptismDateText: parsed.date != null
              ? '${parsed.date!.month}/${parsed.date!.day}/${parsed.date!.year}'
              : '',
          rawLine: line,
          selected: parsed.name.length >= 2 && parsed.date != null,
        ),
      );
    }

    return (entries: entries, skippedLines: skipped);
  }

  static bool _isBaptismHeaderLine(String line) {
    final lower = line.toLowerCase();
    return _baptismHeaderHints.any(lower.contains);
  }

  /// True for column headers / page noise (not a data row).
  static bool isRegisterHeaderLine(String line) {
    final t = line.trim();
    if (t.length < 12) return false;
    if (_isBaptismHeaderLine(t)) return true;
    final lower = t.toLowerCase();
    final headerPhraseCount = _baptismHeaderHints
        .where((h) => lower.contains(h))
        .length;
    return headerPhraseCount >= 2;
  }

  static bool _isHeaderLine(String line) {
    final trimmed = line.trim();
    // Row numbers (1, 2, 3…) are data, not headers
    if (RegExp(r'^\d{1,3}$').hasMatch(trimmed)) return false;
    if (RegExp(r'^\d{1,3}[\.\)\:\s].+').hasMatch(trimmed)) return false;

    final lower = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    final words = lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.length <= 2 && words.every(_headerWords.contains)) return true;
    if (trimmed.length < 3) return true;
    // Page/year-only lines, not register row numbers
    if (RegExp(r'^\d{4,}$').hasMatch(trimmed)) return true;
    return false;
  }

  /// When OCR misses dates, still build a row the user can fix in the table.
  static RegisterOcrEntry? _parseBaptismBodyWithoutDates(
    String? lineNo,
    String work,
    String rawLine,
  ) {
    final ministerMatch = RegExp(
      r'((?:Fr\.|Rev\.|Father|Msgr\.|Monsignor)\s+[A-Za-z][A-Za-z\.\s\-]+)',
      caseSensitive: false,
    ).firstMatch(work);

    var body = work;
    var minister = '';
    var sponsors = '';
    if (ministerMatch != null) {
      minister = ministerMatch.group(1)!.trim();
      sponsors = _normalizeSponsors(work.substring(ministerMatch.end).trim());
      body = work.substring(0, ministerMatch.start).trim();
    }

    final name = _extractChildName(body);
    if (name.length < 2) return null;

    var placeAndBirthDate = body;
    if (name.isNotEmpty) {
      placeAndBirthDate = body.replaceFirst(name, '').trim();
    }
    placeAndBirthDate = placeAndBirthDate.replaceAll(RegExp(r'\s+'), ' ').trim();

    final slashSplit = _splitParentsResidents(body.replaceFirst(name, '').trim());
    var parents = slashSplit.parents;
    var residents = slashSplit.residents;
    if (parents.isEmpty && body.contains('/')) {
      parents = body.replaceFirst(name, '').trim();
    }

    return RegisterOcrEntry(
      id: _uuid.v4(),
      lineNo: lineNo,
      name: name,
      placeAndBirthDate: placeAndBirthDate,
      parents: parents,
      residentsOf: residents,
      baptismDateText: '',
      minister: _normalizeMinister(minister),
      sponsors: sponsors,
      date: null,
      rawLine: rawLine,
      selected: true,
    );
  }

  /// Multiple records on one line: "1 Name... 2 Name... 3 Name..."
  static ({List<RegisterOcrEntry> entries, int skippedLines}) _parseInlineMultiRecord(
    List<String> lines,
  ) {
    final full = lines.join(' ');
    final splits = full.split(RegExp(r'(?<=\s)(?=\d{1,3}\s+[A-Za-z])'));
    if (splits.length < 2) {
      return (entries: <RegisterOcrEntry>[], skippedLines: 0);
    }
    return _parsePartsAsRecords(splits);
  }

  /// Group lines between row-number-only anchors (vertical cell layout).
  static ({List<RegisterOcrEntry> entries, int skippedLines}) _parseLooseRowBlocks(
    List<String> lines,
  ) {
    final dataLines = <String>[];
    var skipped = 0;

    for (final line in lines) {
      if (_isHeaderLine(line) || _isBaptismHeaderLine(line)) {
        skipped++;
      } else {
        dataLines.add(line);
      }
    }

    final blocks = <List<String>>[];
    List<String>? current;

    for (final line in dataLines) {
      final isAnchor = RegExp(r'^\d{1,3}$').hasMatch(line) ||
          _recordStartLine.hasMatch(line);
      if (isAnchor) {
        if (current != null && current.isNotEmpty) blocks.add(current);
        current = [line];
      } else if (current != null) {
        current.add(line);
      } else if (line.length > 8) {
        current = [line];
      }
    }
    if (current != null && current.isNotEmpty) blocks.add(current);

    final entries = <RegisterOcrEntry>[];
    for (final block in blocks) {
      final joined = block.join(' ');
      String? lineNo;
      var body = joined;

      final onlyNo = RegExp(r'^(\d{1,3})$').firstMatch(block.first.trim());
      if (onlyNo != null) {
        lineNo = onlyNo.group(1);
        body = block.length > 1 ? block.sublist(1).join(' ') : '';
      } else {
        final m = _recordStartLine.firstMatch(block.first);
        if (m != null) {
          lineNo = m.group(1);
          body = block.first.substring(m.end).trim() +
              (block.length > 1 ? ' ${block.sublist(1).join(' ')}' : '');
        }
      }

      if (body.trim().isEmpty) continue;

      final entry = _parseAccurateBaptismBody(lineNo, body.trim(), block.join('\n')) ??
          tryParseBaptismRow('$lineNo $body'.trim(), rawLine: block.join('\n')) ??
          _entryFromColumns(block, block.join('\n'));
      if (entry != null) entries.add(entry);
    }

    return (entries: entries, skippedLines: skipped);
  }

  static ({String name, DateTime? date, String? lineNo})? _parseLine(String line) {
    String? lineNo;
    var work = line;

    final lineMatch = _lineNoPrefix.firstMatch(work);
    if (lineMatch != null) {
      lineNo = lineMatch.group(1);
      work = work.substring(lineMatch.end).trim();
    }

    final dateMatch = _datePattern.firstMatch(work);
    if (dateMatch == null) {
      final written = _writtenDatePattern.firstMatch(work);
      if (written == null) {
        final nameOnly = _cleanName(work);
        if (nameOnly.length < 3) return null;
        return (name: nameOnly, date: null, lineNo: lineNo);
      }
      final date = parseDate(written.group(0)!);
      final before = work.substring(0, written.start).trim();
      return (name: _cleanName(before), date: date, lineNo: lineNo);
    }

    final dateStr = dateMatch.group(0)!;
    final date = parseDate(dateStr);
    final before = work.substring(0, dateMatch.start).trim();
    final after = work.substring(dateMatch.end).trim();

    var name = _cleanName(before);
    if (name.length < 2 && after.isNotEmpty) {
      name = _cleanName(after);
    }
    if (name.length < 2) return null;

    return (name: name, date: date, lineNo: lineNo);
  }

  static String _cleanName(String raw) {
    var s = raw
        .replaceAll(RegExp(r'[|;,]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    s = s.replaceAll(
      RegExp(r'\s+(s/o|d/o|son of|daughter of).*$', caseSensitive: false),
      '',
    );
    return s.trim();
  }

  static DateTime? parseDate(String input) {
    final trimmed = input.trim();

    final written = _writtenDatePattern.firstMatch(trimmed);
    if (written != null) {
      const months = {
        'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5,
        'june': 6, 'july': 7, 'august': 8, 'september': 9, 'october': 10,
        'november': 11, 'december': 12,
      };
      final day = int.parse(written.group(1)!);
      final month = months[written.group(2)!.toLowerCase()]!;
      final year = int.parse(written.group(3)!);
      return _safeDate(year, month, day);
    }

    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(trimmed);
    if (iso != null) {
      return _safeDate(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }

    final slash = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})$')
        .firstMatch(trimmed);
    if (slash == null) return null;

    var a = int.parse(slash.group(1)!);
    var b = int.parse(slash.group(2)!);
    var y = int.parse(slash.group(3)!);
    if (y < 100) y += y >= 50 ? 1900 : 2000;

    int month;
    int day;
    if (a > 12 && b <= 12) {
      day = a;
      month = b;
    } else if (b > 12 && a <= 12) {
      month = a;
      day = b;
    } else {
      month = a;
      day = b;
    }
    return _safeDate(y, month, day);
  }

  static DateTime? _safeDate(int year, int month, int day) {
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  static String formatWrittenDate(DateTime d) => _formatWrittenDate(d);

  static List<String> _splitRowParts(String line) {
    if (line.contains('\t')) {
      return line.split('\t').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
    }
    if (line.contains('|')) {
      return line.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
    }
    return line.split(RegExp(r'\s{2,}')).map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
  }

  static String _marriageAsRawLine(RegisterMarriageEntry m) {
    return [
      m.lineNo ?? '',
      m.groom.name,
      m.groom.legalStatus,
      m.groom.actualAddress,
      m.groom.datesPlaceOfBirth,
      m.groom.datesPlaceOfBaptism,
      m.dateOfMarriage,
      m.groom.parents,
      m.groom.sponsors,
      m.bride.name,
      m.bride.legalStatus,
      m.bride.parents,
      m.bride.sponsors,
      m.minister,
      m.licenseNumber,
      m.observations,
    ].join('\t');
  }

  /// Marriage register: pairs of lines (Man / Woman) per register number.
  static ({List<RegisterMarriageEntry> entries, int skippedLines})
      parseMarriageRegister(String rawText) {
    final lines = _normalizeLines(rawText);
    if (lines.isEmpty) {
      return (entries: <RegisterMarriageEntry>[], skippedLines: 0);
    }

    final entries = <RegisterMarriageEntry>[];
    var skipped = 0;
    RegisterMarriageEntry? current;
    var partyIndex = 0;

    void flush() {
      final row = current;
      if (row != null && _marriageEntryHasData(row)) {
        entries.add(row);
      }
      current = null;
      partyIndex = 0;
    }

    for (final line in lines) {
      if (_isHeaderLine(line) || _isMarriageHeaderLine(line)) {
        skipped++;
        continue;
      }

      final delimited = tryParseMarriageDelimitedRow(line);
      if (delimited != null) {
        flush();
        entries.add(delimited);
        continue;
      }

      final noMatch = _lineNoPrefix.firstMatch(line);
      if (noMatch != null) {
        flush();
        current = RegisterMarriageEntry(
          id: _uuid.v4(),
          lineNo: noMatch.group(1),
          selected: true,
        );
        partyIndex = 0;
        final rest = line.substring(noMatch.end).trim();
        if (rest.isNotEmpty) {
          _assignMarriagePartyText(current!.groom, rest);
        }
        continue;
      }

      if (current == null) {
        current = RegisterMarriageEntry(
          id: _uuid.v4(),
          lineNo: '${entries.length + 1}',
          selected: true,
        );
        partyIndex = 0;
      }

      final party = partyIndex == 0 ? current!.groom : current!.bride;
      if (!_partyLineFilled(party)) {
        _assignMarriagePartyText(party, line);
        if (partyIndex == 0 && _partyLineFilled(current!.groom)) {
          partyIndex = 1;
        }
      } else {
        partyIndex = 1;
        _assignMarriagePartyText(current!.bride, line);
      }
    }
    flush();

    return (entries: entries, skippedLines: skipped);
  }

  static bool _isMarriageHeaderLine(String line) {
    final lower = line.toLowerCase();
    return lower.contains('contracting') ||
        lower.contains('legal status') ||
        lower.contains('sponsors of marriage') ||
        lower.contains('license');
  }

  static bool _marriageEntryHasData(RegisterMarriageEntry e) =>
      e.groom.name.trim().isNotEmpty ||
      e.bride.name.trim().isNotEmpty ||
      e.dateOfMarriage.trim().isNotEmpty;

  static bool _partyLineFilled(MarriagePartyInfo p) =>
      p.name.trim().length >= 3;

  static void _assignMarriagePartyText(MarriagePartyInfo party, String line) {
    final parts = _splitRowParts(line);
    if (parts.isEmpty) {
      party.name = line.trim();
      return;
    }
    if (parts.length >= 1 && party.name.trim().isEmpty) {
      party.name = parts[0];
    }
    if (parts.length >= 2 && party.legalStatus.trim().isEmpty) {
      party.legalStatus = parts[1];
    }
    if (parts.length >= 3 && party.actualAddress.trim().isEmpty) {
      party.actualAddress = parts[2];
    }
    if (parts.length >= 4 && party.datesPlaceOfBirth.trim().isEmpty) {
      party.datesPlaceOfBirth = parts[3];
    }
    if (parts.length >= 5 && party.datesPlaceOfBaptism.trim().isEmpty) {
      party.datesPlaceOfBaptism = parts[4];
    }
    if (parts.length >= 6 && party.parents.trim().isEmpty) {
      party.parents = parts[5];
    }
    if (parts.length >= 7 && party.sponsors.trim().isEmpty) {
      party.sponsors = parts[6];
    }
  }

  /// Tab/pipe-separated marriage row with groom + bride columns.
  static RegisterMarriageEntry? tryParseMarriageDelimitedRow(String line) {
    final parts = _splitRowParts(line);
    if (parts.length < 3) return null;

    final entry = RegisterMarriageEntry(
      id: _uuid.v4(),
      lineNo: parts.first.replaceAll(RegExp(r'[^\d]'), '').isNotEmpty
          ? RegExp(r'\d+').firstMatch(parts.first)?.group(0)
          : null,
      selected: true,
    );

    if (parts.length >= 8) {
      entry.groom.name = parts.length > 1 ? parts[1] : '';
      entry.groom.legalStatus = parts.length > 2 ? parts[2] : '';
      entry.groom.actualAddress = parts.length > 3 ? parts[3] : '';
      entry.groom.datesPlaceOfBirth = parts.length > 4 ? parts[4] : '';
      entry.groom.datesPlaceOfBaptism = parts.length > 5 ? parts[5] : '';
      entry.dateOfMarriage = parts.length > 6 ? parts[6] : '';
      entry.groom.parents = parts.length > 7 ? parts[7] : '';
      entry.groom.sponsors = parts.length > 8 ? parts[8] : '';
      if (parts.length > 9) entry.bride.name = parts[9];
      if (parts.length > 10) entry.bride.legalStatus = parts[10];
      if (parts.length > 11) entry.bride.parents = parts[11];
      if (parts.length > 12) entry.bride.sponsors = parts[12];
      if (parts.length > 13) entry.minister = parts[13];
      if (parts.length > 14) entry.licenseNumber = parts[14];
      if (parts.length > 15) entry.observations = parts[15];
    } else {
      entry.groom.name = parts[0];
      if (parts.length > 1) entry.groom.legalStatus = parts[1];
      if (parts.length > 2) entry.groom.actualAddress = parts[2];
      if (parts.length > 3) entry.bride.name = parts[3];
    }

    return _marriageEntryHasData(entry) ? entry : null;
  }

  static String _formatWrittenDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _DateSpan {
  const _DateSpan(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

class _RowParts {
  const _RowParts({
    this.parents = '',
    this.residentsOf = '',
    this.minister = '',
    this.sponsors = '',
  });

  final String parents;
  final String residentsOf;
  final String minister;
  final String sponsors;
}
