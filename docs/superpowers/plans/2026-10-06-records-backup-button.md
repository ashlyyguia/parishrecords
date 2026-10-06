# Records-Page Backup Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Back Up (JSON)" button to the Admin Records page that downloads a JSON backup of the record data currently matching the page's filters.

**Architecture:** A new pure function `recordsToBackupJson(List<ParishRecord>)` serializes records to JSON-ready maps (the one piece with logic, unit-tested). `AdminRecordsPage` gains a button that maps its already-filtered `_load()` items back to their `ParishRecord` objects, serializes them via that function, and downloads via the existing `ExportService.exportJson`.

**Tech Stack:** Flutter / Dart, `flutter_test`, existing `ExportService` (handles web blob download + native file write).

## Global Constraints

- Data only — no scanned image binaries, no scan-flow changes, no backend/storage changes, no changes to the existing `AdminBackupPage`.
- Backup scope = the records currently matching the page's filters (the `_load()` result), not all records.
- Reuse `ExportService.exportJson` as-is; do not add new platform (web/io) code.
- Backup map shape matches the existing `AdminBackupPage` convention exactly: keys `id, type, name, date, imagePath, parish, notes, certificateStatus`.
- Filename format: `records_backup_<count>_<timestamp>.json` where `<timestamp>` is `DateTime.now().toIso8601String()` with `:` replaced by `-`.

---

### Task 1: Serialization function + unit tests

**Files:**
- Create: `lib/services/records_backup.dart`
- Create: `test/records_backup_test.dart`

**Interfaces:**
- Consumes: `ParishRecord`, `RecordType`, `CertificateStatus` from `lib/models/record.dart`.
- Produces: `List<Map<String, dynamic>> recordsToBackupJson(List<ParishRecord> records)` — each map has keys `id` (String), `type` (String, `record.type.name`), `name` (String), `date` (String, `record.date.toIso8601String()`), `imagePath` (String?), `parish` (String?), `notes` (String?), `certificateStatus` (String, `record.certificateStatus.name`).

- [ ] **Step 1: Write the failing test**

Create `test/records_backup_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/record.dart';
import 'package:parishrecord/services/records_backup.dart';

void main() {
  group('recordsToBackupJson', () {
    test('maps a populated record to the backup shape', () {
      final records = [
        ParishRecord(
          id: 'abc123',
          type: RecordType.marriage,
          name: 'Juan & Maria',
          date: DateTime.utc(2026, 9, 15, 10, 30),
          imagePath: '/scans/img.jpg',
          parish: 'San Isidro',
          notes: '{"lineNo":4}',
          certificateStatus: CertificateStatus.approved,
        ),
      ];

      final out = recordsToBackupJson(records);

      expect(out, hasLength(1));
      expect(out.first, {
        'id': 'abc123',
        'type': 'marriage',
        'name': 'Juan & Maria',
        'date': '2026-09-15T10:30:00.000Z',
        'imagePath': '/scans/img.jpg',
        'parish': 'San Isidro',
        'notes': '{"lineNo":4}',
        'certificateStatus': 'approved',
      });
    });

    test('preserves null imagePath, parish, and notes', () {
      final records = [
        ParishRecord(
          id: 'x',
          type: RecordType.baptism,
          name: 'Baby',
          date: DateTime.utc(2026, 1, 2),
        ),
      ];

      final map = recordsToBackupJson(records).first;

      expect(map['imagePath'], isNull);
      expect(map['parish'], isNull);
      expect(map['notes'], isNull);
      expect(map['type'], 'baptism');
      expect(map['certificateStatus'], 'pending');
    });

    test('returns an empty list for empty input', () {
      expect(recordsToBackupJson(const []), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/records_backup_test.dart`
Expected: FAIL — `records_backup.dart` / `recordsToBackupJson` not found (compile error).

- [ ] **Step 3: Write minimal implementation**

Create `lib/services/records_backup.dart`:

```dart
import '../models/record.dart';

/// Serializes parish records into JSON-ready maps for the records-page
/// backup download. Shape matches the existing AdminBackupPage export.
List<Map<String, dynamic>> recordsToBackupJson(List<ParishRecord> records) {
  return records
      .map(
        (r) => <String, dynamic>{
          'id': r.id,
          'type': r.type.name,
          'name': r.name,
          'date': r.date.toIso8601String(),
          'imagePath': r.imagePath,
          'parish': r.parish,
          'notes': r.notes,
          'certificateStatus': r.certificateStatus.name,
        },
      )
      .toList();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/records_backup_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/records_backup.dart test/records_backup_test.dart
git commit -m "feat(records): add recordsToBackupJson serializer with tests"
```

---

### Task 2: Wire the "Back Up (JSON)" button into AdminRecordsPage

**Files:**
- Modify: `lib/screens/admin/pages/records_page.dart`

**Interfaces:**
- Consumes: `recordsToBackupJson` from `lib/services/records_backup.dart`; `ExportService.exportJson(String filename, List<Map<String, dynamic>> data)` from `lib/services/export_service.dart`.
- Produces: no new public interface (internal `_backupFiltered` method + `_backupBusy` state).

- [ ] **Step 1: Add imports**

In `lib/screens/admin/pages/records_page.dart`, add alongside the existing imports (near line 8):

```dart
import '../../../services/export_service.dart';
import '../../../services/records_backup.dart';
```

- [ ] **Step 2: Add busy state field**

In `_AdminRecordsPageState` (after `List<ParishRecord> _records = const [];` near line 33), add:

```dart
  bool _backupBusy = false;
```

- [ ] **Step 3: Add the backup method**

Add this method to `_AdminRecordsPageState` (place it right after `_importCsvDialog()` ends, near line 259):

```dart
  Future<void> _backupFiltered() async {
    final filtered = _load();
    final records = filtered
        .map((m) => m['record'])
        .whereType<ParishRecord>()
        .toList();

    if (records.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No records to back up.')));
      return;
    }

    setState(() => _backupBusy = true);
    try {
      final data = recordsToBackupJson(records);
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      await ExportService.exportJson(
        'records_backup_${records.length}_$ts.json',
        data,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backed up ${records.length} records.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }
```

- [ ] **Step 4: Add the button to the header action Wrap**

In the `headerSection` action `Wrap` (the `children:` list that currently ends with the `OutlinedButton.icon` for `_openNewRecord`, near line 363-367), add a new button after that `OutlinedButton.icon`:

```dart
                OutlinedButton.icon(
                  onPressed: _backupBusy ? null : _backupFiltered,
                  icon: _backupBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_outlined),
                  label: const Text('Back Up (JSON)'),
                ),
```

- [ ] **Step 5: Verify it compiles and analyzes clean**

Run: `flutter analyze lib/screens/admin/pages/records_page.dart lib/services/records_backup.dart`
Expected: No issues (no new warnings/errors introduced by these files).

- [ ] **Step 6: Run the full test suite to confirm no regressions**

Run: `flutter test test/records_backup_test.dart`
Expected: PASS (serializer tests still green; widget wiring has no unit test by design — it is thin glue over the tested serializer and the existing ExportService).

- [ ] **Step 7: Commit**

```bash
git add lib/screens/admin/pages/records_page.dart
git commit -m "feat(records): add Back Up (JSON) button to admin records page"
```

---

## Self-Review

**Spec coverage:**
- Button on `/admin/records` header row → Task 2, Step 4. ✓
- Backs up filtered list (`_load()`) → Task 2, Step 3 (`_load()` → `record` extraction). ✓
- JSON via `ExportService.exportJson` → Task 2, Step 3. ✓
- Filename `records_backup_<count>_<timestamp>.json` with `:`→`-` → Task 2, Step 3. ✓
- Busy state disables button → Task 2, Steps 2 & 4. ✓
- Success / failure / empty snackbars → Task 2, Step 3. ✓
- Full-fidelity map shape (`id,type,name,date,imagePath,parish,notes,certificateStatus`) → Task 1. ✓
- Unit tests: field mapping, ISO date, null handling, enum `.name`, empty list → Task 1, Step 1. ✓
- Out of scope (images, scan flow, backend, AdminBackupPage) honored — no such changes in any task. ✓

**Placeholder scan:** No TBD/TODO/placeholder steps; all code blocks are concrete. ✓

**Type consistency:** `recordsToBackupJson(List<ParishRecord>) → List<Map<String, dynamic>>` is defined in Task 1 and consumed with the same signature in Task 2. `ExportService.exportJson(String, List<Map<String, dynamic>>)` matches the real signature in `lib/services/export_service.dart`. ✓
