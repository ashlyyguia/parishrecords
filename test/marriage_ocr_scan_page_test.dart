import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parishrecord/models/register_ocr_entry.dart';
import 'package:parishrecord/screens/admin/pages/marriage_ocr_scan_page.dart';
import 'package:parishrecord/services/marriage_ocr_service.dart';

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Map<String, dynamic> _scanBody({
  String groom = 'Marlon',
  String bride = 'Ana',
  List<String> warnings = const [],
}) => {
  'success': true,
  'data': {
    'scanId': 's1',
    'rotation': 0,
    'warnings': warnings,
    'rows': [
      {
        'lineNo': '1',
        'groom': {'name': groom, 'actualAddress': 'Bunga Oroquieta'},
        'bride': {'name': bride},
        'dateOfMarriage': 'Jan 07 2023',
        'minister': 'Fr Alcher',
        'licenseNumber': '3518247',
      },
    ],
  },
};

MarriageOcrService serviceReturning(int status, Object body) => MarriageOcrService(
      client: MockClient((_) async => http.Response(jsonEncode(body), status)),
    );

Widget harness({
  required MarriageOcrService service,
  Future<int> Function(List<RegisterRecordDraft>)? saveRecords,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: MarriageOcrScanPage(
        ocrService: service,
        imagePicker: (_) async => _png,
        idTokenProvider: () async => 'test-token',
        saveRecords: saveRecords ?? (_) async => 1,
        existingRecords: () => const [],
      ),
    ),
  );
}

Future<void> toReview(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('pick-image')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan / Process OCR'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('scans and lands on review with groom/bride shown', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _scanBody())));
    await toReview(tester);
    expect(find.textContaining('Marlon'), findsWidgets);
    expect(find.textContaining('Ana'), findsWidgets);
  });

  testWidgets('save builds a marriage draft with the couple name and register notes',
      (tester) async {
    List<RegisterRecordDraft>? captured;
    await tester.pumpWidget(harness(
      service: serviceReturning(200, _scanBody()),
      saveRecords: (drafts) async {
        captured = drafts;
        return drafts.length;
      },
    ));
    await toReview(tester);
    await tester.tap(find.byKey(const ValueKey('save-rows')));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.single.name, 'Marlon & Ana');
    expect(captured!.single.type.name, 'marriage');
    expect(captured!.single.notes, contains('manual_marriage_register'));
  });

  testWidgets('blocks save while the bride name is empty', (tester) async {
    await tester.pumpWidget(harness(service: serviceReturning(200, _scanBody(bride: ''))));
    await toReview(tester);
    final saveButton =
        tester.widget<FilledButton>(find.byKey(const ValueKey('save-rows')));
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('surfaces the groom/bride split warning copy', (tester) async {
    await tester.pumpWidget(harness(
      service: serviceReturning(200, _scanBody(warnings: ['GROOM_BRIDE_SPLIT_UNCERTAIN'])),
    ));
    await toReview(tester);
    expect(find.byKey(const ValueKey('warnings-panel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('warnings-panel')));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be told apart'), findsOneWidget);
  });
}
