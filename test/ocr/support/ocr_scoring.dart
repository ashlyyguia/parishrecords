String normalizeField(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      final del = prev[j + 1] + 1;
      final ins = curr[j] + 1;
      final sub = prev[j] + cost;
      var m = del < ins ? del : ins;
      if (sub < m) m = sub;
      curr[j + 1] = m;
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

double fieldSimilarity(String a, String b) {
  final na = normalizeField(a);
  final nb = normalizeField(b);
  if (na.isEmpty && nb.isEmpty) return 1.0;
  if (na.isEmpty || nb.isEmpty) return 0.0;
  final dist = levenshtein(na, nb);
  final maxLen = na.length > nb.length ? na.length : nb.length;
  return 1.0 - dist / maxLen;
}

const List<String> scoredFields = [
  'name',
  'date',
  'placeAndBirthDate',
  'parents',
  'residentsOf',
  'minister',
  'sponsors',
];

class FixtureScore {
  FixtureScore({
    required this.rowPrecision,
    required this.rowRecall,
    required this.fieldMeans,
    required this.headline,
    required this.rowScores,
  });

  final double rowPrecision;
  final double rowRecall;
  final Map<String, double> fieldMeans;
  final double headline;
  final List<Map<String, double>> rowScores;

  String report(String label) {
    final b = StringBuffer('OCR score [$label]\n');
    b.writeln('  headline: ${headline.toStringAsFixed(3)}');
    b.writeln('  row recall: ${rowRecall.toStringAsFixed(3)}  '
        'precision: ${rowPrecision.toStringAsFixed(3)}');
    for (final f in scoredFields) {
      b.writeln('  $f: ${(fieldMeans[f] ?? 0).toStringAsFixed(3)}');
    }
    return b.toString();
  }
}

FixtureScore scoreRows({
  required List<Map<String, String>> expected,
  required List<Map<String, String>> actual,
  Map<String, double>? weights,
}) {
  final w = weights ?? const {'name': 2.0, 'date': 2.0};
  final actualByLine = <String, Map<String, String>>{};
  for (final row in actual) {
    final ln = (row['lineNo'] ?? '').trim();
    if (ln.isNotEmpty) actualByLine.putIfAbsent(ln, () => row);
  }

  final fieldTotals = {for (final f in scoredFields) f: 0.0};
  final rowScores = <Map<String, double>>[];
  var matched = 0;

  for (final exp in expected) {
    final ln = (exp['lineNo'] ?? '').trim();
    final act = actualByLine[ln];
    if (act != null) matched++;
    final rowScore = <String, double>{};
    for (final f in scoredFields) {
      final sim = fieldSimilarity(exp[f] ?? '', act?[f] ?? '');
      rowScore[f] = sim;
      fieldTotals[f] = fieldTotals[f]! + sim;
    }
    rowScores.add(rowScore);
  }

  final n = expected.isEmpty ? 1 : expected.length;
  final fieldMeans = {for (final f in scoredFields) f: fieldTotals[f]! / n};

  var weightSum = 0.0;
  var weighted = 0.0;
  for (final f in scoredFields) {
    final fw = w[f] ?? 1.0;
    weighted += fieldMeans[f]! * fw;
    weightSum += fw;
  }

  return FixtureScore(
    rowPrecision: actual.isEmpty ? 0.0 : matched / actual.length,
    rowRecall: expected.isEmpty ? 0.0 : matched / expected.length,
    fieldMeans: fieldMeans,
    headline: weightSum == 0 ? 0.0 : weighted / weightSum,
    rowScores: rowScores,
  );
}
