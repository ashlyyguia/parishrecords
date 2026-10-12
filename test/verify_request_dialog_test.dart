import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/register_record_search.dart';
import 'package:parishrecord/services/requests_repository.dart';
import 'package:parishrecord/widgets/verify_request_dialog.dart';

const _rec = RegisterRecordOption(
  id: 'r1',
  name: 'Maria Santos',
  fields: [
    MapEntry('Vol. No.', '3'),
    MapEntry('Parents', 'Jose Santos & Ana Cruz'),
    MapEntry('Sponsors', 'Pedro Reyes'),
  ],
);

Future<VerifyRequestResult?> _open(
  WidgetTester tester,
  Map<String, dynamic> request, {
  List<RegisterRecordOption> results = const [_rec],
  RegisterRecordOption? linked,
}) async {
  VerifyRequestResult? result;
  var done = false;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            result = await showVerifyRequestDialog(
              context,
              request: request,
              loadLinked: (_, _) async => linked,
              search: (_, _) async => results,
            );
            done = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(done, isFalse);
  return result;
}

FilledButton _confirm(WidgetTester tester) => tester.widget<FilledButton>(
      find.byKey(const ValueKey('verify-confirm')),
    );

Future<void> _tickAll(WidgetTester tester) async {
  for (final c in kVerificationChecks) {
    final f = find.byKey(ValueKey('check-${c.$1}'));
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pump();
  }
}

void main() {
  testWidgets('needs a register record and every check before verifying',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    await _open(tester, {
      'request_type': 'baptism',
      'certificate_for_name': 'Maria Santos',
      'record_verified': false,
      'request_details': {'full_name': 'Maria Santos'},
    });

    expect(_confirm(tester).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('verify-search-button')));
    await tester.pumpAndSettle();
    // Every stored detail is shown in the search result.
    expect(find.text('Jose Santos & Ana Cruz'), findsOneWidget);
    expect(find.text('Pedro Reyes'), findsOneWidget);
    await tester.tap(find.text('Use this'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('verify-selected-record')), findsOneWidget);
    expect(_confirm(tester).onPressed, isNull);

    await _tickAll(tester);
    expect(_confirm(tester).onPressed, isNotNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('a linked record is shown and returned with the checks',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    VerifyRequestResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showVerifyRequestDialog(
                context,
                request: const {
                  'request_type': 'marriage',
                  'record_id': 'r1',
                  'record_verified': true,
                },
                loadLinked: (_, _) async => _rec,
                search: (_, _) async => const [],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Maria Santos'), findsOneWidget);
    await _tickAll(tester);
    await tester.enterText(
        find.byKey(const ValueKey('verify-note')), 'Book 3, Page 12');
    await tester.tap(find.byKey(const ValueKey('verify-confirm')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.record.id, 'r1');
    expect(result!.checks.values.every((v) => v), isTrue);
    expect(result!.note, 'Book 3, Page 12');
    await tester.binding.setSurfaceSize(null);
  });

  test('register details are labelled, ordered and skip internal keys', () {
    final fields = registerRecordFields({
      'source': 'Bunga, Oroquieta',
      'notes': '{"source":"baptismal_ocr_vision","status":"official",'
          '"sponsors":"Pedro Reyes","volNo":"3","lineNo":"7",'
          '"nameOfChild":"MARIA SANTOS","parents":"Jose & Ana",'
          '"ocrScanId":"abc","originalImagePath":"x.jpg","minister":"",'
          '"groom":{"name":"Juan","parents":"A & B"}}',
    });
    final labels = fields.map((e) => e.key).toList();
    expect(labels.first, 'Vol. No.');
    expect(labels, containsAll(['Line No.', 'Name of child', 'Parents', 'Sponsors']));
    expect(labels, contains('Groom — Name'));
    expect(labels, contains('Groom — Parents'));
    expect(labels, isNot(contains('Minister'))); // empty value skipped
    expect(labels.any((l) => l.toLowerCase().contains('scan')), isFalse);
    expect(labels.any((l) => l.toLowerCase().contains('image')), isFalse);
    expect(fields.last.key, 'Residence / source');
    expect(fields.last.value, 'Bunga, Oroquieta');
  });

  test('parishioners get a "verified" notification', () {
    final copy = RequestsRepository.notificationForStatus(
      status: 'verified',
      typeLabel: 'Baptism',
      requesterName: 'Ana',
    );
    expect(copy.title, 'Certificate request verified');
    expect(copy.body, contains('awaiting approval'));
  });

  test('verification summary names who verified it', () {
    final s = RequestsRepository.verificationSummary({
      'verification': {
        'verified_by_name': 'Staff Ana',
        'verified_at': DateTime(2026, 10, 12),
      },
    });
    expect(s, 'Verified by Staff Ana · Oct 12, 2026');
  });
}
