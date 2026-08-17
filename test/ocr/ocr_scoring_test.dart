import 'package:flutter_test/flutter_test.dart';
import 'support/ocr_scoring.dart';

void main() {
  test('normalizeField lowercases, strips punctuation, collapses space', () {
    expect(normalizeField('  Alberto,  SALIGUMBA! '), 'alberto saligumba');
  });

  test('levenshtein counts single-char edits', () {
    expect(levenshtein('kitten', 'sitting'), 3);
    expect(levenshtein('abc', 'abc'), 0);
  });

  test('fieldSimilarity: identical is 1.0, both empty is 1.0', () {
    expect(fieldSimilarity('Saligumba', 'saligumba'), 1.0);
    expect(fieldSimilarity('', '   '), 1.0);
  });

  test('fieldSimilarity: one empty is 0.0, near-miss is partial', () {
    expect(fieldSimilarity('Alberto', ''), 0.0);
    final s = fieldSimilarity('Saligumba', 'Saligamba');
    expect(s, greaterThan(0.8));
    expect(s, lessThan(1.0));
  });

  test('scoreRows aligns by lineNo and computes recall/precision', () {
    final expected = [
      {'lineNo': '1', 'name': 'Alberto Saligumba', 'date': '07 January 2008'},
      {'lineNo': '2', 'name': 'Elliana Eltagon', 'date': '08 February 2016'},
    ];
    final actual = [
      {'lineNo': '1', 'name': 'Alberto Saligumba', 'date': '07 January 2008'},
    ];
    final score = scoreRows(expected: expected, actual: actual);
    expect(score.rowRecall, 0.5);
    expect(score.rowPrecision, 1.0);
    expect(score.fieldMeans['name'], greaterThan(0.4));
    expect(score.headline, greaterThan(0.0));
    expect(score.report('demo'), contains('name'));
  });
}
