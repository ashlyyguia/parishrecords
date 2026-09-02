import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parishrecord/models/record.dart';
import 'package:parishrecord/models/register_ocr_entry.dart';
import 'package:parishrecord/screens/admin/pages/baptismal_ocr_scan_page.dart';
import 'package:parishrecord/services/baptismal_ocr_service.dart';

// A 1x1 PNG is enough — the page only needs bytes Image.memory can decode.
final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

Map<String, dynamic> _scanBody({String name = 'TESTA SAMPLE'}) => {
  'success': true,
  'data': {
    'scanId': 's1',
    'rotation': 0,
    'warnings': <String>[],
    'rows': [
      {
        'lineNo': '1',
        'fields': {
          'nameOfChild': {'value': name, 'confidence': 0.9},
          'dateOfBaptism': {'value': '12 MAY 2016', 'confidence': 0.9},
        },
      },
    ],
  },
};

Map<String, dynamic> _scanBodyWithWarnings(List<String> warnings) {
  final body = _scanBody();
  (body['data'] as Map<String, dynamic>)['warnings'] = warnings;
  return body;
}

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

Map<String, dynamic> _emptyScanBody() => {
  'success': true,
  'data': {
    'scanId': 's1',
    'rotation': 0,
    'warnings': <String>[],
    'rows': <Map<String, dynamic>>[],
  },
};

Widget harness({
  required BaptismalOcrService service,
  Future<Uint8List?> Function(BuildContext)? picker,
  Future<String?> Function(String scanId, Uint8List bytes)? uploader,
  Future<int> Function(List<RegisterRecordDraft>)? saveRecords,
  List<ParishRecord> Function()? existingRecords,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: BaptismalOcrScanPage(
        ocrService: service,
        imagePicker: picker ?? (_) async => _png,
        imageUploader: uploader ?? (_, _) async => 'baptism_scans/2026/s1.jpg',
        // Widget tests have no Firebase app registered; without this the
        // page would fall through to FirebaseAuth.instance internally and
        // every scan would fail with UNAUTHENTICATED regardless of what
        // the mocked HTTP client returns.
        idTokenProvider: () async => 'test-token',
        // recordsProvider's default implementation (RecordsNotifier) touches
        // live Firestore in a field initializer, so even overriding the
        // provider with a build()-only subclass still blows up before
        // build() runs. Injecting the save action directly is the only way
        // to exercise the save path without Firebase.
        saveRecords: saveRecords,
        // Same rationale as saveRecords: recordsProvider's default touches
        // live Firestore, so tests inject a fixed list here. Defaults to an
        // empty list (no pre-existing records) when unset.
        existingRecords: existingRecords ?? () => const [],
      ),
    ),
  );
}

BaptismalOcrService serviceReturning(int status, Object body) =>
    BaptismalOcrService(
      client: MockClient((_) async => http.Response(jsonEncode(body), status)),
    );

void main() {
  testWidgets('starts on the upload step', (tester) async {
    await tester.pumpWidget(
      harness(service: serviceReturning(200, _scanBody())),
    );
    expect(find.text('Upload or capture a register page'), findsOneWidget);
    expect(find.text('Scan / Process OCR'), findsNothing);
  });

  testWidgets('shows the capture checklist on the upload step', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _scanBody())));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('capture-guide')), findsOneWidget);
    expect(find.textContaining('flat'), findsWidgets); // "lay the book flat"
  });

  testWidgets('shows the capture-guidance detail when a scan is refused',
      (tester) async {
    final svc = serviceReturning(422, {
      'success': false,
      'code': 'SPREAD_UNREADABLE',
      'message': 'Could not read this register spread reliably.',
      'detail': "The left page's column lines were too faint to read.",
    });
    await tester.pumpWidget(harness(service: svc));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('too faint to read'), findsOneWidget);
  });

  testWidgets('shows a preview and the scan action after picking', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(service: serviceReturning(200, _scanBody())),
    );
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Scan / Process OCR'), findsOneWidget);
  });

  testWidgets('runs OCR and lands on the review step', (tester) async {
    await tester.pumpWidget(
      harness(service: serviceReturning(200, _scanBody())),
    );
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.text('TESTA SAMPLE'), findsOneWidget);
    expect(find.textContaining('Save'), findsWidgets);
  });

  Future<void> toReview(WidgetTester tester, Map<String, dynamic> body) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, body)));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
  }

  // The review uses a lazy ListView, so off-screen rows aren't built at the
  // test surface size -- assert on the always-visible "Save N record(s)" count
  // (and the first, visible row) rather than an off-screen cell key.
  testWidgets('insert adds a blank (selected) row', (tester) async {
    await toReview(tester, _scanBody2());
    expect(find.text('Save 2 record(s)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('row-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert blank row below'));
    await tester.pumpAndSettle();
    expect(find.text('Save 3 record(s)'), findsOneWidget);
  });

  testWidgets('delete removes a row', (tester) async {
    await toReview(tester, _scanBody2());
    await tester.tap(find.byKey(const ValueKey('row-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete row'));
    await tester.pumpAndSettle();
    expect(find.text('Save 1 record(s)'), findsOneWidget);
  });

  testWidgets('merge concatenates two rows into one', (tester) async {
    await toReview(tester, _scanBody2());
    await tester.tap(find.byKey(const ValueKey('row-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge with row below'));
    await tester.pumpAndSettle();
    expect(find.text('Save 1 record(s)'), findsOneWidget);
    final field = tester.widget<TextFormField>(find.byKey(const ValueKey('cell-0-nameOfChild')));
    expect(field.initialValue, 'RENE HAGANAS');
  });

  testWidgets('shows the confidence banner when CONFIDENCE_UNAVAILABLE is present', (tester) async {
    final svc = serviceReturning(200, _scanBodyWithWarnings(['CONFIDENCE_UNAVAILABLE']));
    await tester.pumpWidget(harness(service: svc));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('confidence-banner')), findsOneWidget);
    // It must NOT be rendered inside the red layout-warnings panel.
    expect(find.byKey(const ValueKey('warnings-panel')), findsNothing);
  });

  testWidgets('keeps CONFIDENCE_UNAVAILABLE out of the red warnings panel but still shows layout warnings', (tester) async {
    final svc = serviceReturning(
      200,
      _scanBodyWithWarnings(['GUTTER_UNCONFIRMED', 'CONFIDENCE_UNAVAILABLE']),
    );
    await tester.pumpWidget(harness(service: svc));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('confidence-banner')), findsOneWidget);
    // The collapsible layout-warnings panel is present (one layout warning).
    expect(find.byKey(const ValueKey('warnings-panel')), findsOneWidget);
    expect(find.textContaining('to review before saving'), findsOneWidget);
  });

  testWidgets('keeps CV_UNAVAILABLE out of the red warnings panel (silent fallback signal)', (tester) async {
    // CV_UNAVAILABLE only means automatic grid detection fell back to word
    // clustering; CONFIDENCE_UNAVAILABLE already tells the reviewer to verify
    // every field, so this diagnostic code must not raise its own red banner.
    final svc = serviceReturning(
      200,
      _scanBodyWithWarnings(['CV_UNAVAILABLE', 'CONFIDENCE_UNAVAILABLE']),
    );
    await tester.pumpWidget(harness(service: svc));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('confidence-banner')), findsOneWidget);
    expect(find.byKey(const ValueKey('warnings-panel')), findsNothing);
    // The raw code must never reach the screen.
    expect(find.textContaining('CV_UNAVAILABLE'), findsNothing);
  });

  testWidgets('does not attempt Storage archival when no uploader is configured', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: BaptismalOcrScanPage(
            ocrService: serviceReturning(200, _scanBody()),
            imagePicker: (_) async => _png,
            imageUploader: null, // production: no Firebase Storage archival
            idTokenProvider: () async => 'test-token',
            saveRecords: (_) async => 1,
            existingRecords: () => const [],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();

    // OCR still reached the review step, and there is no "archive failed"
    // notice because no archival was attempted (Storage is never touched).
    expect(find.text('TESTA SAMPLE'), findsOneWidget);
    expect(find.byKey(const ValueKey('archive-failed-notice')), findsNothing);
  });

  testWidgets('blocks save while a required field is empty', (tester) async {
    await tester.pumpWidget(
      harness(service: serviceReturning(200, _scanBody(name: ''))),
    );
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.text('Name of child is required.'), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-rows')),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('unblocks save once the field is corrected', (tester) async {
    await tester.pumpWidget(
      harness(service: serviceReturning(200, _scanBody(name: ''))),
    );
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('cell-0-nameOfChild')),
      'CORRECTED',
    );
    await tester.pumpAndSettle();
    final saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-rows')),
    );
    expect(saveButton.onPressed, isNotNull);
  });

  // FIX 7 regression: the page used to call `validateBaptismalRows(_rows)`
  // with no `existing` argument, which defaults to `const []` -- so
  // cross-record duplicate detection only ever saw rows from the CURRENT
  // scan. Scanning the same register page twice produced silent duplicate
  // records. The page now reads existing records (injected here to avoid
  // touching the live `recordsProvider`) and must flag a row that matches
  // one already on file by name and date.
  testWidgets(
    'flags a duplicate against a pre-existing record, not just within the same scan',
    (tester) async {
      await tester.pumpWidget(
        harness(
          service: serviceReturning(200, _scanBody(name: 'TESTA SAMPLE')),
          existingRecords: () => [
            ParishRecord(
              id: 'existing-1',
              type: RecordType.baptism,
              name: 'TESTA SAMPLE',
              date: DateTime(2016, 5, 12),
            ),
          ],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('pick-image')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan / Process OCR'));
      await tester.pumpAndSettle();

      expect(
        find.text('A baptism for this name and date already exists.'),
        findsOneWidget,
      );
      // A duplicate is a non-blocking warning -- the reviewer may knowingly
      // override it -- so Save must still be enabled.
      final saveButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('save-rows')),
      );
      expect(saveButton.onPressed, isNotNull);
    },
  );

  testWidgets('shows a retryable error and keeps the image', (tester) async {
    await tester.pumpWidget(
      harness(
        service: serviceReturning(429, {
          'success': false,
          'code': 'OCR_QUOTA',
          'message': 'rate limited',
        }),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.text('rate limited'), findsOneWidget);
    expect(find.text('Retry OCR'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget); // image survived the failure
  });

  testWidgets('hides retry for a non-retryable configuration error', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        service: serviceReturning(500, {
          'success': false,
          'code': 'OCR_AUTH',
          'message': 'not configured',
        }),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.text('not configured'), findsOneWidget);
    expect(find.text('Retry OCR'), findsNothing);
    // contactAdmin has nothing to do with the image, so "Choose a different
    // image" must not be offered as if it were a fix.
    expect(find.text('Choose a different image'), findsNothing);
    expect(find.textContaining('server configuration problem'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget); // image survived the failure
  });

  testWidgets(
    'a sign-in error directs the user to sign in, not to pick a new image',
    (tester) async {
      await tester.pumpWidget(
        harness(
          service: serviceReturning(401, {
            'success': false,
            'code': 'UNAUTHENTICATED',
            'message': 'You are signed out.',
          }),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('pick-image')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan / Process OCR'));
      await tester.pumpAndSettle();
      expect(find.text('You are signed out.'), findsOneWidget);
      expect(find.text('Retry OCR'), findsNothing);
      // signIn has nothing to do with the image either -- same requirement as
      // contactAdmin above.
      expect(find.text('Choose a different image'), findsNothing);
      expect(find.textContaining('Sign in again'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget); // image survived the failure
    },
  );

  // --- Edge cases -----------------------------------------------------

  testWidgets('a different-image error hides retry and keeps the image', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        service: serviceReturning(200, {
          'success': false,
          'code': 'NO_TEXT_FOUND',
          'message': 'no text found',
        }),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.text('no text found'), findsOneWidget);
    expect(find.text('Retry OCR'), findsNothing);
    expect(find.text('Choose a different image'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget); // image survived the failure
  });

  testWidgets('cancelling the picker leaves the page on the upload step', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        service: serviceReturning(200, _scanBody()),
        picker: (_) async => null,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    expect(find.text('Upload or capture a register page'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a scan with zero rows explains why and disables save', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(service: serviceReturning(200, _emptyScanBody())),
    );
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No rows were detected'), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-rows')),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('deselecting the only row disables save', (tester) async {
    await tester.pumpWidget(
      harness(service: serviceReturning(200, _scanBody())),
    );
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    var saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-rows')),
    );
    expect(saveButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('row-select-0')));
    await tester.pumpAndSettle();

    saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-rows')),
    );
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('OCR still runs even when the storage upload fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        service: serviceReturning(200, _scanBody()),
        uploader: (_, _) async => throw Exception('storage unavailable'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    // Landed on review with the row intact — the failed upload did not
    // block OCR from proceeding.
    expect(find.text('TESTA SAMPLE'), findsOneWidget);
  });

  testWidgets('a save that throws shows an error and stays on review', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        service: serviceReturning(200, _scanBody()),
        saveRecords: (_) async => throw Exception('write failed'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-rows')),
    );
    expect(saveButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('save-rows')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Save failed'), findsOneWidget);
    // Still on the review step with the row intact — a failed save must
    // not lose the user's work.
    expect(find.text('TESTA SAMPLE'), findsOneWidget);
  });

  testWidgets(
    'the uploader\'s returned value is what lands in the saved draft\'s imagePath',
    (tester) async {
      // _defaultUpload (production) deliberately stores the bare
      // ref.fullPath, NOT a ref.getDownloadURL() -- a download URL carries a
      // long-lived bearer token (`...?alt=media&token=...`) baked into the
      // URL itself, and firestore.rules lets any signed-in user read
      // baptism_records, so storing a tokenized URL there would let every
      // parishioner open the full-resolution photo of an entire register
      // spread (roughly ten families' records, mostly minors) with no auth
      // check at all. This test locks in the wiring: whatever the uploader
      // returns must be exactly what ends up in RegisterRecordDraft.imagePath,
      // so a future "helpful" switch to a download URL would be caught here
      // even though the real Firebase Storage call itself can't run in a
      // widget test.
      const uploadedUrl = 'baptism_scans/s1.jpg';
      List<RegisterRecordDraft>? captured;
      await tester.pumpWidget(
        harness(
          service: serviceReturning(200, _scanBody()),
          uploader: (_, _) async => uploadedUrl,
          saveRecords: (drafts) async {
            captured = drafts;
            return drafts.length;
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('pick-image')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan / Process OCR'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('save-rows')));
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.single.imagePath, uploadedUrl);
    },
  );

  testWidgets('a successful save shows a confirmation', (tester) async {
    await tester.pumpWidget(
      harness(
        service: serviceReturning(200, _scanBody()),
        saveRecords: (drafts) async => drafts.length,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('save-rows')));
    // A single pump, not pumpAndSettle: the SnackBar's own auto-dismiss
    // timer means pumpAndSettle would pump straight through its display
    // window and find it already gone.
    await tester.pump();

    expect(find.textContaining('Saved 1 baptismal record'), findsOneWidget);
  });
}
