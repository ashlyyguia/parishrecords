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
BaptismalRegisterRow makeRow({
  String name = 'TESTA',
  double confidence = 0.9,
  String lineNo = '1',
}) {
  final fields = {
    for (final k in baptismalFieldKeys) k: OcrField(value: '', confidence: confidence),
  };
  fields['nameOfChild'] = OcrField(value: name, confidence: confidence);
  fields['dateOfBaptism'] = OcrField(value: '12 MAY 2016', confidence: confidence);
  return BaptismalRegisterRow(lineNo: lineNo, fields: fields);
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
    // Required fields carry a visible " *" suffix on the label (see the
    // dedicated "marks required fields" test below), so these two use a
    // substring match; `find.text` would demand an exact 'Name of Child'
    // with no suffix, which is no longer true for a required field.
    expect(find.textContaining('Name of Child'), findsOneWidget);
    expect(find.textContaining('Date of Baptism'), findsOneWidget);
    expect(find.text('Observations'), findsOneWidget);
    expect(find.text('TESTA'), findsOneWidget);
  });

  testWidgets('renders a wide column table (No. -> Observations) on large screens', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow()],
      issues: const [],
      onChanged: (_, _, _) {},
      onSelectedChanged: (_, _) {},
      onLineNoChanged: (_, _) {},
    )));

    // Column headers span No. -> Observations; it's a table, not cards; and
    // the editable cell / select / line-no controls keep their keys so the
    // page's interactions still work in this layout.
    expect(find.text('No.'), findsOneWidget);
    expect(find.textContaining('Name of Child'), findsWidgets);
    expect(find.text('Observations'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(find.byKey(const ValueKey('cell-0-nameOfChild')), findsOneWidget);
    expect(find.byKey(const ValueKey('row-select-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('line-no-0')), findsOneWidget);
    expect(find.text('TESTA'), findsOneWidget);
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
    expect(find.text('Line'), findsOneWidget);
    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey('line-no-0')),
    );
    expect(field.initialValue, '1');
  });

  // FIX 8 regression: `lineNo` used to render as static `Text`, even though
  // it can be fabricated (a sequential fallback) when the printed NO. column
  // is unreadable -- and the warning copy tells the reviewer to "verify each
  // row's line number matches the physical register", something static text
  // structurally prevents. It must be editable, wired through the same kind
  // of callback as every other field.
  testWidgets('reports line number edits through onLineNoChanged', (tester) async {
    final edits = <List<Object>>[];
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow()],
      issues: const [],
      onChanged: (_, _, _) {},
      onSelectedChanged: (_, _) {},
      onLineNoChanged: (i, v) => edits.add([i, v]),
    )));
    await tester.enterText(find.byKey(const ValueKey('line-no-0')), '47');
    expect(edits.last, [0, '47']);
  });

  testWidgets('the line number field is disabled when no onLineNoChanged is provided', (tester) async {
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow()],
      issues: const [],
      onChanged: (_, _, _) {},
      onSelectedChanged: (_, _) {},
    )));
    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey('line-no-0')),
    );
    expect(field.enabled, isFalse);
  });

  testWidgets('marks required fields with a visible and accessible marker', (tester) async {
    // Regression test for fix round 1: a required field that already HOLDS
    // a valid value must still show its required marker. A blocking
    // RowIssue only appears once a field is empty/invalid, so relying on
    // that mechanism alone silently drops the marker for the common case
    // of a filled-in row — exactly what this test pins down.
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow(name: 'TESTA')],
      issues: const [],
      onChanged: (_, _, _) {},
      onSelectedChanged: (_, _) {},
    )));
    expect(find.text('Name of Child *'), findsOneWidget);
    expect(find.text('Date of Baptism *'), findsOneWidget);
    // Not signalled by the glyph alone: the accessible name is an explicit
    // "required" announcement rather than relying on a screen reader to
    // vocalise the "*" character meaningfully.
    final semantics = tester.getSemantics(find.text('Name of Child *'));
    expect(semantics.label, contains('required'));
    // Optional fields get no marker and no "required" semantics.
    expect(find.text('Observations'), findsOneWidget);
  });

  testWidgets('renders nothing for an empty rows list', (tester) async {
    await tester.pumpWidget(harness(const BaptismalOcrReviewTable(
      rows: [],
      issues: [],
      onChanged: _noopOnChanged,
      onSelectedChanged: _noopOnSelectedChanged,
    )));
    expect(find.byType(Card), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a row with an empty lineNo without crashing', (tester) async {
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow(lineNo: '')],
      issues: const [],
      onChanged: (_, _, _) {},
      onSelectedChanged: (_, _) {},
    )));
    expect(find.text('Line'), findsOneWidget);
    expect(find.byKey(const ValueKey('line-no-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a blocking issue wins over a non-blocking issue on the same field', (tester) async {
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow(name: 'DUPLICATE')],
      issues: const [
        RowIssue(
          rowIndex: 0,
          field: 'nameOfChild',
          message: 'A baptism for this name and date already exists.',
          blocking: false,
        ),
        RowIssue(
          rowIndex: 0,
          field: 'nameOfChild',
          message: 'Name of child is required.',
          blocking: true,
        ),
      ],
      onChanged: (_, _, _) {},
      onSelectedChanged: (_, _) {},
    )));
    expect(find.text('Name of child is required.'), findsOneWidget);
    expect(find.text('A baptism for this name and date already exists.'), findsNothing);
  });

  testWidgets('ignores an issue whose rowIndex is out of range', (tester) async {
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [makeRow()],
      issues: const [RowIssue(
        rowIndex: 5,
        field: 'nameOfChild',
        message: 'Should never be shown.',
        blocking: true,
      )],
      onChanged: (_, _, _) {},
      onSelectedChanged: (_, _) {},
    )));
    expect(find.text('Should never be shown.'), findsNothing);
    expect(find.byType(Card), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles a very long field value without throwing', (tester) async {
    final row = makeRow();
    // The register's place-of-birth column routinely wraps to two lines;
    // simulate that with a long OCR read to make sure the bounded
    // TextFormField (minLines: 1, maxLines: 3) copes.
    row.setValue(
      'placeAndBirthDate',
      'Barangay Poblacion, Municipality of Initao, Misamis Oriental, '
      'Philippines, born on the twelfth day of May in the year nineteen '
      'hundred and ninety-eight, as recorded by the attending midwife',
    );
    await tester.pumpWidget(harness(BaptismalOcrReviewTable(
      rows: [row],
      issues: const [],
      onChanged: (_, _, _) {},
      onSelectedChanged: (_, _) {},
    )));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('cell-0-placeAndBirthDate')), findsOneWidget);
  });
}

void _noopOnChanged(int rowIndex, String field, String value) {}
void _noopOnSelectedChanged(int rowIndex, bool selected) {}
