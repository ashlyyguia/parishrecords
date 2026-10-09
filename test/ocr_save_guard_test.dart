import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parishrecord/models/baptismal_register_row.dart';
import 'package:parishrecord/models/register_marriage_entry.dart';
import 'package:parishrecord/models/register_ocr_entry.dart';
import 'package:parishrecord/screens/admin/pages/baptismal_ocr_scan_page.dart';
import 'package:parishrecord/screens/admin/pages/marriage_ocr_scan_page.dart';
import 'package:parishrecord/services/baptismal_ocr_service.dart';
import 'package:parishrecord/services/marriage_ocr_service.dart';
import 'package:parishrecord/services/ocr_save_guard.dart';

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Map<String, dynamic> _baptismBody() => {
  'success': true,
  'data': {
    'scanId': 's1',
    'rotation': 0,
    'warnings': <String>[],
    'rows': [
      {
        'lineNo': '1',
        'fields': {
          'nameOfChild': {'value': 'RENE SAMPLE', 'confidence': 0.9},
          'dateOfBaptism': {'value': '12 MAY 2016', 'confidence': 0.9},
        },
      },
      {
        'lineNo': '2',
        'fields': {
          'nameOfChild': {'value': 'ANA HAGANAS', 'confidence': 0.9},
          'dateOfBaptism': {'value': '13 MAY 2016', 'confidence': 0.9},
        },
      },
    ],
  },
};

Map<String, dynamic> _marriageBody() => {
  'success': true,
  'data': {
    'scanId': 's1',
    'rotation': 0,
    'warnings': <String>[],
    'rows': [
      {
        'lineNo': '1',
        'groom': {'name': 'Marlon', 'actualAddress': 'Bunga Oroquieta'},
        'bride': {'name': 'Ana'},
        'dateOfMarriage': 'Jan 07 2023',
        'minister': 'Fr Alcher',
      },
    ],
  },
};

Widget _baptismPage({
  required Future<int> Function(List<RegisterRecordDraft>) saveRecords,
  required OcrPendingSaveStore store,
  Duration saveTimeout = const Duration(seconds: 30),
}) {
  return ProviderScope(
    child: MaterialApp(
      home: BaptismalOcrScanPage(
        ocrService: BaptismalOcrService(
          client: MockClient(
            (_) async => http.Response(jsonEncode(_baptismBody()), 200),
          ),
        ),
        imagePicker: (_) async => _png,
        imageUploader: null,
        idTokenProvider: () async => 'test-token',
        saveRecords: saveRecords,
        existingRecords: () => const [],
        pendingSaveStore: store,
        saveTimeout: saveTimeout,
      ),
    ),
  );
}

Widget _marriagePage({
  required Future<int> Function(List<RegisterRecordDraft>) saveRecords,
  required OcrPendingSaveStore store,
  Duration saveTimeout = const Duration(seconds: 30),
}) {
  return ProviderScope(
    child: MaterialApp(
      home: MarriageOcrScanPage(
        ocrService: MarriageOcrService(
          client: MockClient(
            (_) async => http.Response(jsonEncode(_marriageBody()), 200),
          ),
        ),
        imagePicker: (_) async => _png,
        imageUploader: null,
        idTokenProvider: () async => 'test-token',
        saveRecords: saveRecords,
        existingRecords: () => const [],
        pendingSaveStore: store,
        saveTimeout: saveTimeout,
      ),
    ),
  );
}

Future<void> _scan(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('pick-image')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan / Process OCR'));
  await tester.pumpAndSettle();
}

void main() {
  group('guardedOcrSave', () {
    test('returns saved when the write finishes in time', () async {
      final r = await guardedOcrSave(write: () async => 3);
      expect(r.outcome, OcrSaveOutcome.saved);
      expect(r.count, 3);
    });

    test('returns failed with the error', () async {
      final r = await guardedOcrSave(
        write: () async => throw Exception('permission-denied'),
      );
      expect(r.outcome, OcrSaveOutcome.failed);
      expect(r.error.toString(), contains('permission-denied'));
    });

    test('times out, then reports the late result', () async {
      final c = Completer<int>();
      int? late;
      final r = await guardedOcrSave(
        write: () => c.future,
        timeout: const Duration(milliseconds: 10),
        onLateSuccess: (n) => late = n,
      );
      expect(r.outcome, OcrSaveOutcome.waitingForConnection);
      c.complete(5);
      await Future<void>.delayed(Duration.zero);
      expect(late, 5);
    });
  });

  test('doc ids are stable and safe for Firestore', () {
    expect(ocrRecordDocId('baptism', 'a-b/c', 'r 1'), 'ocr_baptism_a-bc_r1');
    expect(
      ocrRecordDocId('marriage', 's', 'k'),
      ocrRecordDocId('marriage', 's', 'k'),
    );
  });

  test('baptismal rows survive the on-device round trip', () {
    final row = BaptismalRegisterRow.blank()
      ..lineNo = '7'
      ..selected = false;
    row.setValue('nameOfChild', 'JUAN');
    final back = BaptismalRegisterRow.fromStoredJson(
      jsonDecode(jsonEncode(row.toStoredJson())) as Map<String, dynamic>,
    );
    expect(back.rowKey, row.rowKey);
    expect(back.lineNo, '7');
    expect(back.selected, isFalse);
    expect(back.field('nameOfChild').value, 'JUAN');
    expect(back.field('nameOfChild').edited, isTrue);
  });

  test('merging rows keeps the first row key', () {
    final a = BaptismalRegisterRow.blank();
    final b = BaptismalRegisterRow.blank();
    expect(a.mergedWith(b).rowKey, a.rowKey);
  });

  test('marriage entries survive the on-device round trip', () {
    final e = RegisterMarriageEntry(
      id: 'e1',
      lineNo: '3',
      groom: MarriagePartyInfo(name: 'Marlon', parents: 'X & Y'),
      bride: MarriagePartyInfo(name: 'Ana'),
      dateOfMarriage: 'Jan 07 2023',
    );
    final back = RegisterMarriageEntry.fromStoredJson(
      jsonDecode(jsonEncode(e.toStoredJson())) as Map<String, dynamic>,
    );
    expect(back.id, 'e1');
    expect(back.lineNo, '3');
    expect(back.groom.parents, 'X & Y');
    expect(back.bride.name, 'Ana');
  });

  test('pending saves are filtered by kind and owner, newest first', () async {
    final store = MemoryOcrPendingSaveStore();
    OcrPendingSave s(String kind, String id, String owner, int day) =>
        OcrPendingSave(
          kind: kind,
          scanId: id,
          savedAt: DateTime(2026, 10, day),
          rowCount: 1,
          state: const {},
          ownerUid: owner,
        );
    await store.put(s('baptism', 'a', 'u1', 1));
    await store.put(s('baptism', 'b', 'u1', 2));
    await store.put(s('baptism', 'c', 'u2', 3));
    await store.put(s('marriage', 'd', 'u1', 4));
    final mine = await store.list('baptism', ownerUid: 'u1');
    expect(mine.map((e) => e.scanId), ['b', 'a']);
    final parsed = OcrPendingSave.tryParse(jsonEncode(mine.first.toJson()));
    expect(parsed?.scanId, 'b');
  });

  testWidgets('baptismal: retry after a failed save reuses the same ids', (
    tester,
  ) async {
    final store = MemoryOcrPendingSaveStore();
    final calls = <List<String?>>[];
    var fail = true;
    await tester.pumpWidget(
      _baptismPage(
        store: store,
        saveRecords: (drafts) async {
          calls.add(drafts.map((d) => d.docId).toList());
          if (fail) throw Exception('network unavailable');
          return drafts.length;
        },
      ),
    );
    await _scan(tester);

    await tester.tap(find.byKey(const ValueKey('save-rows')));
    await tester.pumpAndSettle();

    // Rows are kept, on screen and on the device.
    expect(find.byKey(const ValueKey('ocr-save-status')), findsOneWidget);
    expect(find.text('Not saved yet'), findsOneWidget);
    expect(find.text('RENE SAMPLE'), findsOneWidget);
    expect(store.saves, hasLength(1));

    fail = false;
    await tester.tap(find.byKey(const ValueKey('ocr-save-retry')));
    await tester.pump();

    expect(calls, hasLength(2));
    expect(calls[0], calls[1]);
    expect(calls[0].every((id) => id != null && id.startsWith('ocr_baptism_')),
        isTrue);
    expect(calls[0].toSet(), hasLength(2));
    expect(find.textContaining('Saved 2 baptismal record'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(store.saves, isEmpty);
  });

  testWidgets('baptismal: a slow save shows "waiting", then confirms', (
    tester,
  ) async {
    final store = MemoryOcrPendingSaveStore();
    final server = Completer<int>();
    await tester.pumpWidget(
      _baptismPage(
        store: store,
        saveTimeout: const Duration(seconds: 5),
        saveRecords: (_) => server.future,
      ),
    );
    await _scan(tester);

    await tester.tap(find.byKey(const ValueKey('save-rows')));
    await tester.pump();
    expect(find.textContaining('Saving 2 record'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    expect(
      find.text('Waiting for the internet connection…'),
      findsOneWidget,
    );
    expect(store.saves, hasLength(1));

    server.complete(2);
    await tester.pump();
    expect(
      find.textContaining('Connection restored — saved 2 baptismal'),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(store.saves, isEmpty);
  });

  testWidgets('baptismal: an interrupted scan can be resumed', (tester) async {
    final store = MemoryOcrPendingSaveStore();
    final row = BaptismalRegisterRow.blank()..lineNo = '4';
    row.setValue('nameOfChild', 'RESUMED CHILD');
    row.setValue('dateOfBaptism', '12 MAY 2016');
    await store.put(
      OcrPendingSave(
        kind: 'baptism',
        scanId: 'scan-9',
        savedAt: DateTime(2026, 10, 10, 9),
        rowCount: 1,
        state: {
          'vol': '12',
          'series': '2020',
          'rows': [row.toStoredJson()],
        },
      ),
    );
    List<RegisterRecordDraft>? saved;
    await tester.pumpWidget(
      _baptismPage(
        store: store,
        saveRecords: (d) async {
          saved = d;
          return d.length;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ocr-pending-saves')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ocr-resume-scan-9')));
    await tester.pumpAndSettle();

    expect(find.text('RESUMED CHILD'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    final btn = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-rows')),
    );
    expect(btn.onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('save-rows')));
    await tester.pump();
    expect(saved!.single.docId, ocrRecordDocId('baptism', 'scan-9', row.rowKey));
    await tester.pumpAndSettle();
    expect(store.saves, isEmpty);
  });

  testWidgets('baptismal: discarding a pending scan removes it', (
    tester,
  ) async {
    final store = MemoryOcrPendingSaveStore();
    await store.put(
      OcrPendingSave(
        kind: 'baptism',
        scanId: 'old',
        savedAt: DateTime(2026, 10, 9),
        rowCount: 3,
        state: const {'rows': []},
      ),
    );
    await tester.pumpWidget(
      _baptismPage(store: store, saveRecords: (d) async => d.length),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ocr-discard-old')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(store.saves, isEmpty);
    expect(find.byKey(const ValueKey('ocr-pending-saves')), findsNothing);
  });

  testWidgets('marriage: failed save keeps entries and retries with same ids', (
    tester,
  ) async {
    final store = MemoryOcrPendingSaveStore();
    final calls = <List<String?>>[];
    var fail = true;
    await tester.pumpWidget(
      _marriagePage(
        store: store,
        saveRecords: (drafts) async {
          calls.add(drafts.map((d) => d.docId).toList());
          if (fail) throw Exception('offline');
          return drafts.length;
        },
      ),
    );
    await _scan(tester);
    await tester.tap(find.byKey(const ValueKey('save-rows')));
    await tester.pumpAndSettle();
    expect(find.text('Not saved yet'), findsOneWidget);
    expect(store.saves, hasLength(1));
    final stored = store.saves.values.single.state['entries'] as List;
    expect(stored, hasLength(1));

    fail = false;
    await tester.tap(find.byKey(const ValueKey('ocr-save-retry')));
    await tester.pump();
    expect(calls[0], calls[1]);
    expect(calls[0].single, startsWith('ocr_marriage_'));
    expect(find.textContaining('Saved 1 marriage record'), findsOneWidget);
  });

  testWidgets('marriage: a slow save shows "waiting"', (tester) async {
    final store = MemoryOcrPendingSaveStore();
    final server = Completer<int>();
    await tester.pumpWidget(
      _marriagePage(
        store: store,
        saveTimeout: const Duration(seconds: 5),
        saveRecords: (_) => server.future,
      ),
    );
    await _scan(tester);
    await tester.tap(find.byKey(const ValueKey('save-rows')));
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Waiting for the internet connection…'), findsOneWidget);
    server.complete(1);
    await tester.pump();
    expect(find.textContaining('Connection restored'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
