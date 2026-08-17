# OCR Accuracy Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a measurement harness that lets us tune the on-device (ML Kit) parish register OCR pipeline against real photos with a repeatable, regression-safe accuracy metric.

**Architecture:** Split capture (ML Kit, device-only) from replay (offline tests) by refactoring the geometry parser to accept plain `OcrLineBox` cells; capture cells to committed JSON fixtures; replay fixtures through the parser and score against hand-keyed ground truth with a Levenshtein-based similarity metric; assert per-fixture baseline floors.

**Tech Stack:** Flutter/Dart, `flutter_test`, Google ML Kit (`google_mlkit_text_recognition`), pure-Dart `image` pipeline (unchanged here). No new dependencies — Levenshtein is implemented in-repo.

## Global Constraints

- Target platform for this spec: **native mobile / Google ML Kit** only. No web/Tesseract fixtures.
- No new pub dependencies; implement string similarity in pure Dart.
- Capture/dev tooling MUST be gated behind `kDebugMode` and excluded from release behavior.
- The refactor of `parseEntriesFromBlocks` MUST be behavior-preserving — the on-device call path stays identical.
- Tests live under `test/ocr/`; run with `flutter test test/ocr/`.
- Follow existing style: `static` utility methods on classes, `RegExp` field cleaning, named constructors with `required`.
- Ground truth is authoritative only after user verification; do not raise baselines above user-verified numbers.

---

### Task 1: `OcrLineBox` JSON + `parseEntriesFromCells` seam

Make the geometry parser replayable offline without ML Kit.

**Files:**
- Modify: `lib/services/register_ocr_scan_helper.dart` (class `OcrLineBox` ~line 15; method `parseEntriesFromBlocks` line 267)
- Test: `test/ocr/parse_entries_from_cells_test.dart`

**Interfaces:**
- Consumes: existing `OcrLineBox({text, top, left, width, height})`, `RegisterOcrScanHelper.linesFromBlocks(List<TextBlock>)`, `RegisterOcrEntry`.
- Produces:
  - `Map<String, dynamic> OcrLineBox.toJson()` → `{text, top, left, width, height}`
  - `factory OcrLineBox.fromJson(Map<String, dynamic>)`
  - `static List<RegisterOcrEntry> RegisterOcrScanHelper.parseEntriesFromCells(List<OcrLineBox> cells)` — contains the former body of `parseEntriesFromBlocks`.
  - `parseEntriesFromBlocks(blocks)` remains, now delegating to `parseEntriesFromCells(linesFromBlocks(blocks))`.

- [ ] **Step 1: Write the failing test**

Create `test/ocr/parse_entries_from_cells_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/register_ocr_scan_helper.dart';

void main() {
  group('OcrLineBox JSON', () {
    test('round-trips through toJson/fromJson', () {
      const box = OcrLineBox(
        text: 'Alberto', top: 100, left: 120, width: 80, height: 20,
      );
      final restored = OcrLineBox.fromJson(box.toJson());
      expect(restored.text, 'Alberto');
      expect(restored.top, 100);
      expect(restored.left, 120);
      expect(restored.width, 80);
      expect(restored.height, 20);
    });
  });

  group('parseEntriesFromCells', () {
    test('extracts a baptism row from positioned cells', () {
      final cells = <OcrLineBox>[
        const OcrLineBox(text: '1', top: 100, left: 10, width: 15, height: 20),
        const OcrLineBox(
            text: 'Alberto', top: 100, left: 120, width: 80, height: 20),
        const OcrLineBox(
            text: 'Saligumba', top: 100, left: 210, width: 90, height: 20),
        const OcrLineBox(
            text: '07 January 2008', top: 100, left: 320, width: 140,
            height: 20),
      ];
      final entries = RegisterOcrScanHelper.parseEntriesFromCells(cells);
      expect(entries, isNotEmpty);
      expect(entries.first.name.toLowerCase(), contains('alberto'));
    });

    test('returns empty for no cells', () {
      expect(RegisterOcrScanHelper.parseEntriesFromCells(const []), isEmpty);
    });
  });
}
```

> Note: the pub package name is `parishrecord` (confirmed in `pubspec.yaml`), so test imports use `package:parishrecord/...`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ocr/parse_entries_from_cells_test.dart`
Expected: FAIL — `OcrLineBox.toJson`/`fromJson` and `parseEntriesFromCells` are undefined.

- [ ] **Step 3: Add JSON to `OcrLineBox`**

In `lib/services/register_ocr_scan_helper.dart`, inside the `OcrLineBox` class (after the `centerY` getter, before the closing brace):

```dart
  Map<String, dynamic> toJson() => {
        'text': text,
        'top': top,
        'left': left,
        'width': width,
        'height': height,
      };

  factory OcrLineBox.fromJson(Map<String, dynamic> json) => OcrLineBox(
        text: json['text'] as String,
        top: (json['top'] as num).toDouble(),
        left: (json['left'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
      );
```

- [ ] **Step 4: Extract `parseEntriesFromCells`**

Replace the existing method at line 267:

```dart
  static List<RegisterOcrEntry> parseEntriesFromBlocks(List<TextBlock> blocks) {
    if (blocks.isEmpty) return [];

    final cells = linesFromBlocks(blocks);
    if (cells.isEmpty) return [];
    // ... existing body ...
    return byAnchor;
  }
```

with:

```dart
  static List<RegisterOcrEntry> parseEntriesFromBlocks(List<TextBlock> blocks) {
    if (blocks.isEmpty) return [];
    return parseEntriesFromCells(linesFromBlocks(blocks));
  }

  static List<RegisterOcrEntry> parseEntriesFromCells(List<OcrLineBox> cells) {
    if (cells.isEmpty) return [];
    // ... existing body, unchanged (imageWidth, mergeGap, byAnchor, rows,
    //     columnCenters, fromCols, _mergeEntryLists) ...
    return byAnchor;
  }
```

Move everything that was between the old `if (cells.isEmpty) return [];` and the final `return byAnchor;` verbatim into `parseEntriesFromCells`. Do not change the other call site (`register_ocr_scan_helper.dart:1256` still calls `parseEntriesFromBlocks(blocks)`).

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/ocr/parse_entries_from_cells_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Verify no regression in the wider suite compiles**

Run: `flutter analyze lib/services/register_ocr_scan_helper.dart`
Expected: No new errors.

- [ ] **Step 7: Commit**

```bash
git add lib/services/register_ocr_scan_helper.dart test/ocr/parse_entries_from_cells_test.dart
git commit -m "refactor(ocr): add OcrLineBox JSON + parseEntriesFromCells seam"
```

---

### Task 2: Similarity scoring utility

Pure-Dart metric so OCR near-misses earn partial credit.

**Files:**
- Create: `test/ocr/support/ocr_scoring.dart`
- Test: `test/ocr/ocr_scoring_test.dart`

> Placed under `test/` because it is test-only support code (no app dependency).

**Interfaces:**
- Produces:
  - `String normalizeField(String s)`
  - `int levenshtein(String a, String b)`
  - `double fieldSimilarity(String a, String b)` — `1.0` when both normalize to empty; `0.0` when exactly one is empty.
  - `const List<String> scoredFields` = `['name', 'date', 'placeAndBirthDate', 'parents', 'residentsOf', 'minister', 'sponsors']`
  - `class FixtureScore { double rowPrecision; double rowRecall; Map<String,double> fieldMeans; double headline; List<Map<String,double>> rowScores; String report(String label); }`
  - `FixtureScore scoreRows({required List<Map<String,String>> expected, required List<Map<String,String>> actual, Map<String,double>? weights})` — matches rows by `'lineNo'`, defaults weights `{name:2, date:2}` (others weight 1).

- [ ] **Step 1: Write the failing test**

Create `test/ocr/ocr_scoring_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'support/ocr_scoring.dart';

void main() {
  test('normalizeField lowercases, strips punctuation, collapses space', () {
    expect(normalizeField('  Alberto,  SALIGUMBA! '), 'alberto saligumba');
  });

  test('levenshtein counts single-char edits', () {
    expect(levenshtein('kitten', 'sitting'), 3);
    expect(levenshtein('abc', 'abc'), 0);
  });

  test('fieldSimilarity: identical is 1.0, both empty is 1.0', () {
    expect(fieldSimilarity('Saligumba', 'saligumba'), 1.0);
    expect(fieldSimilarity('', '   '), 1.0);
  });

  test('fieldSimilarity: one empty is 0.0, near-miss is partial', () {
    expect(fieldSimilarity('Alberto', ''), 0.0);
    final s = fieldSimilarity('Saligumba', 'Saligamba');
    expect(s, greaterThan(0.8));
    expect(s, lessThan(1.0));
  });

  test('scoreRows aligns by lineNo and computes recall/precision', () {
    final expected = [
      {'lineNo': '1', 'name': 'Alberto Saligumba', 'date': '07 January 2008'},
      {'lineNo': '2', 'name': 'Elliana Eltagon', 'date': '08 February 2016'},
    ];
    final actual = [
      {'lineNo': '1', 'name': 'Alberto Saligumba', 'date': '07 January 2008'},
    ];
    final score = scoreRows(expected: expected, actual: actual);
    expect(score.rowRecall, 0.5);
    expect(score.rowPrecision, 1.0);
    expect(score.fieldMeans['name'], greaterThan(0.4));
    expect(score.headline, greaterThan(0.0));
    expect(score.report('demo'), contains('name'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ocr/ocr_scoring_test.dart`
Expected: FAIL — `ocr_scoring.dart` does not exist.

- [ ] **Step 3: Implement the scoring utility**

Create `test/ocr/support/ocr_scoring.dart`:

```dart
String normalizeField(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      final del = prev[j + 1] + 1;
      final ins = curr[j] + 1;
      final sub = prev[j] + cost;
      var m = del < ins ? del : ins;
      if (sub < m) m = sub;
      curr[j + 1] = m;
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

double fieldSimilarity(String a, String b) {
  final na = normalizeField(a);
  final nb = normalizeField(b);
  if (na.isEmpty && nb.isEmpty) return 1.0;
  if (na.isEmpty || nb.isEmpty) return 0.0;
  final dist = levenshtein(na, nb);
  final maxLen = na.length > nb.length ? na.length : nb.length;
  return 1.0 - dist / maxLen;
}

const List<String> scoredFields = [
  'name',
  'date',
  'placeAndBirthDate',
  'parents',
  'residentsOf',
  'minister',
  'sponsors',
];

class FixtureScore {
  FixtureScore({
    required this.rowPrecision,
    required this.rowRecall,
    required this.fieldMeans,
    required this.headline,
    required this.rowScores,
  });

  final double rowPrecision;
  final double rowRecall;
  final Map<String, double> fieldMeans;
  final double headline;
  final List<Map<String, double>> rowScores;

  String report(String label) {
    final b = StringBuffer('OCR score [$label]\n');
    b.writeln('  headline: ${headline.toStringAsFixed(3)}');
    b.writeln('  row recall: ${rowRecall.toStringAsFixed(3)}  '
        'precision: ${rowPrecision.toStringAsFixed(3)}');
    for (final f in scoredFields) {
      b.writeln('  $f: ${(fieldMeans[f] ?? 0).toStringAsFixed(3)}');
    }
    return b.toString();
  }
}

FixtureScore scoreRows({
  required List<Map<String, String>> expected,
  required List<Map<String, String>> actual,
  Map<String, double>? weights,
}) {
  final w = weights ?? const {'name': 2.0, 'date': 2.0};
  final actualByLine = <String, Map<String, String>>{};
  for (final row in actual) {
    final ln = (row['lineNo'] ?? '').trim();
    if (ln.isNotEmpty) actualByLine.putIfAbsent(ln, () => row);
  }

  final fieldTotals = {for (final f in scoredFields) f: 0.0};
  final rowScores = <Map<String, double>>[];
  var matched = 0;

  for (final exp in expected) {
    final ln = (exp['lineNo'] ?? '').trim();
    final act = actualByLine[ln];
    if (act != null) matched++;
    final rowScore = <String, double>{};
    for (final f in scoredFields) {
      final sim = fieldSimilarity(exp[f] ?? '', act?[f] ?? '');
      rowScore[f] = sim;
      fieldTotals[f] = fieldTotals[f]! + sim;
    }
    rowScores.add(rowScore);
  }

  final n = expected.isEmpty ? 1 : expected.length;
  final fieldMeans = {for (final f in scoredFields) f: fieldTotals[f]! / n};

  var weightSum = 0.0;
  var weighted = 0.0;
  for (final f in scoredFields) {
    final fw = w[f] ?? 1.0;
    weighted += fieldMeans[f]! * fw;
    weightSum += fw;
  }

  return FixtureScore(
    rowPrecision: actual.isEmpty ? 0.0 : matched / actual.length,
    rowRecall: expected.isEmpty ? 0.0 : matched / expected.length,
    fieldMeans: fieldMeans,
    headline: weightSum == 0 ? 0.0 : weighted / weightSum,
    rowScores: rowScores,
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ocr/ocr_scoring_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add test/ocr/support/ocr_scoring.dart test/ocr/ocr_scoring_test.dart
git commit -m "test(ocr): add Levenshtein similarity scoring utility"
```

---

### Task 3: Fixture model, loader, and synthetic golden test

Prove the whole replay→score loop end-to-end without a device, using a committed synthetic fixture.

**Files:**
- Create: `test/ocr/support/register_ocr_fixture.dart`
- Create: `test/ocr/fixtures/_synthetic.json`
- Create: `test/ocr/fixtures/_synthetic.expected.json`
- Test: `test/ocr/register_ocr_fixtures_test.dart`

**Interfaces:**
- Consumes: `OcrLineBox.fromJson`, `RegisterOcrScanHelper.parseEntriesFromCells`, `RegisterOcrEntry`, `scoreRows`, `FixtureScore`.
- Produces:
  - `class RegisterOcrFixture { String image; String recordType; String page; String flatText; List<OcrLineBox> cells; factory RegisterOcrFixture.fromJson(Map<String,dynamic>); }`
  - `RegisterOcrFixture loadFixture(String name)` — reads `test/ocr/fixtures/<name>.json`.
  - `List<Map<String,String>> loadExpected(String name)` — reads `test/ocr/fixtures/<name>.expected.json`.
  - `Map<String,String> entryToFieldMap(RegisterOcrEntry e)` — maps an entry to the scored-field keys (`date` ← `baptismDateText`).

- [ ] **Step 1: Write the synthetic fixture files**

Create `test/ocr/fixtures/_synthetic.json`:

```json
{
  "image": "_synthetic",
  "recordType": "baptism",
  "page": "left",
  "capturedWith": "synthetic",
  "flatText": "1 Alberto Saligumba 07 January 2008\n2 Elliana Eltagon 08 February 2016",
  "cells": [
    { "text": "1", "top": 100, "left": 10, "width": 15, "height": 20 },
    { "text": "Alberto", "top": 100, "left": 120, "width": 80, "height": 20 },
    { "text": "Saligumba", "top": 100, "left": 210, "width": 90, "height": 20 },
    { "text": "07 January 2008", "top": 100, "left": 320, "width": 140, "height": 20 },
    { "text": "2", "top": 160, "left": 10, "width": 15, "height": 20 },
    { "text": "Elliana", "top": 160, "left": 120, "width": 80, "height": 20 },
    { "text": "Eltagon", "top": 160, "left": 210, "width": 90, "height": 20 },
    { "text": "08 February 2016", "top": 160, "left": 320, "width": 150, "height": 20 }
  ]
}
```

Create `test/ocr/fixtures/_synthetic.expected.json`:

```json
[
  { "lineNo": "1", "name": "Alberto Saligumba", "date": "07 January 2008" },
  { "lineNo": "2", "name": "Elliana Eltagon", "date": "08 February 2016" }
]
```

- [ ] **Step 2: Write the failing test**

Create `test/ocr/register_ocr_fixtures_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'support/ocr_scoring.dart';
import 'support/register_ocr_fixture.dart';
import 'package:parishrecord/services/register_ocr_scan_helper.dart';

void main() {
  test('synthetic fixture replays through parser and scores well', () {
    final fixture = loadFixture('_synthetic');
    final expected = loadExpected('_synthetic');

    final entries =
        RegisterOcrScanHelper.parseEntriesFromCells(fixture.cells);
    final actual = entries.map(entryToFieldMap).toList();

    final score = scoreRows(expected: expected, actual: actual);
    // ignore: avoid_print
    print(score.report('_synthetic'));

    expect(score.rowRecall, greaterThanOrEqualTo(0.5));
    expect(score.fieldMeans['name'], greaterThan(0.5));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/ocr/register_ocr_fixtures_test.dart`
Expected: FAIL — `register_ocr_fixture.dart` does not exist.

- [ ] **Step 4: Implement the fixture support**

Create `test/ocr/support/register_ocr_fixture.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:parishrecord/services/register_ocr_scan_helper.dart';
import 'package:parishrecord/models/register_ocr_entry.dart';

class RegisterOcrFixture {
  RegisterOcrFixture({
    required this.image,
    required this.recordType,
    required this.page,
    required this.flatText,
    required this.cells,
  });

  final String image;
  final String recordType;
  final String page;
  final String flatText;
  final List<OcrLineBox> cells;

  factory RegisterOcrFixture.fromJson(Map<String, dynamic> json) {
    return RegisterOcrFixture(
      image: json['image'] as String? ?? '',
      recordType: json['recordType'] as String? ?? 'baptism',
      page: json['page'] as String? ?? 'left',
      flatText: json['flatText'] as String? ?? '',
      cells: (json['cells'] as List<dynamic>)
          .map((c) => OcrLineBox.fromJson(Map<String, dynamic>.from(c as Map)))
          .toList(),
    );
  }
}

const _fixtureDir = 'test/ocr/fixtures';

RegisterOcrFixture loadFixture(String name) {
  final file = File('$_fixtureDir/$name.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return RegisterOcrFixture.fromJson(json);
}

List<Map<String, String>> loadExpected(String name) {
  final file = File('$_fixtureDir/$name.expected.json');
  final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  return list
      .map((e) => (e as Map).map(
            (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
          ))
      .toList();
}

Map<String, String> entryToFieldMap(RegisterOcrEntry e) => {
      'lineNo': e.lineNo ?? '',
      'name': e.name,
      'date': e.baptismDateText,
      'placeAndBirthDate': e.placeAndBirthDate,
      'parents': e.parents,
      'residentsOf': e.residentsOf,
      'minister': e.minister,
      'sponsors': e.sponsors,
    };
```

> `flutter test` runs with the package root as the working directory, so the relative `test/ocr/fixtures` path resolves correctly.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/ocr/register_ocr_fixtures_test.dart`
Expected: PASS; the printed report shows non-zero `name` and `date` field means.

- [ ] **Step 6: Commit**

```bash
git add test/ocr/support/register_ocr_fixture.dart test/ocr/fixtures/_synthetic.json test/ocr/fixtures/_synthetic.expected.json test/ocr/register_ocr_fixtures_test.dart
git commit -m "test(ocr): add fixture loader + synthetic golden test"
```

---

### Task 4: Debug-only fixture capture tool

Produce real fixture JSON from an image using ML Kit, on a device/emulator.

**Files:**
- Create: `lib/dev/ocr_fixture_dump.dart`
- Modify: `lib/app/router.dart` (add a `kDebugMode`-gated route)
- Test: `test/ocr/fixture_dump_json_test.dart`

**Interfaces:**
- Consumes: `OcrImagePick.pickRegisterPages`, `OcrService.instance.recognizeText(File)` → `OcrResult{text, blocks}`, `RegisterOcrScanHelper.linesFromBlocks`, `OcrLineBox.toJson`.
- Produces:
  - `String buildFixtureJson({required String image, required String recordType, required String page, required String flatText, required List<OcrLineBox> cells})` — pretty-printed JSON matching the fixture schema.
  - `class OcrFixtureDumpPage extends StatefulWidget` — debug UI that runs the capture and shows/copies the JSON.

- [ ] **Step 1: Write the failing test**

Create `test/ocr/fixture_dump_json_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/dev/ocr_fixture_dump.dart';
import 'package:parishrecord/services/register_ocr_scan_helper.dart';

void main() {
  test('buildFixtureJson emits schema-correct JSON', () {
    final json = buildFixtureJson(
      image: 'sample.jpg',
      recordType: 'baptism',
      page: 'left',
      flatText: 'hello',
      cells: const [
        OcrLineBox(text: '1', top: 100, left: 10, width: 15, height: 20),
      ],
    );
    final map = jsonDecode(json) as Map<String, dynamic>;
    expect(map['image'], 'sample.jpg');
    expect(map['recordType'], 'baptism');
    expect(map['page'], 'left');
    expect(map['flatText'], 'hello');
    expect((map['cells'] as List).first['text'], '1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ocr/fixture_dump_json_test.dart`
Expected: FAIL — `ocr_fixture_dump.dart` does not exist.

- [ ] **Step 3: Implement the dump helper + page**

Create `lib/dev/ocr_fixture_dump.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/ocr_image_pick.dart';
import '../services/ocr_service.dart';
import '../services/register_ocr_scan_helper.dart';

String buildFixtureJson({
  required String image,
  required String recordType,
  required String page,
  required List<OcrLineBox> cells,
  required String flatText,
}) {
  final map = {
    'image': image,
    'recordType': recordType,
    'page': page,
    'capturedWith': 'mlkit-latin',
    'flatText': flatText,
    'cells': cells.map((c) => c.toJson()).toList(),
  };
  return const JsonEncoder.withIndent('  ').convert(map);
}

/// Debug-only screen: pick a register image, run ML Kit, dump fixture JSON.
class OcrFixtureDumpPage extends StatefulWidget {
  const OcrFixtureDumpPage({super.key});

  @override
  State<OcrFixtureDumpPage> createState() => _OcrFixtureDumpPageState();
}

class _OcrFixtureDumpPageState extends State<OcrFixtureDumpPage> {
  String _recordType = 'baptism';
  String _page = 'left';
  String? _json;
  bool _busy = false;

  Future<void> _capture() async {
    setState(() => _busy = true);
    try {
      final files = await OcrImagePick.pickRegisterPages(
        context,
        allowMultiple: false,
        includeCamera: ocrSupportsCamera,
      );
      if (files.isEmpty) return;
      final xfile = files.first;
      final result =
          await OcrService.instance.recognizeText(File(xfile.path));
      final cells = RegisterOcrScanHelper.linesFromBlocks(result.blocks);
      final json = buildFixtureJson(
        image: xfile.name,
        recordType: _recordType,
        page: _page,
        cells: cells,
        flatText: result.text,
      );

      final dir = await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/${xfile.name}.ocr.json');
      await out.writeAsString(json);
      await Clipboard.setData(ClipboardData(text: json));
      debugPrint('OCR FIXTURE (${xfile.name}):\n$json');
      if (mounted) setState(() => _json = json);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR Fixture Dump (debug)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _recordType,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                          value: 'baptism', child: Text('baptism')),
                      DropdownMenuItem(
                          value: 'marriage', child: Text('marriage')),
                    ],
                    onChanged: (v) =>
                        setState(() => _recordType = v ?? 'baptism'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    value: _page,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'left', child: Text('left')),
                      DropdownMenuItem(value: 'right', child: Text('right')),
                    ],
                    onChanged: (v) => setState(() => _page = v ?? 'left'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _capture,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Pick image & dump fixture JSON'),
            ),
            const SizedBox(height: 12),
            if (_json != null)
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    _json!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Register the debug-only route**

In `lib/app/router.dart`, add this route inside the top-level `routes: [ ... ]` list of `createRouter()` (near the other top-level `GoRoute`s around line 125), guarded so it exists only in debug builds. Add the imports `package:flutter/foundation.dart` (for `kDebugMode`) and `../dev/ocr_fixture_dump.dart` at the top if not present:

```dart
      if (kDebugMode)
        GoRoute(
          path: '/dev/ocr-dump',
          builder: (context, state) => const OcrFixtureDumpPage(),
        ),
```

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/ocr/fixture_dump_json_test.dart`
Expected: PASS.
Run: `flutter analyze lib/dev/ocr_fixture_dump.dart lib/app/router.dart`
Expected: No new errors.

- [ ] **Step 6: Commit**

```bash
git add lib/dev/ocr_fixture_dump.dart lib/app/router.dart test/ocr/fixture_dump_json_test.dart
git commit -m "feat(ocr): add debug-only fixture capture tool + route"
```

---

### Task 5: Capture real fixtures, key ground truth, set baselines

Human-in-the-loop: generate the four real fixtures and lock in the baseline floor. This task has manual steps and cannot be fully automated (ML Kit needs a device).

**Files:**
- Create: `test/ocr/fixtures/baptism_left.json`, `baptism_left.expected.json`
- Create: `test/ocr/fixtures/baptism_right.json`, `baptism_right.expected.json`
- Create: `test/ocr/fixtures/marriage_left.json`, `marriage_left.expected.json`
- Create: `test/ocr/fixtures/marriage_right.json`, `marriage_right.expected.json`
- Modify: `test/ocr/register_ocr_fixtures_test.dart` (add baseline-asserting cases)

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces: committed real fixtures + a `baselines` map in the test.

- [ ] **Step 1: Capture the four fixtures on an emulator**

Start an Android emulator, run the app in debug (`flutter run`), navigate to `/dev/ocr-dump`. For each of the four images in `book-scan/` (upload via the picker), set the correct `recordType`/`page`, tap capture, and save the copied JSON to the matching fixture file:
- `741704936_...` → `baptism_left.json` (recordType `baptism`, page `left`)
- `742001331_...` → `baptism_right.json` (`baptism`, `right`)
- `743588549_...` → `marriage_left.json` (`marriage`, `left`)
- `741693507_...` → `marriage_right.json` (`marriage`, `right`)

Rename each fixture's `"image"` field to the source filename for traceability.

- [ ] **Step 2: Draft ground truth from the photos**

For each fixture, create `<name>.expected.json`: a JSON array of the correct rows, keyed by `lineNo`, using the scored-field keys (`name`, `date`, `placeAndBirthDate`, `parents`, `residentsOf`, `minister`, `sponsors`). Transcribe the **first 10–15 rows** of each page from the source photo. Leave fields absent when that column is on the other page of the spread (e.g. left-page baptism has no `minister`/`sponsors`). Example row:

```json
{ "lineNo": "1", "name": "Alberto Saligumba", "date": "07 January 2008", "placeAndBirthDate": "Tuburan, Villaflor, Oroquieta City" }
```

- [ ] **Step 3: User verification checkpoint**

Have the user review each `<name>.expected.json` against the photo and correct handwritten-name readings. **Do not proceed until the user confirms** — the baselines are only meaningful if ground truth is right.

- [ ] **Step 4: Measure the current baseline**

Extend `test/ocr/register_ocr_fixtures_test.dart` to loop the four fixtures, print each report, and record the observed `headline`. Run:

Run: `flutter test test/ocr/register_ocr_fixtures_test.dart`
Read the printed `headline` for each fixture from the output.

- [ ] **Step 5: Lock baselines into the test**

Add to `test/ocr/register_ocr_fixtures_test.dart` (replace the synthetic-only body with the real set; keep the synthetic test too). Use the measured headlines from Step 4, rounded **down** to 2 decimals, as the floor:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'support/ocr_scoring.dart';
import 'support/register_ocr_fixture.dart';
import 'package:parishrecord/services/register_ocr_scan_helper.dart';

void main() {
  // Baseline floors: measured from the current pipeline (Step 4), rounded
  // down. Raise only after a verified improvement; never lower silently.
  const baselines = <String, double>{
    'baptism_left': 0.0, // TODO(step4): set to measured floor
    'baptism_right': 0.0,
    'marriage_left': 0.0,
    'marriage_right': 0.0,
  };

  for (final name in baselines.keys) {
    test('$name meets baseline via parseEntriesFromCells', () {
      final fixture = loadFixture(name);
      final expected = loadExpected(name);
      final entries =
          RegisterOcrScanHelper.parseEntriesFromCells(fixture.cells);
      final actual = entries.map(entryToFieldMap).toList();
      final score = scoreRows(expected: expected, actual: actual);
      // ignore: avoid_print
      print(score.report(name));
      expect(score.headline, greaterThanOrEqualTo(baselines[name]!));
    });
  }
}
```

Replace each `0.0` with the Step 4 measured floor (this is the one place the plan intentionally defers a literal value — it is data measured at implementation time, not a design gap).

- [ ] **Step 6: Run the full OCR suite**

Run: `flutter test test/ocr/`
Expected: PASS — all fixtures meet their baselines; reports print per-field means.

- [ ] **Step 7: Commit**

```bash
git add test/ocr/fixtures/ test/ocr/register_ocr_fixtures_test.dart
git commit -m "test(ocr): add real register fixtures + baseline floors"
```

---

## Self-Review

**Spec coverage:**
- `parseEntriesFromCells` seam + `OcrLineBox` JSON → Task 1 ✅
- Fixture format (cells + flatText + recordType/page) → Task 3 (schema) + Task 5 (real data) ✅
- Debug `kDebugMode` capture tool → Task 4 ✅
- Four fixtures (2 baptism + 2 marriage) → Task 5 ✅
- Hand-keyed, user-verified ground truth → Task 5 Steps 2–3 ✅
- Scoring util (normalize, Levenshtein similarity, per-field means, row precision/recall, headline, report) → Task 2 ✅
- Golden tests + baseline ratchet → Task 3 (synthetic) + Task 5 (real floors) ✅
- Non-goals (merge, deskew, cloud OCR, web) → not in any task ✅

**Placeholder scan:** The only deferred literals are the baseline floors in Task 5 Step 5, which are runtime measurements, not design placeholders — flagged explicitly. All code steps contain full implementations.

**Type consistency:** `OcrLineBox.fromJson`/`toJson`, `parseEntriesFromCells(List<OcrLineBox>)`, `scoreRows({expected, actual, weights})` → `FixtureScore`, `scoredFields`, `entryToFieldMap` (maps `baptismDateText` → `date`), `loadFixture`/`loadExpected`, `buildFixtureJson({image, recordType, page, cells, flatText})` are used consistently across Tasks 1–5. Fixture field keys match `scoredFields` in every task.

**Resolved:** pub package name confirmed as `parishrecord`; all test imports use `package:parishrecord/...`.
