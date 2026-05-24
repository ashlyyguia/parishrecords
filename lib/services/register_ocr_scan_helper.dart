import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:uuid/uuid.dart';

import '../models/register_marriage_entry.dart';
import '../models/register_ocr_entry.dart';
import 'register_marriage_ocr_helper.dart';
import 'ocr_service.dart';
import 'register_ocr_image_preprocess.dart';
import 'register_ocr_parser.dart';

/// One OCR text fragment with position (for table layout).
class OcrLineBox {
  const OcrLineBox({
    required this.text,
    required this.top,
    required this.left,
    required this.width,
    required this.height,
  });

  final String text;
  final double top;
  final double left;
  final double width;
  final double height;

  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
}

/// Result returned after staff reviews a scan.
class StaffOcrScanResult {
  const StaffOcrScanResult({
    required this.text,
    this.entries = const [],
    this.marriageEntries = const [],
    this.lineCount = 0,
    this.cellCount = 0,
  });

  /// Full OCR text (nothing removed).
  final String text;
  final List<RegisterOcrEntry> entries;
  final List<RegisterMarriageEntry> marriageEntries;
  final int lineCount;
  final int cellCount;

  bool get isMarriage => marriageEntries.isNotEmpty;
}

/// Builds accurate register rows from ML Kit block geometry.
class RegisterOcrScanHelper {
  static const _uuid = Uuid();
  static const _baptismColumns = 8;

  static final _headerPattern = RegExp(
    r'name\s+of\s+child|place.*birth|parents|residents|baptism|minister|sponsors',
    caseSensitive: false,
  );

  /// Collect every line and element from ML Kit (maximum text capture).
  static List<OcrLineBox> linesFromBlocks(List<TextBlock> blocks) {
    final lines = <OcrLineBox>[];
    final seen = <String>{};

    void add(String text, double top, double left, double width, double height) {
      final t = text.trim();
      if (t.isEmpty) return;
      final key = '${top.toStringAsFixed(0)}|${left.toStringAsFixed(0)}|$t';
      if (seen.contains(key)) return;
      seen.add(key);
      lines.add(
        OcrLineBox(
          text: t,
          top: top,
          left: left,
          width: width,
          height: height,
        ),
      );
    }

    for (final block in blocks) {
      for (final line in block.lines) {
        if (line.elements.length > 1) {
          for (final el in line.elements) {
            final box = el.boundingBox;
            add(el.text, box.top, box.left, box.width, box.height);
          }
        } else {
          final box = line.boundingBox;
          add(line.text, box.top, box.left, box.width, box.height);
        }
      }
      if (block.lines.isEmpty && block.text.trim().isNotEmpty) {
        final box = block.boundingBox;
        add(block.text, box.top, box.left, box.width, box.height);
      }
    }

    return lines;
  }

  /// Full reading-order text from blocks (supplements [plainText]).
  static String textFromBlockStructure(List<TextBlock> blocks) {
    final cells = linesFromBlocks(blocks);
    if (cells.isEmpty) return '';

    final sorted = List<OcrLineBox>.from(cells)
      ..sort((a, b) {
        final y = a.top.compareTo(b.top);
        return y != 0 ? y : a.left.compareTo(b.left);
      });

    return sorted.map((c) => c.text).join('\n');
  }

  /// Never drop ML Kit output — merge plain text + structured block text.
  static String extractCompleteText(
    String plainText,
    List<TextBlock> blocks,
  ) {
    final parts = <String>[];
    final plain = plainText.trim();
    if (plain.isNotEmpty) parts.add(plain);

    final structured = textFromBlockStructure(blocks);
    if (structured.isNotEmpty &&
        structured.replaceAll(RegExp(r'\s+'), ' ') !=
            plain.replaceAll(RegExp(r'\s+'), ' ')) {
      parts.add(structured);
    }

    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;

    return '${parts.first}\n\n${parts.sublist(1).join('\n\n')}';
  }

  static double _medianLineHeight(List<OcrLineBox> lines) {
    if (lines.isEmpty) return 20;
    final heights = lines.map((e) => e.height).toList()..sort();
    return heights[heights.length ~/ 2].clamp(10, 50);
  }

  static List<List<OcrLineBox>> _clusterIntoRows(List<OcrLineBox> lines) {
    if (lines.isEmpty) return [];

    final sorted = List<OcrLineBox>.from(lines)
      ..sort((a, b) {
        final y = a.top.compareTo(b.top);
        return y != 0 ? y : a.left.compareTo(b.left);
      });

    final tolerance = _medianLineHeight(sorted) * 0.75;
    final rows = <List<OcrLineBox>>[];

    for (final cell in sorted) {
      if (rows.isEmpty) {
        rows.add([cell]);
        continue;
      }
      final last = rows.last;
      final avgTop =
          last.map((e) => e.centerY).reduce((a, b) => a + b) / last.length;
      if ((cell.centerY - avgTop).abs() <= tolerance) {
        last.add(cell);
      } else {
        rows.add([cell]);
      }
    }

    for (final row in rows) {
      row.sort((a, b) => a.left.compareTo(b.left));
    }
    return rows;
  }

  static bool _isHeaderRow(List<OcrLineBox> row) {
    final joined = row.map((c) => c.text).join(' ').toLowerCase();
    return _headerPattern.hasMatch(joined);
  }

  static List<double> _detectColumnCenters(
    List<List<OcrLineBox>> rows, {
    double mergeGap = 35,
  }) {
    for (final row in rows) {
      if (_isHeaderRow(row) && row.length >= 3) {
        return row.map((c) => c.centerX).toList()..sort();
      }
    }

    final xPositions = <double>[];
    for (final row in rows) {
      if (_isHeaderRow(row)) continue;
      for (final cell in row) {
        xPositions.add(cell.centerX);
      }
    }

    if (xPositions.length < 3) {
      List<OcrLineBox>? widest;
      for (final row in rows) {
        if (_isHeaderRow(row)) continue;
        if (widest == null || row.length > widest.length) widest = row;
      }
      if (widest != null && widest.length >= 2) {
        return widest.map((c) => c.centerX).toList()..sort();
      }
      return [];
    }

    xPositions.sort();
    return _clusterPositions(
      xPositions,
      targetClusters: _baptismColumns,
      mergeGap: mergeGap,
    );
  }

  static List<double> _clusterPositions(
    List<double> sorted, {
    required int targetClusters,
    double mergeGap = 35.0,
  }) {
    if (sorted.isEmpty) return [];

    final clusters = <List<double>>[[sorted.first]];

    for (var i = 1; i < sorted.length; i++) {
      final x = sorted[i];
      final last = clusters.last;
      final avg = last.reduce((a, b) => a + b) / last.length;
      if (x - avg <= mergeGap) {
        last.add(x);
      } else {
        clusters.add([x]);
      }
    }

    final centers = clusters
        .map((c) => c.reduce((a, b) => a + b) / c.length)
        .toList()
      ..sort();

    while (centers.length < targetClusters && centers.length >= 2) {
      var maxGap = 0.0;
      var idx = 0;
      for (var i = 0; i < centers.length - 1; i++) {
        final g = centers[i + 1] - centers[i];
        if (g > maxGap) {
          maxGap = g;
          idx = i;
        }
      }
      if (maxGap < 40) break;
      centers.insert(idx + 1, (centers[idx] + centers[idx + 1]) / 2);
    }

    return centers;
  }

  static List<RegisterOcrEntry> parseEntriesFromBlocks(List<TextBlock> blocks) {
    if (blocks.isEmpty) return [];

    final cells = linesFromBlocks(blocks);
    if (cells.isEmpty) return [];

    final imageWidth = cells
        .map((c) => c.left + c.width)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final mergeGap = (imageWidth * 0.025).clamp(18.0, 55.0);

    final byAnchor = _parseEntriesFromRowAnchors(cells);
    final rows = _clusterIntoRows(cells);
    if (rows.isEmpty) return byAnchor;

    final columnCenters = _detectColumnCenters(rows, mergeGap: mergeGap);
    if (columnCenters.length >= 3) {
      final fromCols = _entriesFromColumnLayout(rows, columnCenters);
      if (fromCols.length >= byAnchor.length) return fromCols;
      return _mergeEntryLists(fromCols, byAnchor);
    }

    return byAnchor;
  }

  /// Groups all cells between left-column row numbers (1, 2, 3…).
  static List<RegisterOcrEntry> _parseEntriesFromRowAnchors(List<OcrLineBox> cells) {
    if (cells.length < 3) return [];

    final minLeft = cells.map((c) => c.left).reduce((a, b) => a < b ? a : b);
    final maxRight =
        cells.map((c) => c.left + c.width).reduce((a, b) => a > b ? a : b);
    final leftBand = minLeft + (maxRight - minLeft) * 0.15;

    final anchors = <({int no, double top})>[];
    for (final cell in cells) {
      final t = cell.text.trim();
      if (cell.left > leftBand) continue;
      final m = RegExp(r'^(\d{1,3})$').firstMatch(t);
      if (m != null) {
        anchors.add((no: int.parse(m.group(1)!), top: cell.top));
      }
    }

    if (anchors.isEmpty) return [];

    anchors.sort((a, b) => a.top.compareTo(b.top));

    final entries = <RegisterOcrEntry>[];
    for (var i = 0; i < anchors.length; i++) {
      final top = anchors[i].top;
      final bottom = i + 1 < anchors.length
          ? anchors[i + 1].top - 2
          : double.infinity;

      final bandCells = cells
          .where((c) => c.top >= top - 4 && c.top < bottom)
          .toList()
        ..sort((a, b) {
          final y = a.top.compareTo(b.top);
          return y != 0 ? y : a.left.compareTo(b.left);
        });

      if (bandCells.isEmpty) continue;

      final rowTexts = _clusterIntoRows(bandCells)
          .map((r) => r.map((c) => c.text).join(' ').trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final joined = rowTexts.join(' ').trim();
      if (joined.length < 4) continue;

      final entry = RegisterOcrParser.tryParseBaptismRow(
            '${anchors[i].no} $joined',
            rawLine: rowTexts.join('\n'),
          ) ??
          RegisterOcrParser.entryFromColumnTexts(
            [anchors[i].no.toString(), ...rowTexts],
            rawLine: rowTexts.join('\t'),
            id: _uuid.v4(),
          );

      if (entry != null) {
        entry.lineNo ??= '${anchors[i].no}';
        entries.add(entry);
      }
    }

    return entries;
  }

  static List<RegisterOcrEntry> _entriesFromColumnLayout(
    List<List<OcrLineBox>> rows,
    List<double> columnCenters,
  ) {
    final mergedRows = <List<String>>[];
    List<String>? pending;

    for (final row in rows) {
      if (_isHeaderRow(row)) continue;

      final cols = List<String>.filled(columnCenters.length, '');
      for (final cell in row) {
        final idx = _nearestColumnIndex(cell.centerX, columnCenters);
        if (idx < 0 || idx >= cols.length) continue;
        cols[idx] = cols[idx].isEmpty ? cell.text : '${cols[idx]} ${cell.text}';
      }

      final trimmed = cols.map((c) => c.trim()).toList();
      final nonEmpty = trimmed.where((c) => c.isNotEmpty).length;
      if (nonEmpty < 1) continue;

      final col0 = trimmed.isNotEmpty ? trimmed[0] : '';
      final startsNewRecord = RegExp(r'^\d{1,3}$').hasMatch(col0) ||
          RegExp(r'^\d{1,3}[\.\)\:\s]').hasMatch(col0);

      if (startsNewRecord) {
        if (pending != null && pending.any((c) => c.isNotEmpty)) {
          mergedRows.add(pending);
        }
        pending = trimmed;
      } else if (pending != null) {
        for (var i = 0; i < trimmed.length; i++) {
          if (trimmed[i].isEmpty) continue;
          pending[i] = pending[i].isEmpty
              ? trimmed[i]
              : '${pending[i]} ${trimmed[i]}';
        }
      } else {
        pending = trimmed;
      }
    }
    if (pending != null && pending.any((c) => c.isNotEmpty)) {
      mergedRows.add(pending);
    }

    final entries = <RegisterOcrEntry>[];

    for (final trimmed in mergedRows) {
      final joined = trimmed.join(' ').trim();
      if (joined.length < 3) continue;

      var entry = RegisterOcrParser.entryFromColumnTexts(
        trimmed,
        rawLine: trimmed.join('\t'),
        id: _uuid.v4(),
      );

      entry ??= RegisterOcrParser.tryParseBaptismRow(joined, rawLine: joined);

      if (entry != null) entries.add(entry);
    }

    return entries;
  }

  static int _nearestColumnIndex(double x, List<double> centers) {
    if (centers.isEmpty) return -1;
    var best = 0;
    var bestDist = (x - centers[0]).abs();
    for (var i = 1; i < centers.length; i++) {
      final d = (x - centers[i]).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  static String reconstructTableText(List<OcrLineBox> lines) {
    final rows = _clusterIntoRows(lines);
    final buffer = StringBuffer();
    for (final row in rows) {
      buffer.writeln(row.map((e) => e.text).join('\t'));
    }
    return buffer.toString().trim();
  }

  static int _entryScore(RegisterOcrEntry e) {
    var s = 0;
    if (e.name.trim().length >= 2) s += 3;
    if (e.date != null) s += 2;
    if (e.placeAndBirthDate.isNotEmpty) s += 2;
    if (e.parents.isNotEmpty) s += 2;
    if (e.residentsOf.isNotEmpty) s += 1;
    if (e.baptismDateText.isNotEmpty) s += 2;
    if (e.minister.isNotEmpty) s += 2;
    if (e.sponsors.isNotEmpty) s += 1;
    return s;
  }

  static String _entryDedupeKey(RegisterOcrEntry e, int index) {
    final no = e.lineNo?.trim();
    if (no != null && no.isNotEmpty) return 'no:$no';
    final name = e.name.trim().toLowerCase();
    if (name.length >= 2) return 'name:$name|${e.baptismDateText.trim()}';
    final raw = e.rawLine.trim();
    if (raw.length > 10) return 'raw:${raw.hashCode}';
    return 'idx:$index';
  }

  static bool _hasMeaningfulData(RegisterOcrEntry e) =>
      e.name.trim().isNotEmpty ||
      e.placeAndBirthDate.trim().isNotEmpty ||
      e.parents.trim().isNotEmpty ||
      e.residentsOf.trim().isNotEmpty ||
      e.minister.trim().isNotEmpty ||
      e.sponsors.trim().isNotEmpty ||
      e.baptismDateText.trim().isNotEmpty ||
      e.date != null ||
      e.rawLine.trim().length > 4;

  /// True when OCR produced rows that can populate the register table.
  static bool scanHasAutofillData(StaffOcrScanResult scan) {
    if (scan.marriageEntries
        .any(RegisterMarriageOcrHelper.entryHasData)) {
      return true;
    }
    return hasMeaningfulEntries(scan.entries);
  }

  /// Guarantees every row has a non-empty unique [RegisterOcrEntry.id] for Flutter keys.
  static List<RegisterOcrEntry> ensureUniqueEntryIds(List<RegisterOcrEntry> entries) {
    final seen = <String>{};
    final out = <RegisterOcrEntry>[];
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

  /// Ensures parsed rows are filled from OCR text before opening register forms.
  static StaffOcrScanResult finalizeScanResult(
    StaffOcrScanResult scan, {
    required String recordType,
  }) {
    final isMarriage = recordType.toLowerCase() == 'marriage';
    if (isMarriage) {
      var rows = scan.marriageEntries;
      if (!rows.any(RegisterMarriageOcrHelper.entryHasData)) {
        rows = RegisterMarriageOcrHelper.resolveTableRows(
          ocrText: scan.text,
          parsedOcr: scan.entries,
        );
      } else {
        rows = RegisterMarriageOcrHelper.autofillForTable(rows);
      }
      return StaffOcrScanResult(
        text: scan.text,
        marriageEntries: RegisterMarriageOcrHelper.ensureUniqueEntryIds(rows),
        lineCount: scan.lineCount,
        cellCount: rows.length,
      );
    }

    final entries = ensureUniqueEntryIds(
      autofillForTable(
        resolveTableRows(
          ocrText: scan.text,
          parsed: scan.entries,
          recordType: recordType,
        ),
      ),
    );
    return StaffOcrScanResult(
      text: scan.text,
      entries: entries,
      lineCount: scan.lineCount,
      cellCount: entries.isNotEmpty ? entries.length : scan.cellCount,
    );
  }

  static int _populatedCount(List<RegisterOcrEntry> entries) =>
      entries.where(_hasMeaningfulData).length;

  static List<RegisterOcrEntry> _mergeEntryLists(
    List<RegisterOcrEntry> primary,
    List<RegisterOcrEntry> secondary,
  ) {
    final combined = <RegisterOcrEntry>[...primary, ...secondary];
    return _dedupePreserveCount(combined);
  }

  static List<RegisterOcrEntry> _dedupePreserveCount(List<RegisterOcrEntry> entries) {
    final map = <String, RegisterOcrEntry>{};

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final key = _entryDedupeKey(e, i);
      final existing = map[key];
      if (existing == null || _entryScore(e) > _entryScore(existing)) {
        map[key] = e;
      }
    }

    final list = map.values.toList();
    list.sort((a, b) {
      final an = int.tryParse(a.lineNo ?? '9999') ?? 9999;
      final bn = int.tryParse(b.lineNo ?? '9999') ?? 9999;
      return an.compareTo(bn);
    });
    return list;
  }

  static List<RegisterOcrEntry> _bestEntriesFromSources(
    List<List<RegisterOcrEntry>> sources,
  ) {
    if (sources.isEmpty) return [];

    List<RegisterOcrEntry>? bestList;
    var bestPopulated = -1;
    var bestLength = -1;

    for (final list in sources) {
      if (list.isEmpty) continue;
      final pop = _populatedCount(list);
      final len = list.length;
      if (pop > bestPopulated ||
          (pop == bestPopulated && len > bestLength)) {
        bestPopulated = pop;
        bestLength = len;
        bestList = list;
      }
    }

    if (bestList == null) return [];

    var merged = List<RegisterOcrEntry>.from(bestList);
    for (final list in sources) {
      if (identical(list, bestList) || list.isEmpty) continue;
      merged = _mergeEntryLists(merged, list);
    }

    return _dedupePreserveCount(merged);
  }

  /// Split OCR text into one row per register record (1, 2, 3…).
  static List<RegisterOcrEntry> buildFallbackRowsFromText(String text) {
    final full = text.replaceAll('\r\n', '\n').trim();
    if (full.isEmpty) return [];

    var parts = full.split(
      RegExp(r'(?=(?:^|\n)\s*[1-9]\d{0,2}[\.\)\:\s]+[A-Za-z])', multiLine: true),
    );
    if (parts.length <= 1) {
      parts = full.split(RegExp(r'(?<=\s)(?=[1-9]\d{0,2}\s+[A-Za-z])'));
    }

    final entries = <RegisterOcrEntry>[];
    for (final part in parts) {
      final line = part.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (line.length < 6) continue;
      if (RegisterOcrParser.isRegisterHeaderLine(line)) continue;

      final entry = RegisterOcrParser.tryParseBaptismRow(line, rawLine: line) ??
          RegisterOcrParser.entryFromColumnTexts(
            line.split(RegExp(r'\t|\s{2,}')),
            rawLine: line,
            id: _uuid.v4(),
          );

      if (entry != null) {
        if (entry.lineNo == null || entry.lineNo!.isEmpty) {
          entry.lineNo = '${entries.length + 1}';
        }
        entries.add(entry);
        continue;
      }

      entries.add(
        RegisterOcrEntry(
          id: _uuid.v4(),
          lineNo: '${entries.length + 1}',
          name: line.length > 80 ? '${line.substring(0, 80)}…' : line,
          rawLine: line,
          selected: true,
        ),
      );
    }

    if (entries.length >= 2) return autofillForTable(entries);

    // One OCR fragment per line (vertical register layout)
    final lines = full
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.length > 4)
        .where((l) => !RegisterOcrParser.isRegisterHeaderLine(l))
        .toList();

    if (lines.length >= 4) {
      final vertical = <RegisterOcrEntry>[];
      var i = 0;
      while (i < lines.length) {
        final line = lines[i];
        final isNoOnly = RegExp(r'^\d{1,3}$').hasMatch(line);
        if (isNoOnly && i + 1 < lines.length) {
          final end = (i + 9).clamp(0, lines.length);
          final chunk = lines.sublist(i + 1, end);
          final body = chunk.join(' ');
          final parsed = RegisterOcrParser.tryParseBaptismRow(
            '$line $body',
            rawLine: '$line\n${chunk.join('\n')}',
          );
          vertical.add(
            parsed ??
                RegisterOcrEntry(
                  id: _uuid.v4(),
                  lineNo: line,
                  name: chunk.isNotEmpty ? chunk.first : body,
                  placeAndBirthDate:
                      chunk.length > 1 ? chunk.sublist(1).join(' ') : '',
                  rawLine: '$line\n${chunk.join('\n')}',
                  selected: true,
                ),
          );
          i += 1 + chunk.length;
        } else {
          i++;
        }
      }
      if (vertical.length >= 2) return autofillForTable(vertical);
    }

    if (entries.isNotEmpty) return autofillForTable(entries);

    final chunked = buildChunkedVerticalRows(full);
    if (chunked.isNotEmpty) return chunked;

    return buildEveryLineRows(full);
  }

  /// Register read top-to-bottom: 8 lines per record.
  static List<RegisterOcrEntry> buildChunkedVerticalRows(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.length > 1)
        .where((l) => !RegisterOcrParser.isRegisterHeaderLine(l))
        .toList();

    if (lines.length < 6) return [];

    final entries = <RegisterOcrEntry>[];
    for (final chunkSize in [8, 7, 9, 6]) {
      if (lines.length < chunkSize) continue;
      if (lines.length % chunkSize > 2 && lines.length != chunkSize) continue;

      entries.clear();
      for (var i = 0; i + chunkSize <= lines.length; i += chunkSize) {
        final chunk = lines.sublist(i, i + chunkSize);
        final entry = RegisterOcrParser.entryFromColumnTexts(
          chunk,
          rawLine: chunk.join('\n'),
          id: _uuid.v4(),
        );
        if (entry != null) {
          entry.lineNo ??= '${entries.length + 1}';
          entries.add(entry);
        }
      }
      if (entries.length >= 2) return autofillForTable(entries);
      entries.clear();
    }

    return [];
  }

  /// Last resort: one table row per OCR text line.
  static List<RegisterOcrEntry> buildEveryLineRows(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.length > 2)
        .where((l) => !RegisterOcrParser.isRegisterHeaderLine(l))
        .toList();

    if (lines.isEmpty) return [];

    return autofillForTable([
      for (var i = 0; i < lines.length; i++)
        RegisterOcrEntry(
          id: _uuid.v4(),
          lineNo: '${i + 1}',
          name: lines[i],
          rawLine: lines[i],
          selected: true,
        ),
    ]);
  }

  static int _ocrTextQuality(String text) {
    final t = text.trim();
    if (t.isEmpty) return 0;
    final lines =
        t.split(RegExp(r'\r?\n')).where((l) => l.trim().length > 2).length;
    var score = t.length + lines * 25;
    if (RegExp(r'\d{1,2}[\/\-\.]\d{1,2}').hasMatch(t)) score += 35;
    if (RegExp(
      r'baptism|marriage|minister|sponsor|child|parents|born|residents|name',
      caseSensitive: false,
    ).hasMatch(t)) {
      score += 45;
    }
    if (t.contains('\t') || RegExp(r' {2,}').hasMatch(t)) score += 20;
    return score;
  }

  /// Chooses the richest ML Kit result (original vs resized).
  static String pickBestOcrText(String a, String b) =>
      _ocrTextQuality(b) > _ocrTextQuality(a) ? b : a;

  /// Joins OCR text from successive register page scans.
  static String mergeScanText(String existing, String addition) {
    final a = existing.trim();
    final b = addition.trim();
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return '$a\n\n$b';
  }

  /// Merges a new register photo into existing rows.
  ///
  /// Parish books are usually a two-page spread: left page has child name,
  /// birth, and parents; right page has residents, baptism date, minister,
  /// and sponsors. Rows share the same register number (1, 2, 3…), so we
  /// merge by [RegisterOcrEntry.lineNo] instead of duplicating rows.
  static List<RegisterOcrEntry> appendPageEntries(
    List<RegisterOcrEntry> existing,
    List<RegisterOcrEntry> fromPage,
  ) {
    final base = existing.where(_hasMeaningfulData).toList();
    final added = autofillForTable(
      fromPage.where(_hasMeaningfulData).toList(),
    );
    if (base.isEmpty) {
      return added.isNotEmpty
          ? added
          : autofillForTable(List<RegisterOcrEntry>.from(fromPage));
    }
    if (added.isEmpty) return base;

    if (_shouldMergeRegisterPages(base, added)) {
      return autofillForTable(_mergeRegisterPagesByLineNo(base, added));
    }

    return _appendRegisterPagesSequential(base, added);
  }

  static int? _parseRegisterLineNo(String? lineNo) {
    if (lineNo == null || lineNo.trim().isEmpty) return null;
    final digits = RegExp(r'\d+').firstMatch(lineNo.trim());
    if (digits == null) return null;
    return int.tryParse(digits.group(0)!);
  }

  static Set<int> _registerLineNumbers(List<RegisterOcrEntry> entries) {
    final nums = <int>{};
    for (final e in entries) {
      final n = _parseRegisterLineNo(e.lineNo);
      if (n != null) nums.add(n);
    }
    return nums;
  }

  static int _leftColumnScore(RegisterOcrEntry e) {
    var score = 0;
    if (e.name.trim().length >= 2) score += 3;
    if (e.placeAndBirthDate.trim().isNotEmpty) score += 2;
    if (e.parents.trim().isNotEmpty) score += 2;
    return score;
  }

  static int _rightColumnScore(RegisterOcrEntry e) {
    var score = 0;
    if (e.residentsOf.trim().isNotEmpty) score += 2;
    if (e.baptismDateText.trim().isNotEmpty) score += 2;
    if (e.minister.trim().isNotEmpty) score += 2;
    if (e.sponsors.trim().isNotEmpty) score += 2;
    return score;
  }

  /// `left` = child/birth/parents page; `right` = residents/baptism/minister page.
  static String _registerPageSide(List<RegisterOcrEntry> entries) {
    var left = 0;
    var right = 0;
    for (final e in entries) {
      left += _leftColumnScore(e);
      right += _rightColumnScore(e);
    }
    if (left > right * 1.4) return 'left';
    if (right > left * 1.4) return 'right';
    return 'mixed';
  }

  static bool _shouldMergeRegisterPages(
    List<RegisterOcrEntry> base,
    List<RegisterOcrEntry> added,
  ) {
    final baseNums = _registerLineNumbers(base);
    final addedNums = _registerLineNumbers(added);
    final overlap = baseNums.intersection(addedNums);
    if (overlap.length >= 2) return true;
    if (overlap.length == 1 &&
        base.length <= 35 &&
        added.length <= 35 &&
        (base.length - added.length).abs() <= 4) {
      return true;
    }

    final baseSide = _registerPageSide(base);
    final addedSide = _registerPageSide(added);
    if (baseSide != 'mixed' &&
        addedSide != 'mixed' &&
        baseSide != addedSide &&
        base.length >= 2 &&
        added.length >= 2 &&
        (base.length - added.length).abs() <= 6) {
      return true;
    }

    return false;
  }

  static List<RegisterOcrEntry> _mergeRegisterPagesByLineNo(
    List<RegisterOcrEntry> base,
    List<RegisterOcrEntry> added,
  ) {
    final byNo = <int, RegisterOcrEntry>{};
    final noLineNo = <RegisterOcrEntry>[];

    for (final e in base) {
      final n = _parseRegisterLineNo(e.lineNo);
      if (n != null) {
        byNo[n] = e;
      } else {
        noLineNo.add(e);
      }
    }

    final unmatchedAdded = <RegisterOcrEntry>[];

    for (final e in added) {
      final n = _parseRegisterLineNo(e.lineNo);
      if (n != null && byNo.containsKey(n)) {
        _mergeEntryFields(byNo[n]!, e);
      } else if (n != null) {
        byNo[n] = e;
      } else {
        unmatchedAdded.add(e);
      }
    }

    if (byNo.isEmpty) {
      return _mergeRegisterPagesByIndex(base, added);
    }

    final merged = byNo.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final result = merged.map((e) => e.value).toList();

    if (noLineNo.isNotEmpty || unmatchedAdded.isNotEmpty) {
      result.addAll(
        _mergeRegisterPagesByIndex(noLineNo, unmatchedAdded),
      );
    }

    for (var i = 0; i < result.length; i++) {
      if (result[i].lineNo == null || result[i].lineNo!.trim().isEmpty) {
        result[i].lineNo = '${i + 1}';
      }
    }

    return result;
  }

  /// When row numbers are missing, pair rows in order (left page then right page).
  static List<RegisterOcrEntry> _mergeRegisterPagesByIndex(
    List<RegisterOcrEntry> base,
    List<RegisterOcrEntry> added,
  ) {
    if (base.isEmpty) return List<RegisterOcrEntry>.from(added);
    if (added.isEmpty) return List<RegisterOcrEntry>.from(base);

    final pairCount = base.length < added.length ? base.length : added.length;
    for (var i = 0; i < pairCount; i++) {
      _mergeEntryFields(base[i], added[i]);
      if (base[i].lineNo == null || base[i].lineNo!.trim().isEmpty) {
        base[i].lineNo = added[i].lineNo ?? '${i + 1}';
      }
    }

    if (added.length > base.length) {
      base.addAll(added.sublist(pairCount));
    }

    return base;
  }

  /// Next register volume or extra rows — append after the last row number.
  static List<RegisterOcrEntry> _appendRegisterPagesSequential(
    List<RegisterOcrEntry> base,
    List<RegisterOcrEntry> added,
  ) {
    final combined = <RegisterOcrEntry>[...base, ...added];
    var nextNo = 1;
    for (final e in combined) {
      final n = _parseRegisterLineNo(e.lineNo);
      if (n != null && n >= nextNo) nextNo = n + 1;
    }
    for (final e in combined) {
      if (e.lineNo == null || e.lineNo!.trim().isEmpty) {
        e.lineNo = '$nextNo';
        nextNo++;
      }
    }
    return combined;
  }

  /// Runs OCR from a picked file (reliable on web blob URLs).
  static Future<StaffOcrScanResult> scanXFile(
    XFile file, {
    String recordType = 'baptism',
  }) async {
    final rawBytes = await file.readAsBytes();
    return _scanFromBytes(
      rawBytes,
      recordType: recordType,
      cachePath: file.path,
    );
  }

  /// Runs OCR on one image path and returns table-ready rows.
  /// Uses ML Kit on Android/iOS; Tesseract on web and desktop.
  static Future<StaffOcrScanResult> scanImageFile(
    String path, {
    String recordType = 'baptism',
  }) async {
    final rawBytes = await XFile(path).readAsBytes();
    return _scanFromBytes(
      rawBytes,
      recordType: recordType,
      cachePath: path,
    );
  }

  static Future<StaffOcrScanResult> _scanFromBytes(
    Uint8List rawBytes, {
    required String recordType,
    required String cachePath,
  }) async {
    OcrResult? best;

    if (ocrUsesMlKit) {
      final enhancedBytes = await RegisterOcrImagePreprocess.enhanceBytes(
        rawBytes,
      );
      final enhancedPath = await RegisterOcrImagePreprocess.pathForEnhancedBytes(
        enhancedBytes,
      );
      final paths = <String>[
        cachePath,
        if (enhancedPath != cachePath) enhancedPath,
      ];
      for (final p in paths) {
        for (final mode in [OcrMode.printed, OcrMode.auto]) {
          final result = await OcrService.instance.recognizePath(
            p,
            mode: mode,
            languageHint: 'eng',
          );
          if (best == null ||
              _ocrTextQuality(result.text) > _ocrTextQuality(best.text) ||
              (result.blocks.length > best.blocks.length &&
                  result.text.length >= best.text.length)) {
            best = result;
          }
        }
      }
    } else {
      final variants = await RegisterOcrImagePreprocess.webOcrVariants(rawBytes);
      for (final variant in variants) {
        final result = await OcrService.instance.recognizeBytes(
          variant,
          languageHint: 'eng',
        );
        if (best == null ||
            _ocrTextQuality(result.text) > _ocrTextQuality(best.text)) {
          best = result;
        }
        if (_ocrTextQuality(result.text) >= 200) break;
      }
    }

    final ocr = best ?? OcrResult(text: '', mode: OcrMode.printed, blocks: []);
    final mergedText = extractCompleteText(ocr.text, ocr.blocks);

    final scan = prepareScanResult(
      plainText: mergedText.isNotEmpty ? mergedText : ocr.text,
      blocks: ocr.blocks,
      recordType: recordType,
    );

    return finalizeScanResult(scan, recordType: recordType);
  }

  /// Picks the best rows for the table after a camera scan.
  static List<RegisterOcrEntry> resolveTableRows({
    required String ocrText,
    required List<RegisterOcrEntry> parsed,
    String recordType = 'baptism',
  }) {
    final text = ocrText.trim();

    // Keep block-layout rows even when ML Kit plain [text] is empty.
    var entries = autofillForTable(List<RegisterOcrEntry>.from(parsed));

    if (text.isNotEmpty) {
      if (_populatedCount(entries) < 1) {
        entries = autofillForTable(
          RegisterOcrParser.parse(text, recordType: recordType).entries,
        );
      }

      if (_populatedCount(entries) < 1) {
        entries = buildFallbackRowsFromText(text);
      }

      if (_populatedCount(entries) < 1) {
        entries = buildChunkedVerticalRows(text);
      }

      if (_populatedCount(entries) < 1) {
        entries = buildEveryLineRows(text);
      }
    }

    entries = entries.where(_hasMeaningfulData).toList();

    if (entries.isEmpty && text.isNotEmpty) {
      entries = buildEveryLineRows(text);
    }

    for (var i = 0; i < entries.length; i++) {
      if (entries[i].lineNo == null || entries[i].lineNo!.trim().isEmpty) {
        entries[i].lineNo = '${i + 1}';
      }
    }

    return entries;
  }

  /// True when OCR produced at least one fillable register row.
  static bool hasMeaningfulEntries(List<RegisterOcrEntry> entries) =>
      entries.any(_hasMeaningfulData);

  /// Merges OCR sources and fills every column the parser could detect.
  static List<RegisterOcrEntry> autofillForTable(List<RegisterOcrEntry> entries) {
    if (entries.isEmpty) return entries;

    final filled = <RegisterOcrEntry>[];
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i];
      if (e.name.trim().isEmpty && e.rawLine.trim().isNotEmpty) {
        final parsed = RegisterOcrParser.tryParseBaptismRow(
          e.rawLine,
          rawLine: e.rawLine,
        );
        if (parsed != null) e = _mergeEntryFields(e, parsed);
      }
      _fillVisibleFieldsFromRawLine(e);
      if (e.lineNo == null || e.lineNo!.trim().isEmpty) {
        e.lineNo = '${i + 1}';
      }
      if (e.baptismDateText.trim().isEmpty && e.date != null) {
        e.baptismDateText = RegisterOcrParser.formatWrittenDate(e.date!);
      }
      e.selected = e.name.trim().length >= 2 ||
          e.placeAndBirthDate.trim().isNotEmpty ||
          e.parents.trim().isNotEmpty ||
          e.minister.trim().isNotEmpty;
      filled.add(e);
    }
    return filled;
  }

  /// Copies OCR text into table columns when structured parsing left them empty.
  static void _fillVisibleFieldsFromRawLine(RegisterOcrEntry e) {
    final raw = e.rawLine.trim();
    if (raw.isEmpty) return;

    if (e.name.trim().isEmpty) {
      final lines = raw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      var candidate = lines.isNotEmpty ? lines.first : raw;
      candidate =
          candidate.replaceFirst(RegExp(r'^\d{1,3}[\.\)\:\s]+'), '').trim();
      if (candidate.length >= 2) {
        e.name = candidate.length > 120
            ? '${candidate.substring(0, 120)}…'
            : candidate;
      }
    }

    if (e.placeAndBirthDate.trim().isEmpty && e.parents.trim().isEmpty) {
      final cols = raw.split(RegExp(r'\t|\s{2,}')).map((c) => c.trim()).toList();
      if (cols.length >= 3) {
        if (e.name.trim().isEmpty && cols.length > 1) {
          e.name = cols[1];
        }
        if (e.placeAndBirthDate.trim().isEmpty && cols.length > 2) {
          e.placeAndBirthDate = cols[2];
        }
        if (e.parents.trim().isEmpty && cols.length > 3) {
          e.parents = cols[3];
        }
        if (e.residentsOf.trim().isEmpty && cols.length > 4) {
          e.residentsOf = cols[4];
        }
        if (e.baptismDateText.trim().isEmpty && cols.length > 5) {
          e.baptismDateText = cols[5];
        }
        if (e.minister.trim().isEmpty && cols.length > 6) {
          e.minister = cols[6];
        }
        if (e.sponsors.trim().isEmpty && cols.length > 7) {
          e.sponsors = cols[7];
        }
      }
    }
  }

  static RegisterOcrEntry _mergeEntryFields(
    RegisterOcrEntry keep,
    RegisterOcrEntry parsed,
  ) {
    if (keep.name.trim().isEmpty && parsed.name.trim().isNotEmpty) {
      keep.name = parsed.name;
    } else if (keep.name.trim().length < 3 &&
        parsed.name.trim().length > keep.name.trim().length) {
      keep.name = parsed.name;
    }
    if (keep.placeAndBirthDate.trim().isEmpty) {
      keep.placeAndBirthDate = parsed.placeAndBirthDate;
    }
    if (keep.parents.trim().isEmpty) keep.parents = parsed.parents;
    if (keep.residentsOf.trim().isEmpty) {
      keep.residentsOf = parsed.residentsOf;
    }
    if (keep.baptismDateText.trim().isEmpty) {
      keep.baptismDateText = parsed.baptismDateText;
    }
    if (keep.date == null) keep.date = parsed.date;
    if (keep.minister.trim().isEmpty) keep.minister = parsed.minister;
    if (keep.sponsors.trim().isEmpty) keep.sponsors = parsed.sponsors;
    keep.selected = keep.name.trim().length >= 2 ||
        keep.placeAndBirthDate.trim().isNotEmpty ||
        keep.parents.trim().isNotEmpty ||
        keep.baptismDateText.trim().isNotEmpty ||
        keep.minister.trim().isNotEmpty;
    return keep;
  }

  /// Fast pipeline for camera scans — block layout + text merge + autofill.
  static StaffOcrScanResult prepareScanResult({
    required String plainText,
    List<TextBlock> blocks = const [],
    String recordType = 'baptism',
  }) {
    final cells = linesFromBlocks(blocks);
    final tableText =
        cells.isNotEmpty ? reconstructTableText(cells) : '';
    final fullText = extractCompleteText(plainText, blocks);
    var textForParse = fullText.isNotEmpty ? fullText : plainText;
    if (textForParse.trim().isEmpty && blocks.isNotEmpty) {
      textForParse = textFromBlockStructure(blocks);
    }

    final sources = <List<RegisterOcrEntry>>[
      parseEntriesFromBlocks(blocks),
      if (tableText.isNotEmpty)
        RegisterOcrParser.parseFast(tableText).entries,
      if (plainText.trim().isNotEmpty)
        RegisterOcrParser.parseFast(plainText).entries,
      if (textForParse.trim().isNotEmpty &&
          textForParse.trim() != plainText.trim())
        RegisterOcrParser.parseFast(textForParse).entries,
      if (plainText.trim().isNotEmpty)
        RegisterOcrParser.parse(plainText, recordType: recordType).entries,
    ];

    var entries = resolveTableRows(
      ocrText: textForParse,
      parsed: _bestEntriesFromSources(sources),
      recordType: recordType,
    );

    return StaffOcrScanResult(
      text: textForParse,
      entries: entries,
      marriageEntries: const [],
      lineCount: _lineCount(textForParse),
      cellCount: cells.length,
    );
  }

  static int _lineCount(String text) =>
      text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).length;

  static String bestTextForParsing({
    required String plainText,
    List<TextBlock> blocks = const [],
  }) {
    return prepareScanResult(plainText: plainText, blocks: blocks).text;
  }
}
