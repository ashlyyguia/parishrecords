import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/models/baptismal_register_row.dart';
import 'package:parishrecord/services/baptismal_row_validation.dart';
import 'package:parishrecord/widgets/baptismal_ocr_review_table.dart';

// The two seeded fields below are built directly (not via `setValue`)
// because `setValue`/`copyWith` always marks a field `edited = true`, which
// makes `OcrField.needsReview` return false regardless of confidence. Using
// `setValue` here would make it impossible to construct a row that actually
// exercises the "low confidence, not yet reviewed" scenario the way real OCR
// output would arrive (edited stays false until a human touches the cell).
BaptismalRegisterRow makeRow({String name = 'JEZL', double confidence = 0.9}) {
  final fields = {
    for (final k in baptismalFieldKeys) k: OcrField(value: '', confidence: confidence),
  };
  fields['nameOfChild'] = OcrField(value: name, confidence: confidence);
  fields['dateOfBaptism'] = OcrField(value: '12 MAY 2016', confidence: confidence);
  return BaptismalRegisterRow(lineNo: '1', fields: fields);
}

Widget harness(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('renders a labelled editable field per column', (tester) async {
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow()],
      issues: const [],
      onChanged: (_, _, _) {},
      onSelectedChanged: (_, _) {},
    )));
    expect(find.text('Name of Child'), findsOneWidget);
    expect(find.text('Date of Baptism'), findsOneWidget);
    expect(find.text('Observations'), findsOneWidget);
    expect(find.text('JEZL'), findsOneWidget);
  });

  testWidgets('reports edits through onChanged', (tester) async {
    final edits = <List<Object>>[];
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow()],
      issues: const [],
      onChanged: (i, f, v) => edits.add([i, f, v]),
      onSelectedChanged: (_, _) {},
    )));
    await tester.enterText(find.byKey(const ValueKey('cell-0-nameOfChild')), 'CORRECTED');
    expect(edits.last, [0, 'nameOfChild', 'CORRECTED']);
  });

  testWidgets('reports deselection', (tester) async {
    final changes = <List<Object>>[];
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow()],
      issues: const [],
      onChanged: (_, _, _) {},
      onSelectedChanged: (i, v) => changes.add([i, v]),
    )));
    await tester.tap(find.byKey(const ValueKey('row-select-0')));
    expect(changes.last, [0, false]);
  });

  testWidgets('shows the issue message on a blocking field', (tester) async {
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow(name: '')],
      issues: const [RowIssue(
        rowIndex: 0, field: 'nameOfChild',
        message: 'Name of child is required.', blocking: true,
      )],
      onChanged: (_, _, _) {},
      onSelectedChanged: (_, _) {},
    )));
    expect(find.text('Name of child is required.'), findsOneWidget);
  });

  testWidgets('marks a low-confidence cell as needing verification', (tester) async {
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow(confidence: 0.3)],
      issues: const [],
      onChanged: (_, _, _) {},
      onSelectedChanged: (_, _) {},
    )));
    expect(find.byIcon(Icons.help_outline), findsWidgets);
  });

  testWidgets('shows the line number for each row', (tester) async {
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow()],
      issues: const [],
      onChanged: (_, _, _) {},
      onSelectedChanged: (_, _) {},
    )));
    expect(find.text('Line 1'), findsOneWidget);
  });
}
