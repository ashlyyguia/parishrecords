import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/requests_repository.dart';
import 'package:parishrecord/widgets/request_record_check.dart';

void main() {
  final manual = <String, dynamic>{
    'record_verified': false,
    'request_details': {
      'full_name': 'Maria Santos',
      'sacrament_date': '1998-05-10',
      'father_name': '',
      'notes': 'Baptized at the chapel',
    },
  };
  final linked = <String, dynamic>{
    'record_verified': true,
    'record_id': 'abc123',
  };

  test('needsRecordCheck flags only unverified requests', () {
    expect(RequestsRepository.needsRecordCheck(manual), isTrue);
    expect(RequestsRepository.needsRecordCheck(linked), isFalse);
    // Older requests have no flag and a record id.
    expect(RequestsRepository.needsRecordCheck({'record_id': 'x'}), isFalse);
  });

  test('detailLines keeps order and drops blanks', () {
    final lines = RequestsRepository.detailLines(manual);
    expect(lines.map((e) => e.key).toList(),
        ['Full name', 'Date of sacrament', 'Notes']);
    expect(lines.first.value, 'Maria Santos');
    expect(RequestsRepository.detailLines(linked), isEmpty);
  });

  testWidgets('badge and details render for manual requests only',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          RequestDetailLines(request: manual),
          RequestRecordCheckBadge(request: linked),
        ]),
      ),
    ));
    expect(find.byKey(const ValueKey('record-not-verified')), findsOneWidget);
    expect(find.text('Record not yet verified'), findsOneWidget);
    expect(find.textContaining('Maria Santos'), findsOneWidget);
  });
}
