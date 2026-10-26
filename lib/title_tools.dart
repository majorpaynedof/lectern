/// Helpers for finding a book online when its title or author in the library
/// isn't quite what the metadata sources expect, e.g.
/// "(SW-025) Star Wars: Splinter of the Mind's Eye (Unabridged)".
library;

final _brackets = RegExp(r'\s*[\(\[\{][^\)\]\}]*[\)\]\}]\s*');
final _bookNumber = RegExp(
    r'[,:\-–—]?\s*\b(book|bk|volume|vol|part|pt|episode|ep|no|number)\.?\s*#?\s*\d+(\.\d+)?\b',
    caseSensitive: false);
final _hashNumber = RegExp(r'\s*#\s*\d+(\.\d+)?\b');
final _leadingNumber = RegExp(r'^\s*\d+(\.\d+)?\s*[\.\-–—:]\s+');
final _trailingNumber = RegExp(r'\s+\d+(\.\d+)?\s*$');
final _junk = RegExp(r'\b(unabridged|abridged|audiobook|audio book|a novel|dramatized|dramatised)\b',
    caseSensitive: false);
final _spaces = RegExp(r'\s+');
final _edgePunct = RegExp(r'^[\s,:;\-–—\.]+|[\s,:;\-–—\.]+$');

String _tidy(String s) => s.replaceAll(_spaces, ' ').replaceAll(_edgePunct, '').trim();

/// The title with codes, brackets, "Book 3", "(Unabridged)" and the like
/// removed. "(SW-025) Star Wars: Splinter of the Mind's Eye" ->
/// "Star Wars: Splinter of the Mind's Eye".
String cleanTitle(String title) {
  var s = title.replaceAll(_brackets, ' ');
  s = s.replaceAll(_junk, ' ');
  s = s.replaceAll(_bookNumber, ' ');
  s = s.replaceAll(_hashNumber, ' ');
  s = s.replaceFirst(_leadingNumber, '');
  final t = _tidy(s);
  return t.isEmpty ? _tidy(title) : t;
}

/// Looser versions of a title to search for, most likely first, without the
/// original and without repeats. For "Star Wars: Splinter of the Mind's
/// Eye (Unabridged)": the cleaned title, then the part after the colon
/// ("Splinter of the Mind's Eye"), then the part before it ("Star Wars").
List<String> titleVariants(String title) {
  final out = <String>[];
  void add(String v) {
    final t = _tidy(v);
    if (t.length < 2) return;
    final key = t.toLowerCase();
    if (key == _tidy(title).toLowerCase()) return;
    if (out.any((o) => o.toLowerCase() == key)) return;
    out.add(t);
  }

  final clean = cleanTitle(title);
  add(clean);
  final noTrailingNumber = clean.replaceFirst(_trailingNumber, '');
  add(noTrailingNumber);
  final plain = title.replaceAll(_brackets, ' ');
  for (final sep in [':', ' - ', ' – ', ' — ']) {
    final i = clean.indexOf(sep);
    if (i > 0) {
      final before = clean.substring(0, i);
      final after = clean.substring(i + sep.length);
      // "All These Worlds: Bobiverse, Book 3": the part after the colon is
      // the series, so the title comes first. Otherwise ("Star Wars:
      // Splinter of the Mind's Eye") the part after is usually the title.
      final j = plain.indexOf(sep);
      final seriesAfter = j > 0 && _bookNumber.hasMatch(plain.substring(j + sep.length));
      if (seriesAfter) {
        add(before);
        add(after);
      } else {
        add(after);
        add(before);
      }
      break;
    }
  }
  return out;
}

/// The first few meaningful words of a title, for a broad "same author,
/// similar title" search.
String shortTitle(String title, {int words = 2}) {
  const skip = {'the', 'a', 'an', 'of', 'and'};
  final w = cleanTitle(title).split(' ').where((x) => x.isNotEmpty).toList();
  final keep = <String>[];
  for (final x in w) {
    if (keep.isEmpty && skip.contains(x.toLowerCase())) continue;
    keep.add(x);
    if (keep.length >= words) break;
  }
  return keep.join(' ');
}

/// The main author only, without roles or extra names:
/// "Dennis E. Taylor, Ray Porter - narrator" -> "Dennis E. Taylor".
String cleanAuthor(String author) {
  var s = author;
  for (final sep in [',', ';', '&', ' and ', ' with ', ' / ']) {
    final i = s.toLowerCase().indexOf(sep);
    if (i > 0) s = s.substring(0, i);
  }
  s = s.replaceAll(_brackets, ' ');
  s = s.replaceAll(RegExp(r'\s+-\s+.*$'), ''); // "Name - translator"
  s = s.replaceAll(RegExp(r'\b(dr|prof|sir|phd|jr|sr)\b\.?', caseSensitive: false), ' ');
  return _tidy(s);
}

String _letters(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// How alike two titles are, from 0 (nothing in common) to 1 (the same),
/// ignoring case, punctuation, brackets and "Book 3"-style extras.
double titleSimilarity(String a, String b) {
  final x = _letters(cleanTitle(a));
  final y = _letters(cleanTitle(b));
  if (x.isEmpty || y.isEmpty) return 0;
  if (x == y) return 1;
  if (x.contains(y) || y.contains(x)) {
    final ratio = (x.length < y.length ? x.length / y.length : y.length / x.length);
    return 0.75 + 0.25 * ratio;
  }
  return _dice(x, y);
}

/// How alike two author names are (0..1). Matches "J.R.R. Tolkien" with
/// "J. R. R. Tolkien", and a surname alone with the full name.
double authorSimilarity(String a, String b) {
  final x = _letters(cleanAuthor(a)).replaceAll(' ', '');
  final y = _letters(cleanAuthor(b)).replaceAll(' ', '');
  if (x.isEmpty || y.isEmpty) return 0;
  if (x == y) return 1;
  final lastX = _letters(cleanAuthor(a)).split(' ').last;
  final lastY = _letters(cleanAuthor(b)).split(' ').last;
  if (lastX.length > 2 && lastX == lastY) return 0.85;
  return _dice(x, y);
}

double _dice(String a, String b) {
  Set<String> grams(String s) {
    final t = s.replaceAll(' ', '');
    return {for (var i = 0; i < t.length - 1; i++) t.substring(i, i + 2)};
  }

  final ga = grams(a);
  final gb = grams(b);
  if (ga.isEmpty || gb.isEmpty) return 0;
  final common = ga.intersection(gb).length;
  return 2 * common / (ga.length + gb.length);
}
