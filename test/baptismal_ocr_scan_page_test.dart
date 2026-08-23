import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parishrecord/models/register_ocr_entry.dart';
import 'package:parishrecord/screens/admin/pages/baptismal_ocr_scan_page.dart';
import 'package:parishrecord/services/baptismal_ocr_service.dart';

// A 1x1 PNG is enough — the page only needs bytes Image.memory can decode.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00,
  0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63,
  0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

Map<String, dynamic> _scanBody({String name = 'JEZL ANTOINETTE'}) => {
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
      ),
    ),
  );
}

BaptismalOcrService serviceReturning(int status, Object body) => BaptismalOcrService(
  client: MockClient((_) async => http.Response(jsonEncode(body), status)),
);

void main() {
  testWidgets('starts on the upload step', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _scanBody())));
    expect(find.text('Upload or capture a register page'), findsOneWidget);
    expect(find.text('Scan / Process OCR'), findsNothing);
  });

  testWidgets('shows a preview and the scan action after picking', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _scanBody())));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Scan / Process OCR'), findsOneWidget);
  });

  testWidgets('runs OCR and lands on the review step', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _scanBody())));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.text('JEZL ANTOINETTE'), findsOneWidget);
    expect(find.textContaining('Save'), findsWidgets);
  });

  testWidgets('blocks save while a required field is empty', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _scanBody(name: ''))));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.text('Name of child is required.'), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(find.byKey(const ValueKey('save-rows')));
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('unblocks save once the field is corrected', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _scanBody(name: ''))));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cell-0-nameOfChild')), 'CORRECTED');
    await tester.pumpAndSettle();
    final saveButton = tester.widget<FilledButton>(find.byKey(const ValueKey('save-rows')));
    expect(saveButton.onPressed, isNotNull);
  });

  testWidgets('shows a retryable error and keeps the image', (tester) async {
    await tester.pumpWidget(harness(
      service: serviceReturning(429, {'success': false, 'code': 'VISION_QUOTA', 'message': 'rate limited'}),
    ));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.text('rate limited'), findsOneWidget);
    expect(find.text('Retry OCR'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget); // image survived the failure
  });

  testWidgets('hides retry for a non-retryable configuration error', (tester) async {
    await tester.pumpWidget(harness(
      service: serviceReturning(500, {'success': false, 'code': 'VISION_AUTH', 'message': 'not configured'}),
    ));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.text('not configured'), findsOneWidget);
    expect(find.text('Retry OCR'), findsNothing);
  });

  // --- Edge cases -----------------------------------------------------

  testWidgets('a different-image error hides retry and keeps the image', (tester) async {
    await tester.pumpWidget(harness(
      service: serviceReturning(200, {
        'success': false,
        'code': 'NO_TEXT_FOUND',
        'message': 'no text found',
      }),
    ));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.text('no text found'), findsOneWidget);
    expect(find.text('Retry OCR'), findsNothing);
    expect(find.text('Choose a different image'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget); // image survived the failure
  });

  testWidgets('cancelling the picker leaves the page on the upload step', (tester) async {
    await tester.pumpWidget(harness(
      service: serviceReturning(200, _scanBody()),
      picker: (_) async => null,
    ));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    expect(find.text('Upload or capture a register page'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a scan with zero rows explains why and disables save', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _emptyScanBody())));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No rows were detected'), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(find.byKey(const ValueKey('save-rows')));
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('deselecting the only row disables save', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _scanBody())));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    var saveButton = tester.widget<FilledButton>(find.byKey(const ValueKey('save-rows')));
    expect(saveButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('row-select-0')));
    await tester.pumpAndSettle();

    saveButton = tester.widget<FilledButton>(find.byKey(const ValueKey('save-rows')));
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('OCR still runs even when the storage upload fails', (tester) async {
    await tester.pumpWidget(harness(
      service: serviceReturning(200, _scanBody()),
      uploader: (_, _) async => throw Exception('storage unavailable'),
    ));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();
    // Landed on review with the row intact — the failed upload did not
    // block OCR from proceeding.
    expect(find.text('JEZL ANTOINETTE'), findsOneWidget);
  });

  testWidgets('a save that throws shows an error and stays on review', (tester) async {
    await tester.pumpWidget(harness(
      service: serviceReturning(200, _scanBody()),
      saveRecords: (_) async => throw Exception('write failed'),
    ));
    await tester.tap(find.byKey(const ValueKey('pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan / Process OCR'));
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(find.byKey(const ValueKey('save-rows')));
    expect(saveButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('save-rows')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Save failed'), findsOneWidget);
    // Still on the review step with the row intact — a failed save must
    // not lose the user's work.
    expect(find.text('JEZL ANTOINETTE'), findsOneWidget);
  });

  testWidgets('a successful save shows a confirmation', (tester) async {
    await tester.pumpWidget(harness(
      service: serviceReturning(200, _scanBody()),
      saveRecords: (drafts) async => drafts.length,
    ));
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
