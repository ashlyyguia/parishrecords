# OCR Grid Parser Tuning (Baptism-Left) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn real OCR.space cells for the baptism-left register page into ~24 clean, correctly-separated rows via a pitch-based grid reconstructor, measured against a committed real fixture + hand-keyed ground truth.

**Architecture:** A new pure `reconstructBaptismGrid(cells)` builds the row grid from the register's regular row pitch (not the half-recognized "No." column), assigns cells to (row, column), merges two-line child names, and emits `RegisterOcrEntry` rows. It's wired as the top-priority strategy in `parseEntriesFromCells` with a plausibility guardrail; the accuracy harness scores it.

**Tech Stack:** Flutter/Dart, `flutter_test`, existing OCR harness (`test/ocr/support/ocr_scoring.dart`, `register_ocr_fixture.dart`). Node (one-liner) to convert the captured fixture.

## Global Constraints

- Reconstructor is pure: `List<OcrLineBox>` in → `List<RegisterOcrEntry>` out, no I/O, no engine coupling.
- Must never regress the on-device path: `parseEntriesFromCells` uses the reconstructor only when it returns a plausible result (≥3 rows), else the existing strategies run unchanged.
- Ground truth is authoritative only after user verification.
- Acceptance target (baptism-left golden test): `rowRecall >= 0.9` AND `fieldMeans['name'] >= 0.6`. Place/parents/residents are reported, not gated, in this spec.
- Reuse the existing harness helpers; do not fork the scoring/loader code.
- Flutter package name is `parishrecord`. Tests live under `test/ocr/`.
- Scope: baptism-left page only. Baptism-right, marriage, cross-page merge, and deep per-field tuning are out.

---

### Task 1: Real fixture + hand-keyed ground truth

Commit the captured OCR.space cells in harness format and the verified expected rows.

**Files:**
- Create: `test/ocr/fixtures/baptism_left.json` (from `book-scan/baptism_left.cells.json`)
- Create: `test/ocr/fixtures/baptism_left.expected.json`

**Interfaces:**
- Consumes: `book-scan/baptism_left.cells.json` (`{text, cells:[{text,left,top,width,height}]}`, already captured).
- Produces: fixture readable by `loadFixture('baptism_left')` and expected readable by `loadExpected('baptism_left')`.

- [ ] **Step 1: Convert the captured cells into the harness fixture schema**

Run (from repo root):

```bash
node -e "const {text,cells}=require('./book-scan/baptism_left.cells.json'); require('fs').writeFileSync('test/ocr/fixtures/baptism_left.json', JSON.stringify({image:'baptism_left', recordType:'baptism', page:'left', capturedWith:'ocrspace', flatText:text, cells}));"
```

Verify it wrote: `node -e "const f=require('./test/ocr/fixtures/baptism_left.json'); console.log(f.recordType, f.page, f.cells.length, 'cells')"`
Expected: `baptism left 401 cells`.

- [ ] **Step 2: Draft the ground truth (row No. + child name for all 24 rows)**

Create `test/ocr/fixtures/baptism_left.expected.json` with this first-pass transcription (only `lineNo` + `name` are gated; other fields can be added later):

```json
[
  { "lineNo": "1", "name": "Alberto Saligumba" },
  { "lineNo": "2", "name": "Jhon Frix Jay Dadiang" },
  { "lineNo": "3", "name": "Elliana Eltagon" },
  { "lineNo": "4", "name": "Erica Jane Dejeno" },
  { "lineNo": "5", "name": "Frezhelia Zhei Baloncio" },
  { "lineNo": "6", "name": "Princess Federlyn Jean Taboco" },
  { "lineNo": "7", "name": "Rachelle Maravillas" },
  { "lineNo": "8", "name": "Princess Kyana Jerusalem" },
  { "lineNo": "9", "name": "Glaiza Marie Suico" },
  { "lineNo": "10", "name": "Aljean Grace Taboco" },
  { "lineNo": "11", "name": "Clint Julius Cayubit" },
  { "lineNo": "12", "name": "James Castillano" },
  { "lineNo": "13", "name": "Mariel Sarancial" },
  { "lineNo": "14", "name": "Robert Jr Somoson" },
  { "lineNo": "15", "name": "EJ Digal" },
  { "lineNo": "16", "name": "Aston Martin Saguin" },
  { "lineNo": "17", "name": "Dwayne Banga" },
  { "lineNo": "18", "name": "Haziel Jane Amante" },
  { "lineNo": "19", "name": "Jhon Michael Ending" },
  { "lineNo": "20", "name": "Rowena Antido" },
  { "lineNo": "21", "name": "Richard Jr Daque" },
  { "lineNo": "22", "name": "Cyrus Franz Sabaiton" },
  { "lineNo": "23", "name": "Klein Mark Cabonita" },
  { "lineNo": "24", "name": "Crislyn Joy Olmillo" }
]
```

- [ ] **Step 3: USER VERIFICATION CHECKPOINT**

Have the user compare each name in `baptism_left.expected.json` against the source photo (`book-scan/741704936_...n.jpg`) and correct any misreads — especially rows 22–24, which are uncertain. **Do not proceed until the user confirms.** The accuracy metric is only meaningful once ground truth is right.

- [ ] **Step 4: Commit**

```bash
git add -f test/ocr/fixtures/baptism_left.json test/ocr/fixtures/baptism_left.expected.json
git commit -m "test(ocr): add real baptism-left OCR.space fixture + verified ground truth"
```

> `-f` because `test/ocr/fixtures/` may sit under a broadly-ignored path; these are committed test data with no secrets.

---

### Task 2: `reconstructBaptismGrid` (pure) + unit tests

Build the grid reconstructor and prove it on synthetic cells. No integration yet.

**Files:**
- Modify: `lib/services/register_ocr_scan_helper.dart` (add two static methods)
- Test: `test/ocr/reconstruct_baptism_grid_test.dart`

**Interfaces:**
- Consumes: existing `_clusterIntoRows`, `_detectColumnCenters(rows, mergeGap:)`, `_nearestColumnIndex`, `_uuid`, `OcrLineBox.centerX/centerY`, `RegisterOcrParser.entryFromColumnTexts(cols, rawLine:, id:)`.
- Produces: `static List<RegisterOcrEntry> RegisterOcrScanHelper.reconstructBaptismGrid(List<OcrLineBox> cells)`.

- [ ] **Step 1: Write the failing test**

Create `test/ocr/reconstruct_baptism_grid_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/register_ocr_scan_helper.dart';

// Three evenly-pitched rows (pitch 50), each with a two-line child name and
// a recognized No. cell, across 5 columns (No, Name, Place&Birth, Parents,
// Residents). The reconstructor must yield 3 rows with merged names.
List<OcrLineBox> _syntheticCells() {
  final cells = <OcrLineBox>[];
  final names = [
    ['Alberto', 'Saligumba'],
    ['Elliana', 'Eltagon'],
    ['Erica', 'Dejeno'],
  ];
  final places = ['07 January 2008', '08 February 2016', '22 May 2015'];
  for (var r = 0; r < 3; r++) {
    final top = 100.0 + r * 50;
    cells.add(OcrLineBox(text: '${r + 1}', top: top, left: 10, width: 15, height: 18));
    cells.add(OcrLineBox(text: names[r][0], top: top, left: 140, width: 90, height: 18));
    cells.add(OcrLineBox(text: names[r][1], top: top + 20, left: 140, width: 110, height: 18));
    cells.add(OcrLineBox(text: places[r], top: top, left: 380, width: 150, height: 18));
    cells.add(OcrLineBox(text: 'Arnel / Edelina', top: top, left: 680, width: 200, height: 18));
    cells.add(OcrLineBox(text: 'Villaflor', top: top, left: 930, width: 120, height: 18));
  }
  return cells;
}

void main() {
  test('reconstructBaptismGrid yields one row per pitch, merging two-line names', () {
    final entries = RegisterOcrScanHelper.reconstructBaptismGrid(_syntheticCells());
    expect(entries, hasLength(3));
    expect(entries[0].name.toLowerCase(), contains('alberto'));
    expect(entries[0].name.toLowerCase(), contains('saligumba'));
    expect(entries[1].name.toLowerCase(), contains('elliana'));
    expect(entries[2].name.toLowerCase(), contains('erica'));
    expect(entries.map((e) => e.lineNo), ['1', '2', '3']);
  });

  test('returns empty for too few cells', () {
    expect(RegisterOcrScanHelper.reconstructBaptismGrid(const []), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ocr/reconstruct_baptism_grid_test.dart`
Expected: FAIL — `reconstructBaptismGrid` is undefined.

- [ ] **Step 3: Implement the reconstructor**

In `lib/services/register_ocr_scan_helper.dart`, add both methods inside `RegisterOcrScanHelper` (e.g. right after `parseEntriesFromCells`):

```dart
  /// Reconstructs baptism register rows from a regular row pitch (engine-
  /// agnostic), instead of the sparse/misread "No." column. Returns [] when the
  /// layout doesn't look like a griddable baptism page (caller falls back).
  static List<RegisterOcrEntry> reconstructBaptismGrid(List<OcrLineBox> cells) {
    if (cells.length < 8) return const [];

    final rows0 = _clusterIntoRows(cells);
    if (rows0.length < 3) return const [];

    final imageWidth = cells
        .map((c) => c.left + c.width)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final mergeGap = (imageWidth * 0.025).clamp(18.0, 55.0);
    final columnCenters = _detectColumnCenters(rows0, mergeGap: mergeGap);
    if (columnCenters.length < 3) return const [];

    // No.-column numeric cells → pitch + phase.
    final secondCenter =
        columnCenters.length > 1 ? columnCenters[1] : columnCenters.first + 120;
    final leftBand =
        columnCenters.first + (secondCenter - columnCenters.first) * 0.5;
    final anchors = <({int no, double top})>[];
    for (final c in cells) {
      if (c.centerX > leftBand) continue;
      final m = RegExp(r'^(\d{1,2})$').firstMatch(c.text.trim());
      if (m != null) anchors.add((no: int.parse(m.group(1)!), top: c.centerY));
    }
    anchors.sort((a, b) => a.top.compareTo(b.top));

    final centerYs = cells.map((c) => c.centerY).toList()..sort();
    final firstTop = centerYs.first;
    final lastTop = centerYs.last;

    var pitch = _estimatePitch(anchors);
    if (pitch <= 0) {
      pitch = (lastTop - firstTop) / (rows0.length - 1);
    }
    if (pitch <= 4) return const [];

    double phase;
    if (anchors.isNotEmpty) {
      final phases = anchors.map((a) => a.top - (a.no - 1) * pitch).toList()
        ..sort();
      phase = phases[phases.length ~/ 2];
    } else {
      phase = firstTop;
    }

    final n = ((lastTop - phase) / pitch).round() + 1;
    if (n < 2 || n > 60) return const [];

    final rowCenters = [for (var i = 0; i < n; i++) phase + i * pitch];
    final tol = pitch * 0.6;

    final grid = List.generate(
      n,
      (_) => List.generate(columnCenters.length, (_) => <OcrLineBox>[]),
    );
    for (final c in cells) {
      var ri = -1;
      var best = double.infinity;
      for (var i = 0; i < n; i++) {
        final d = (c.centerY - rowCenters[i]).abs();
        if (d < best) {
          best = d;
          ri = i;
        }
      }
      if (ri < 0 || best > tol) continue; // headers / stray rows dropped
      final ci = _nearestColumnIndex(c.centerX, columnCenters);
      if (ci < 0 || ci >= columnCenters.length) continue;
      grid[ri][ci].add(c);
    }

    final entries = <RegisterOcrEntry>[];
    var lineNo = 1;
    for (var r = 0; r < n; r++) {
      final cols = <String>[];
      for (var col = 0; col < columnCenters.length; col++) {
        final inCol = grid[r][col]
          ..sort((a, b) {
            final y = a.top.compareTo(b.top);
            return y != 0 ? y : a.left.compareTo(b.left);
          });
        cols.add(inCol.map((c) => c.text).join(' ').trim());
      }
      final entry = RegisterOcrParser.entryFromColumnTexts(
        cols,
        rawLine: cols.join('\t'),
        id: _uuid.v4(),
      );
      if (entry != null && entry.name.trim().length >= 2) {
        entry.lineNo = '${lineNo++}';
        entries.add(entry);
      }
    }
    return entries;
  }

  static double _estimatePitch(List<({int no, double top})> anchors) {
    if (anchors.length < 2) return 0;
    final pitches = <double>[];
    for (var i = 1; i < anchors.length; i++) {
      final dn = anchors[i].no - anchors[i - 1].no;
      final dt = anchors[i].top - anchors[i - 1].top;
      if (dn > 0 && dt > 0) pitches.add(dt / dn);
    }
    if (pitches.isEmpty) return 0;
    pitches.sort();
    return pitches[pitches.length ~/ 2];
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ocr/reconstruct_baptism_grid_test.dart`
Expected: PASS (2 tests). If the 3-row test fails, the synthetic geometry is deterministic — fix the reconstructor, not the test.

- [ ] **Step 5: Commit**

```bash
git add lib/services/register_ocr_scan_helper.dart test/ocr/reconstruct_baptism_grid_test.dart
git commit -m "feat(ocr): add pitch-based reconstructBaptismGrid (pure)"
```

---

### Task 3: Integrate + measure + tune to target

Wire the reconstructor in, score it on the real fixture, and tune knobs until the target is met.

**Files:**
- Modify: `lib/services/register_ocr_scan_helper.dart:289` (`parseEntriesFromCells`)
- Test: `test/ocr/baptism_left_cloud_fixture_test.dart`

**Interfaces:**
- Consumes: `reconstructBaptismGrid` (Task 2); `scanResultFromCloud`; harness `loadFixture`/`loadExpected`/`entryToFieldMap`/`scoreRows` (Task 1 fixture).
- Produces: reconstructor wired as the top-priority strategy; a passing golden test with committed floors.

- [ ] **Step 1: Wire the reconstructor as the top-priority strategy (with guardrail)**

In `parseEntriesFromCells` (line 289), insert the reconstructor call right after the empty check:

```dart
  static List<RegisterOcrEntry> parseEntriesFromCells(List<OcrLineBox> cells) {
    if (cells.isEmpty) return [];

    final grid = reconstructBaptismGrid(cells);
    if (grid.length >= 3) return grid;

    final imageWidth = cells
        .map((c) => c.left + c.width)
        .fold<double>(0, (a, b) => a > b ? a : b);
    // ... rest of the existing method unchanged ...
```

Leave the remainder of the method untouched (the on-device fallback path).

- [ ] **Step 2: Write the golden test with the target asserts**

Create `test/ocr/baptism_left_cloud_fixture_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'support/ocr_scoring.dart';
import 'support/register_ocr_fixture.dart';
import 'package:parishrecord/services/register_ocr_scan_helper.dart';

void main() {
  test('baptism-left OCR.space fixture parses into clean, scored rows', () {
    final fixture = loadFixture('baptism_left');
    final expected = loadExpected('baptism_left');

    final scan = RegisterOcrScanHelper.scanResultFromCloud(
      fixture.cells,
      fixture.flatText,
      recordType: 'baptism',
    );
    final actual = scan.entries.map(entryToFieldMap).toList();
    final score = scoreRows(expected: expected, actual: actual);
    // ignore: avoid_print
    print(score.report('baptism_left'));

    expect(score.rowRecall, greaterThanOrEqualTo(0.9));
    expect(score.fieldMeans['name'], greaterThanOrEqualTo(0.6));
  });
}
```

- [ ] **Step 3: Run it to capture the BASELINE and see where it stands**

Run: `flutter test test/ocr/baptism_left_cloud_fixture_test.dart`
Read the printed `report('baptism_left')` — record `rowRecall` and `fieldMeans['name']` as the baseline. With the reconstructor wired, expect a large jump from the scrambled 102-row result toward ~24 rows.

- [ ] **Step 4: Tune knobs until the target is met**

If `rowRecall < 0.9` or `name < 0.6`, adjust these named knobs in `reconstructBaptismGrid` and re-run, using the printed report to see which is off:

- **Too many/few rows (rowRecall low, row count ≠ 24):** the row `tol` factor (`pitch * 0.6`) or the header cutoff — raise `tol` toward `0.7` to catch offset rows, lower toward `0.5` if adjacent rows bleed together. Check `n` (projected row count) vs 24.
- **Names merged across rows or split:** pitch/phase estimate — verify `_estimatePitch` median and the `phase` median; if pitch is off, adjacent name lines land in the wrong row.
- **Columns shifted (name field holds place/parents text):** the column→field mapping. If `_detectColumnCenters` returns more centers than expected (e.g. the narrow "L/Ill" column), drop the narrowest/sparsest center before building `cols` so the order matches `entryFromColumnTexts`'s `[No, Name, Place, Parents, Residents]`.
- **`leftBand` mis-detects No. anchors:** adjust the `* 0.5` factor.

Re-run after each single change. Do not weaken the test thresholds to pass — fix the reconstruction.

- [ ] **Step 5: Lock the achieved floors**

Once green, set the two `expect` thresholds in the golden test to the achieved values rounded **down** to 2 decimals (never above what was measured), so the test is a ratchet. Keep them ≥ the spec target (`rowRecall >= 0.9`, `name >= 0.6`); if the tuned result can't reach the target, STOP and report — do not lower below target.

- [ ] **Step 6: Verify the whole OCR suite still passes**

Run: `flutter test test/ocr/`
Expected: PASS (harness golden tests, reconstructor unit tests, cloud builder, and the new baptism-left fixture test).
Run: `flutter analyze lib/services/register_ocr_scan_helper.dart`
Expected: no new errors.

- [ ] **Step 7: Commit**

```bash
git add lib/services/register_ocr_scan_helper.dart test/ocr/baptism_left_cloud_fixture_test.dart
git commit -m "feat(ocr): grid reconstruction clears baptism-left cloud rows to target"
```

---

## Self-Review

**Spec coverage:**
- Pitch-based `reconstructBaptismGrid` (columns, row grid from pitch, assign+merge, build entries) → Task 2 ✅
- Integration as top-priority strategy with plausibility guardrail → Task 3 Step 1 ✅
- Real fixture in harness schema + hand-keyed, user-verified ground truth → Task 1 ✅
- Scoring reuse (`scanResultFromCloud` → `entryToFieldMap` → `scoreRows`) → Task 3 ✅
- Baseline captured; target `rowRecall >= 0.9` & `name >= 0.6` gated and ratcheted → Task 3 Steps 3–5 ✅
- Unit tests (synthetic) + golden test (real) → Task 2 + Task 3 ✅
- Non-goals (right page, marriage, cross-page merge, deep per-field tuning) → not in any task ✅

**Placeholder scan:** No TBD/TODO. Task 3 Step 4 is a concrete measure-adjust loop with named knobs and a concrete pass condition (the two thresholds), not a vague instruction. The baseline/floor numbers are runtime measurements, explicitly captured at implementation time.

**Type consistency:** `reconstructBaptismGrid(List<OcrLineBox>) -> List<RegisterOcrEntry>` and `_estimatePitch(List<({int no, double top})>) -> double` are defined in Task 2 and consumed in Task 3. `OcrLineBox` positional-named constructor usage in the synthetic test matches the class (`text/top/left/width/height`). Fixture/expected keys (`lineNo`, `name`) match `entryToFieldMap` and `scoreRows` matching-by-`lineNo`. `scanResultFromCloud(cells, flatText, recordType:)` matches its definition from the prior cloud-integration work.
