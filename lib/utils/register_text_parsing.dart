// Helpers for turning free-text register cells (often OCR'd) into the
// separate pieces a certificate prints.

/// Splits a register "parents" cell into individual names, in the order they
/// were written.
///
/// Handles explicit separators ("/", "&", " and ", ";", ",") and the common
/// OCR form with none, e.g. "EGLORIA M . PATEÑO LITO E . BALILI": each name
/// is "FIRST [MIDDLE-INITIAL .] SURNAME", so a new name starts right after the
/// surname that follows a middle initial.
List<String> splitParentNames(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const [];

  for (final sep in [RegExp(r'\s*/\s*'), RegExp(r'\s*&\s*'),
      RegExp(r'\s+and\s+', caseSensitive: false), RegExp(r'\s*;\s*'),
      RegExp(r'\s*,\s*')]) {
    final parts = text
        .split(sep)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length >= 2) return parts;
  }

  final tokens = text.split(RegExp(r'\s+'));
  bool isInitial(int i) {
    final t = tokens[i];
    if (RegExp(r'^[A-Za-zÑñ]\.$').hasMatch(t)) return true;
    // "M" followed by a lone "." token (OCR spacing).
    return RegExp(r'^[A-Za-zÑñ]$').hasMatch(t) &&
        i + 1 < tokens.length &&
        tokens[i + 1] == '.';
  }

  for (var i = 1; i < tokens.length; i++) {
    if (!isInitial(i)) continue;
    var surname = i + 1;
    if (surname < tokens.length && tokens[surname] == '.') surname++;
    // A name needs a surname after the initial and something after it.
    if (surname < tokens.length - 1) {
      final first = tokens.sublist(0, surname + 1).join(' ');
      final second = tokens.sublist(surname + 1).join(' ');
      return [_tidy(first), _tidy(second)];
    }
    break;
  }
  return [_tidy(text)];
}

/// "M . PATEÑO" -> "M. PATEÑO".
String _tidy(String s) =>
    s.replaceAll(RegExp(r'\s+\.'), '.').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Picks the mother and the father out of a parents cell.
///
/// The parent who shares [familySurname] (the child's surname) is taken as
/// the father; otherwise the register's order is used with the mother first,
/// as the parish's marriage register writes them ("mother's maiden name, then
/// father").
({String mother, String father}) motherAndFather(
  String raw, {
  String familySurname = '',
}) {
  final names = splitParentNames(raw);
  if (names.isEmpty) return (mother: '', father: '');
  if (names.length == 1) return (mother: names.first, father: '');

  String lastWord(String s) {
    final w = s.trim().split(RegExp(r'\s+'));
    return w.isEmpty ? '' : w.last.replaceAll('.', '').toUpperCase();
  }

  final surname = familySurname.trim().toUpperCase();
  if (surname.isNotEmpty) {
    final i = names.indexWhere((n) => lastWord(n) == surname);
    if (i != -1) {
      final father = names[i];
      final mother = [
        for (var j = 0; j < names.length; j++)
          if (j != i) names[j],
      ].join(' / ');
      return (mother: mother, father: father);
    }
  }
  return (mother: names.first, father: names.sublist(1).join(' / '));
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

int? _month(String word) {
  final w = word.toLowerCase().replaceAll('.', '');
  if (w.length < 3) return null;
  for (final e in _months.entries) {
    if (w.startsWith(e.key)) return e.value;
  }
  return null;
}

DateTime? _safe(int y, int m, int d) {
  if (y < 1800 || y > 2200 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  return dt.month == m ? dt : null;
}

/// Finds a date inside free text such as "Oroquieta City, May 5, 1995" or
/// "05/12/1995 Bunga" and returns it with the remaining text (the place).
({DateTime? date, String place}) splitPlaceAndDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return (date: null, place: '');

  final patterns = <(RegExp, DateTime? Function(RegExpMatch))>[
    // May 5, 1995 / Sept. 05 1995
    (
      RegExp(r'([A-Za-z]{3,9}\.?)\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})'),
      (m) {
        final mo = _month(m[1]!);
        return mo == null ? null : _safe(int.parse(m[3]!), mo, int.parse(m[2]!));
      },
    ),
    // 5 May 1995 / 5th of May, 1995
    (
      RegExp(r'(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?([A-Za-z]{3,9}\.?),?\s+(\d{4})'),
      (m) {
        final mo = _month(m[2]!);
        return mo == null ? null : _safe(int.parse(m[3]!), mo, int.parse(m[1]!));
      },
    ),
    // 1995-05-05
    (
      RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'),
      (m) => _safe(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)),
    ),
    // 05/12/1995, 5-12-95 (month first unless the first number is > 12)
    (
      RegExp(r'(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})'),
      (m) {
        var a = int.parse(m[1]!), b = int.parse(m[2]!), y = int.parse(m[3]!);
        if (y < 100) y += y >= 50 ? 1900 : 2000;
        return a > 12 ? _safe(y, b, a) : _safe(y, a, b);
      },
    ),
  ];

  for (final (re, toDate) in patterns) {
    final m = re.firstMatch(text);
    if (m == null) continue;
    final date = toDate(m);
    if (date == null) continue;
    final place = '${text.substring(0, m.start)} ${text.substring(m.end)}'
        .replaceAll(RegExp(r'^[\s,;/\-]+|[\s,;/\-]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return (date: date, place: place);
  }
  return (date: null, place: text);
}
