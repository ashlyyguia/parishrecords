# Register Fill-Down Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let staff set the baptism date and minister once and fill them across all selected rows on the scan preview, so left-page-only scans become savable.

**Architecture:** A pure `applyRegisterFillDown` helper mutates the selected `RegisterOcrEntry` rows (sets `baptismDateText` + parsed `date`, and `minister`); a thin dialog on `StaffOcrResultPage` collects the two values and calls it, then refreshes the table.

**Tech Stack:** Flutter/Dart, `flutter_test`. No new dependencies.

## Global Constraints

- Baptism only; fields = **date** + **minister** (batch-constant). Residents/sponsors stay per-row editable; marriage untouched.
- The date fill must set BOTH `entry.baptismDateText` and `entry.date` (via `RegisterOcrParser.parseDate`), because `RegisterOcrEntry.isValid` and `saveRegisterOcrEntries` require `entry.date`.
- Only rows with `selected == true` are modified.
- Flutter package name is `parishrecord`; tests under `test/ocr/`.

---

### Task 1: `applyRegisterFillDown` (pure helper)

**Files:**
- Modify: `lib/services/register_ocr_scan_helper.dart` (add one static method to `RegisterOcrScanHelper`)
- Test: `test/ocr/apply_register_fill_down_test.dart`

**Interfaces:**
- Consumes: `RegisterOcrEntry` (fields `selected`, `baptismDateText`, `date`, `minister`); `RegisterOcrParser.parseDate(String)`.
- Produces: `static int RegisterOcrScanHelper.applyRegisterFillDown(List<RegisterOcrEntry> entries, {String? date, String? minister})` — returns the number of selected rows changed.

- [ ] **Step 1: Write the failing test**

Create `test/ocr/apply_register_fill_down_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/register_ocr_entry.dart';
import 'package:parishrecord/services/register_ocr_scan_helper.dart';

RegisterOcrEntry _row(String name, {bool selected = true}) =>
    RegisterOcrEntry(id: name, name: name, rawLine: '', selected: selected);

void main() {
  test('fills date (+parsed) and minister on selected rows only', () {
    final a = _row('Alderto');
    final b = _row('Elliana', selected: false);
    final n = RegisterOcrScanHelper.applyRegisterFillDown(
      [a, b],
      date: '16 May 2016',
      minister: 'Fr. Daryl Rosales',
    );
    expect(n, 1);
    expect(a.baptismDateText, '16 May 2016');
    expect(a.date, DateTime(2016, 5, 16));
    expect(a.minister, 'Fr. Daryl Rosales');
    // untouched
    expect(b.baptismDateText, '');
    expect(b.date, isNull);
    expect(b.minister, '');
  });

  test('returns 0 when nothing to apply', () {
    final a = _row('x');
    expect(RegisterOcrScanHelper.applyRegisterFillDown([a]), 0);
    expect(a.baptismDateText, '');
  });

  test('keeps baptismDateText even when the date is unparseable', () {
    final a = _row('x');
    RegisterOcrScanHelper.applyRegisterFillDown([a], date: 'not a date');
    expect(a.baptismDateText, 'not a date');
    expect(a.date, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ocr/apply_register_fill_down_test.dart`
Expected: FAIL — `applyRegisterFillDown` is undefined.

- [ ] **Step 3: Implement the helper**

In `lib/services/register_ocr_scan_helper.dart`, add this static method inside `RegisterOcrScanHelper` (e.g. near `appendPageEntries`):

```dart
  /// Fills the batch-constant baptism [date] and/or [minister] onto every
  /// selected row. Sets both `baptismDateText` and the parsed `date` so the
  /// rows become valid/savable. Returns the number of rows changed.
  static int applyRegisterFillDown(
    List<RegisterOcrEntry> entries, {
    String? date,
    String? minister,
  }) {
    final dateText = date?.trim() ?? '';
    final ministerText = minister?.trim() ?? '';
    if (dateText.isEmpty && ministerText.isEmpty) return 0;

    var changed = 0;
    for (final e in entries) {
      if (!e.selected) continue;
      if (dateText.isNotEmpty) {
        e.baptismDateText = dateText;
        e.date = RegisterOcrParser.parseDate(dateText);
      }
      if (ministerText.isNotEmpty) {
        e.minister = ministerText;
      }
      changed++;
    }
    return changed;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ocr/apply_register_fill_down_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/register_ocr_scan_helper.dart test/ocr/apply_register_fill_down_test.dart
git commit -m "feat(ocr): add applyRegisterFillDown batch date/minister helper"
```

---

### Task 2: Fill-down dialog on the scan preview

**Files:**
- Modify: `lib/screens/staff/pages/staff_ocr_result_page.dart` (add `_openFillDown`; add a toolbar button)

**Interfaces:**
- Consumes: `RegisterOcrScanHelper.applyRegisterFillDown` (Task 1); existing `_entries`, `_isMarriage`, `_isProcessing`, `_tableGeneration`.
- Produces: a "Set date / minister" toolbar action (baptism only) that applies fill-down and refreshes the table.

- [ ] **Step 1: Add the `_openFillDown` dialog method**

In `lib/screens/staff/pages/staff_ocr_result_page.dart`, add this method to `_StaffOcrResultPageState` (e.g. right after `_addRow`):

```dart
  Future<void> _openFillDown() async {
    final dateCtrl = TextEditingController();
    final ministerCtrl = TextEditingController();
    final selectedCount = _entries.where((e) => e.selected).length;

    final applied = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set date / minister'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Applies to $selectedCount selected row(s).'),
            const SizedBox(height: 12),
            TextField(
              controller: dateCtrl,
              decoration: const InputDecoration(
                labelText: 'Baptism date',
                hintText: 'e.g. 16 May 2016',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ministerCtrl,
              decoration: const InputDecoration(
                labelText: 'Minister (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: selectedCount == 0
                ? null
                : () {
                    final n = RegisterOcrScanHelper.applyRegisterFillDown(
                      _entries,
                      date: dateCtrl.text,
                      minister: ministerCtrl.text,
                    );
                    Navigator.pop(ctx, n);
                  },
            child: Text('Apply to $selectedCount selected'),
          ),
        ],
      ),
    );

    dateCtrl.dispose();
    ministerCtrl.dispose();

    if (applied != null && mounted) {
      // Bump the generation so the table re-seeds its cell controllers from
      // the updated entries.
      setState(() => _tableGeneration++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Applied to $applied row(s).')),
      );
    }
  }
```

- [ ] **Step 2: Add the toolbar button (baptism only)**

In the same file, in the `build` toolbar `Row` that contains "Add row" and "Scan other page" (the `Row(children: [ TextButton.icon(... _addRow ...), TextButton.icon(... _scanAnotherPage ...), const Spacer(), ... ])`), add this button right after the "Scan other page" `TextButton.icon` and before `const Spacer()`:

```dart
                      if (!_isMarriage)
                        TextButton.icon(
                          onPressed: _isProcessing ? null : _openFillDown,
                          icon: const Icon(Icons.event_note_outlined, size: 18),
                          label: const Text('Set date / minister'),
                        ),
```

- [ ] **Step 3: Verify it compiles and the suite is green**

Run: `flutter analyze lib/screens/staff/pages/staff_ocr_result_page.dart`
Expected: no new errors.
Run: `flutter test`
Expected: PASS (existing suite + Task 1 tests; nothing regressed).

- [ ] **Step 4: Commit**

```bash
git add lib/screens/staff/pages/staff_ocr_result_page.dart
git commit -m "feat(ocr): fill-down dialog to set date/minister for selected rows"
```

---

## Self-Review

**Spec coverage:**
- Pure `applyRegisterFillDown(entries, {date, minister})` setting `baptismDateText` + parsed `date` + `minister` on selected rows, returning changed count → Task 1 ✅
- Sets both `baptismDateText` and `date` so rows become savable → Task 1 Step 3 ✅
- Dialog on `StaffOcrResultPage` (baptism) with date + optional minister + "Apply to N selected" + snackbar → Task 2 ✅
- Only selected rows changed → Task 1 (loop guard) + test ✅
- Table refresh after apply → Task 2 (`_tableGeneration++`) ✅
- Non-goals (right-page OCR, sponsors/residents fill-down, marriage) → not in any task ✅

**Placeholder scan:** No TBD/TODO; both code steps contain full implementations. Task 2's UI wiring is verified via analyze + full suite (the mutation logic it calls is unit-tested in Task 1), consistent with the spec's "dialog is thin wiring, manual check."

**Type consistency:** `applyRegisterFillDown(List<RegisterOcrEntry>, {String? date, String? minister}) -> int` is defined in Task 1 and called identically in Task 2. `RegisterOcrEntry` fields (`selected`, `baptismDateText`, `date`, `minister`) and `RegisterOcrParser.parseDate(String) -> DateTime?` match the model/parser. `_tableGeneration` and `_isMarriage`/`_isProcessing` are existing `_StaffOcrResultPageState` members.
