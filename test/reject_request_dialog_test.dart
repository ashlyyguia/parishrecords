import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/requests_repository.dart';
import 'package:parishrecord/widgets/reject_request_dialog.dart';

void main() {
  Future<String?> openDialog(WidgetTester tester) async {
    String? result = 'untouched';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showRejectRequestDialog(
                context,
                typeLabel: 'Marriage',
                personName: 'Juan Dela Cruz',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('requires a reason, then returns the typed message',
      (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showRejectRequestDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('reject-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Please write a short reason'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('reject-note')),
      '  Record not found, please visit the office  ',
    );
    await tester.tap(find.byKey(const ValueKey('reject-confirm')));
    await tester.pumpAndSettle();
    expect(result, 'Record not found, please visit the office');
  });

  testWidgets('quick reason chip fills the message', (tester) async {
    await openDialog(tester);
    expect(find.textContaining('Marriage certificate for Juan Dela Cruz'),
        findsOneWidget);
    await tester.tap(find.text('Incomplete information'));
    await tester.pump();
    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey('reject-note')),
    );
    expect(field.controller!.text, 'Incomplete information');
  });

  testWidgets('cancel returns null', (tester) async {
    String? result = 'x';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showRejectRequestDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  test('rejection notification includes the message', () {
    final copy = RequestsRepository.notificationForStatus(
      status: 'rejected',
      typeLabel: 'Baptism',
      requesterName: 'Ana',
      note: 'Record not found',
    );
    expect(copy.body, contains('"Record not found"'));
    final plain = RequestsRepository.notificationForStatus(
      status: 'rejected',
      typeLabel: 'Baptism',
    );
    expect(plain.body, isNot(contains('Message from')));
  });

  testWidgets('status note shows only when present', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          RequestStatusNote(request: {
            'status': 'rejected',
            'status_note': 'Please bring a valid ID',
          }),
          RequestStatusNote(request: {'status': 'approved'}),
        ]),
      ),
    ));
    expect(find.byKey(const ValueKey('request-status-note')), findsOneWidget);
    expect(find.text('Please bring a valid ID'), findsOneWidget);
  });
}
