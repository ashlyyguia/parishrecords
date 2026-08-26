# Baptismal OCR Review — Add/Delete/Merge Rows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let staff insert, delete, and merge rows in the baptismal OCR review table so they can correct over/under-counted OCR output before saving.

**Architecture:** Pure in-memory edits on the already-loaded `List<BaptismalRegisterRow>` in the scan page. The model gains a `blank()` factory and a pure `mergedWith()` method; the review-table widget gains three optional callbacks and a per-row overflow menu; the scan page wires the callbacks to `setState` list mutations. No backend, no infrastructure.

**Tech Stack:** Flutter + `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-26-baptismal-review-row-editing-design.md`

## Global Constraints

- **Branch:** all work lands on `feature/baptismal-ocr-record`. Never commit to `main`/`master`/`development`/`ocr`.
- **Scope:** add/delete/merge only — no split, undo, or drag-reorder. Flutter only.
- **Field keys:** operate over `baptismalFieldKeys` (`nameOfChild, placeAndBirthDate, parents, residentsOf, dateOfBaptism, minister, sponsors`).
- **`flutter analyze` must be clean** on touched files before each commit.
- **`docs/` is gitignored** but plan/spec files are tracked — use `git add -f` for docs.

## File Structure

| File | Change |
|------|--------|
| `lib/models/baptismal_register_row.dart` | Add `BaptismalRegisterRow.blank()` + `mergedWith()`. |
| `test/baptismal_register_row_test.dart` | Model tests. |
| `lib/widgets/baptismal_ocr_review_table.dart` | Add `onInsertRowBelow`/`onDeleteRow`/`onMergeWithNext` + per-row menu. |
| `test/baptismal_ocr_review_table_test.dart` | Widget menu tests. |
| `lib/screens/admin/pages/baptismal_ocr_scan_page.dart` | Wire callbacks to `_rows` mutations. |
| `test/baptismal_ocr_scan_page_test.dart` | Scan-page row-op tests. |

---

### Task 1: Model — `blank()` and `mergedWith()`

**Files:**
- Modify: `lib/models/baptismal_register_row.dart`
- Test: `test/baptismal_register_row_test.dart`

**Interfaces:**
- Consumes: `baptismalFieldKeys`, `OcrField` (with `copyWith({String? value})` that marks the result `edited`), `BaptismalRegisterRow({lineNo, fields, selected})`, `field(key)`.
- Produces:
  - `factory BaptismalRegisterRow.blank()` — empty `lineNo`, `selected == true`, an `OcrField(value:'', confidence:1)` per key.
  - `BaptismalRegisterRow mergedWith(BaptismalRegisterRow other)` — pure; per key the value is the two trimmed values space-joined (empties skipped), marked `edited`; `lineNo == this.lineNo`; `selected == this.selected || other.selected`.

- [ ] **Step 1: Write the failing tests**

Add to `test/baptismal_register_row_test.dart`:

```dart
  BaptismalRegisterRow rowWith(Map<String, String> vals, {bool selected = true, String lineNo = ''}) =>
      BaptismalRegisterRow(
        lineNo: lineNo,
        selected: selected,
        fields: {for (final k in baptismalFieldKeys) k: OcrField(value: vals[k] ?? '', confidence: 0.9)},
      );

  test('blank() has every field empty and is selected', () {
    final r = BaptismalRegisterRow.blank();
    expect(r.lineNo, '');
    expect(r.selected, isTrue);
    for (final k in baptismalFieldKeys) {
      expect(r.field(k).value, '');
    }
  });

  test('mergedWith space-joins per field, skips empties, marks edited, unions selected', () {
    final a = rowWith({'nameOfChild': 'RENE', 'placeAndBirthDate': 'ZONE1'}, selected: false, lineNo: '1');
    final b = rowWith({'nameOfChild': 'HAGANAS', 'minister': 'FR.X'}, selected: true, lineNo: '2');
    final m = a.mergedWith(b);
    expect(m.field('nameOfChild').value, 'RENE HAGANAS');
    expect(m.field('placeAndBirthDate').value, 'ZONE1'); // other empty -> kept
    expect(m.field('minister').value, 'FR.X'); // this empty -> kept
    expect(m.field('nameOfChild').edited, isTrue);
    expect(m.lineNo, '1');
    expect(m.selected, isTrue);
  });
```

Confirm the test file imports the model (`package:parishrecord/models/baptismal_register_row.dart`); it already does.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/baptismal_register_row_test.dart`
Expected: FAIL — `blank`/`mergedWith` undefined.

- [ ] **Step 3: Implement**

In `lib/models/baptismal_register_row.dart`, inside `class BaptismalRegisterRow`, add after the `factory BaptismalRegisterRow.fromJson(...)`:

```dart
  /// A fresh, empty, selected row — used when a reviewer inserts a register
  /// entry OCR missed. Confidence 1 so it is never flagged low-confidence
  /// (an empty value isn't flagged anyway).
  factory BaptismalRegisterRow.blank() {
    return BaptismalRegisterRow(
      lineNo: '',
      fields: {
        for (final key in baptismalFieldKeys) key: OcrField(value: '', confidence: 1),
      },
    );
  }

  /// Combines this row with [other] into one — the fix for a single register
  /// entry OCR split across two rows. Each field's values are space-joined
  /// (empties skipped) and marked edited (a human triggered the merge); the
  /// line number is kept from this row; the result is selected if either was.
  BaptismalRegisterRow mergedWith(BaptismalRegisterRow other) {
    final merged = <String, OcrField>{};
    for (final key in baptismalFieldKeys) {
      final a = field(key).value.trim();
      final b = other.field(key).value.trim();
      final joined = [a, b].where((s) => s.isNotEmpty).join(' ');
      merged[key] = field(key).copyWith(value: joined);
    }
    return BaptismalRegisterRow(
      lineNo: lineNo,
      fields: merged,
      selected: selected || other.selected,
    );
  }
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/baptismal_register_row_test.dart && flutter analyze lib/models/baptismal_register_row.dart`
Expected: PASS; analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/models/baptismal_register_row.dart test/baptismal_register_row_test.dart
git commit -m "feat(ocr): add blank() and mergedWith() to BaptismalRegisterRow"
```

---

### Task 2: Review table — per-row menu + callbacks

**Files:**
- Modify: `lib/widgets/baptismal_ocr_review_table.dart`
- Test: `test/baptismal_ocr_review_table_test.dart`

**Interfaces:**
- Consumes: Task 1 model.
- Produces: three optional constructor callbacks `void Function(int rowIndex)? onInsertRowBelow, onDeleteRow, onMergeWithNext`; a per-row `PopupMenuButton` keyed `row-menu-$i` with items "Insert blank row below" (`insert`), "Merge with row below" (`merge`, only when `onMergeWithNext != null && i < rows.length - 1`), "Delete row" (`delete`). Rendered only when at least one callback is set.

- [ ] **Step 1: Write the failing tests**

Add to `test/baptismal_ocr_review_table_test.dart` (uses the file's existing `harness` + `makeRow`):

```dart
  testWidgets('row menu fires insert / delete with the row index', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow(), makeRow()],
      issues: const [],
      onChanged: (_, _, _) {},
      onSelectedChanged: (_, _) {},
      onInsertRowBelow: (i) => events.add('insert$i'),
      onDeleteRow: (i) => events.add('delete$i'),
      onMergeWithNext: (i) => events.add('merge$i'),
    )));
    await tester.tap(find.byKey(const ValueKey('row-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert blank row below'));
    await tester.pumpAndSettle();
    expect(events, contains('insert0'));

    await tester.tap(find.byKey(const ValueKey('row-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete row'));
    await tester.pumpAndSettle();
    expect(events, contains('delete1'));
  });

  testWidgets('merge action is hidden on the last row', (tester) async {
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow(), makeRow()],
      issues: const [],
      onChanged: (_, _, _) {},
      onSelectedChanged: (_, _) {},
      onMergeWithNext: (_) {},
    )));
    // Row 0 (not last) offers merge; row 1 (last) does not.
    await tester.tap(find.byKey(const ValueKey('row-menu-0')));
    await tester.pumpAndSettle();
    expect(find.text('Merge with row below'), findsOneWidget);
    await tester.tap(find.text('Merge with row below')); // close menu
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('row-menu-1')));
    await tester.pumpAndSettle();
    expect(find.text('Merge with row below'), findsNothing);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/baptismal_ocr_review_table_test.dart -j 1 --plain-name "row menu"`
Expected: FAIL — no `row-menu-0`.

- [ ] **Step 3: Add the callbacks to the widget**

In `lib/widgets/baptismal_ocr_review_table.dart`, add to the constructor and fields (alongside `onRowTap`):

```dart
    this.onInsertRowBelow,
    this.onDeleteRow,
    this.onMergeWithNext,
```
```dart
  final void Function(int rowIndex)? onInsertRowBelow;
  final void Function(int rowIndex)? onDeleteRow;
  final void Function(int rowIndex)? onMergeWithNext;
```

- [ ] **Step 4: Add the menu builder + a "has actions" getter**

Add these methods inside `_BaptismalOcrReviewTableState`:

```dart
  bool get _hasRowActions =>
      widget.onInsertRowBelow != null ||
      widget.onDeleteRow != null ||
      widget.onMergeWithNext != null;

  Widget _rowMenu(BuildContext context, int index) {
    final canMerge =
        widget.onMergeWithNext != null && index < widget.rows.length - 1;
    return PopupMenuButton<String>(
      key: ValueKey('row-menu-$index'),
      icon: const Icon(Icons.more_vert, size: 18),
      tooltip: 'Row actions',
      onSelected: (v) {
        switch (v) {
          case 'insert':
            widget.onInsertRowBelow?.call(index);
            break;
          case 'merge':
            widget.onMergeWithNext?.call(index);
            break;
          case 'delete':
            widget.onDeleteRow?.call(index);
            break;
        }
      },
      itemBuilder: (context) => [
        if (widget.onInsertRowBelow != null)
          const PopupMenuItem(value: 'insert', child: Text('Insert blank row below')),
        if (canMerge)
          const PopupMenuItem(value: 'merge', child: Text('Merge with row below')),
        if (widget.onDeleteRow != null)
          const PopupMenuItem(value: 'delete', child: Text('Delete row')),
      ],
    );
  }
```

- [ ] **Step 5: Render the menu in both layouts**

In the **card** layout `_rowCard`, the leading `Row(children: [ Checkbox(...), Text('Line'...), ... ])` — add the menu at the end of that Row so it sits on the card header:

```dart
                  if (_hasRowActions) _rowMenu(context, index),
```
(insert it as the last child of that `Row`, after the line-no `SizedBox`.)

In the **wide table** `_tableRow`, add the menu as the first child of the row `Row(...)`, before the select `SizedBox`:

```dart
          if (_hasRowActions)
            SizedBox(width: _menuWidth, child: _rowMenu(context, index)),
```
Add the constant near `_selectWidth`:
```dart
  static const double _menuWidth = 40;
```
And in `_headerRow`, add a matching leading spacer as the first child (before the select `SizedBox`) so the header aligns:
```dart
          if (_hasRowActions) const SizedBox(width: _menuWidth),
```
And include it in `_totalWidth`:
```dart
    var w = _selectWidth + _lineNoWidth + (_hasRowActions ? _menuWidth : 0);
```

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test test/baptismal_ocr_review_table_test.dart -j 1 && flutter analyze lib/widgets/baptismal_ocr_review_table.dart`
Expected: PASS (existing + 2 new); analyze clean.

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/baptismal_ocr_review_table.dart test/baptismal_ocr_review_table_test.dart
git commit -m "feat(ocr): per-row insert/delete/merge menu in the OCR review table"
```

---

### Task 3: Scan page — wire the row operations

**Files:**
- Modify: `lib/screens/admin/pages/baptismal_ocr_scan_page.dart`
- Test: `test/baptismal_ocr_scan_page_test.dart`

**Interfaces:**
- Consumes: Task 1 (`BaptismalRegisterRow.blank()`, `mergedWith`) and Task 2 (table callbacks).

- [ ] **Step 1: Write the failing tests**

Add a 2-row scan body next to `_scanBody` in `test/baptismal_ocr_scan_page_test.dart`:

```dart
Map<String, dynamic> _scanBody2() => {
  'success': true,
  'data': {
    'scanId': 's1', 'rotation': 0, 'warnings': <String>[],
    'rows': [
      {'lineNo': '1', 'fields': {'nameOfChild': {'value': 'RENE', 'confidence': 0.9}, 'dateOfBaptism': {'value': '12 MAY 2016', 'confidence': 0.9}}},
      {'lineNo': '2', 'fields': {'nameOfChild': {'value': 'HAGANAS', 'confidence': 0.9}, 'dateOfBaptism': {'value': '12 MAY 2016', 'confidence': 0.9}}},
    ],
  },
};
```

Then add tests (reuse `harness`, `serviceReturning`; drive pick → scan → review):

```dart
  Future<void> _toReview(WidgetTester tester, Map<String, dynamic> body) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, body)));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
  }

  testWidgets('insert adds a blank row below', (tester) async {
    await _toReview(tester, _scanBody2());
    expect(find.byKey(const ValueKey('cell-2-nameOfChild')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('row-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert blank row below'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cell-2-nameOfChild')), findsOneWidget); // 3 rows now
  });

  testWidgets('delete removes a row', (tester) async {
    await _toReview(tester, _scanBody2());
    await tester.tap(find.byKey(const ValueKey('row-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete row'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cell-1-nameOfChild')), findsNothing); // 1 row left
  });

  testWidgets('merge concatenates two rows into one', (tester) async {
    await _toReview(tester, _scanBody2());
    await tester.tap(find.byKey(const ValueKey('row-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge with row below'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cell-1-nameOfChild')), findsNothing); // 1 row
    final field = tester.widget<TextFormField>(find.byKey(const ValueKey('cell-0-nameOfChild')));
    expect(field.initialValue, 'RENE HAGANAS');
  });
```

Note: `TextFormField.initialValue` reflects the row's value because each cell is keyed `cell-$row-$key` and rebuilt from `_rows` (a new merged row → new initialValue).

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/baptismal_ocr_scan_page_test.dart -j 1 --plain-name "insert adds"`
Expected: FAIL — no `row-menu-0` wired.

- [ ] **Step 3: Wire the callbacks**

In `lib/screens/admin/pages/baptismal_ocr_scan_page.dart`, `_reviewStep()`'s `BaptismalOcrReviewTable(...)` — add after the existing `onLineNoChanged:` argument:

```dart
                  onInsertRowBelow: (i) => setState(() {
                    _rows.insert(i + 1, BaptismalRegisterRow.blank());
                    _highlightedRow = null;
                  }),
                  onDeleteRow: (i) => setState(() {
                    _rows.removeAt(i);
                    _highlightedRow = null;
                  }),
                  onMergeWithNext: (i) => setState(() {
                    if (i + 1 < _rows.length) {
                      _rows[i] = _rows[i].mergedWith(_rows[i + 1]);
                      _rows.removeAt(i + 1);
                      _highlightedRow = null;
                    }
                  }),
```

(`BaptismalRegisterRow` is already imported in this file.)

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/baptismal_ocr_scan_page_test.dart -j 1 && flutter analyze lib/screens/admin/pages/baptismal_ocr_scan_page.dart`
Expected: PASS; analyze clean.

- [ ] **Step 5: Full regression + commit**

```bash
flutter test
git add lib/screens/admin/pages/baptismal_ocr_scan_page.dart test/baptismal_ocr_scan_page_test.dart
git commit -m "feat(ocr): wire insert/delete/merge row actions into the OCR review"
```
Expected: full Flutter suite green.

---

## Self-Review Notes

- **Spec coverage:** `blank()`/`mergedWith()` → Task 1; widget callbacks + per-row menu (both layouts, merge hidden on last row) → Task 2; scan-page wiring + `_highlightedRow` clear → Task 3; all three test layers present. YAGNI (no split/undo/reorder) honored.
- **Placeholder scan:** none — every step has concrete code.
- **Type consistency:** `onInsertRowBelow/onDeleteRow/onMergeWithNext : void Function(int)` are defined in Task 2 and consumed identically in Task 3; `BaptismalRegisterRow.blank()`/`mergedWith(other)` defined in Task 1 and used in Task 3; menu keys `row-menu-$i` and item texts ("Insert blank row below" / "Merge with row below" / "Delete row") match across Tasks 2 and 3 tests.
