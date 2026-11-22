/// Rules for "Find duplicates": spots the same book entered more than once,
/// e.g. "The Two Week Curse" and "The Two Week Curse: A LitRPG Adventure",
/// or two books that are both "Discworld #28" by the same author. Nothing
/// here changes anything; the screen shows the copies side by side and you
/// decide.
library;

import 'series_check.dart';
import 'title_tools.dart';

class DupBook {
  const DupBook({
    required this.id,
    required this.title,
    required this.author,
    this.duration = 0,
    this.series = '',
    this.path = '',
  });
  final String id;
  final String title;
  final String author;

  /// Seconds; 0 if unknown.
  final double duration;

  /// The server's series text, e.g. "Discworld #28".
  final String series;

  /// The book's folder on the server; empty if unknown.
  final String path;
}

class DuplicateGroup {
  const DuplicateGroup({required this.ids, required this.confidence, required this.reason});
  final List<String> ids;

  /// 'High' or 'Medium'.
  final String confidence;
  final String reason;
}

String _letters(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

final _by = RegExp(r'\s+by\s+(.+)$', caseSensitive: false);
final _segmentSplit = RegExp(r'\s*(?::|\s[-–—]\s)\s*');
const _skip = {'the', 'a', 'an', 'of', 'and'};

/// The title without codes, "(Unabridged)", "Book 3" or a trailing
/// "by <the author>".
String coreTitle(String title, String author) {
  var t = cleanTitle(title);
  final m = _by.firstMatch(t);
  if (m != null && authorSimilarity(m.group(1)!, author) >= 0.85) t = t.substring(0, m.start);
  return _letters(t);
}

/// The parts of a title split at colons and dashes:
/// "11 ABY - The Jedi Academy Trilogy 02 - Dark Apprentice" -> three parts.
List<String> _segments(String title) {
  final t = cleanTitle(title);
  final parts = t.split(_segmentSplit).map(_letters).where((p) => p.isNotEmpty).toList();
  return parts.length > 1 ? parts : const [];
}

String _firstWord(String letters) {
  for (final w in letters.split(' ')) {
    if (w.isNotEmpty && !_skip.contains(w)) return w;
  }
  return letters.split(' ').first;
}

/// Durations within [tolerance] of each other (unknown counts as close).
bool _similarLength(double a, double b, {double tolerance = 0.10}) {
  if (a <= 0 || b <= 0) return true;
  final big = a > b ? a : b;
  return (a - b).abs() / big <= tolerance;
}

/// The last part of a path, without a file extension:
/// "/books/Star Wars/21. 27 BBY - Jedi Quest 03 - The Dangerous Games".
String _folderName(String path) {
  final parts = path.replaceAll('\\', '/').split('/').where((p) => p.trim().isNotEmpty).toList();
  if (parts.isEmpty) return '';
  return parts.last.replaceFirst(RegExp(r'\.(m4b|m4a|mp3|aac|flac|ogg|opus|wma|wav)$', caseSensitive: false), '');
}

List<String> _numbers(String s) =>
    [for (final m in RegExp(r'\d+(?:\.\d+)?').allMatches(s)) (double.tryParse(m.group(0)!) ?? 0).toString()];

/// The folders say these are different books, whatever the details say:
/// different numbers ("Jedi Quest 03" / "Jedi Quest 04") or clearly
/// different names ("The Unifying Force" / "Force Heretic III Reunion").
/// Books often share a wrong title after a bad match; the folder usually
/// still names the real book.
bool differentFolders(String pathA, String pathB) {
  final a = _folderName(pathA);
  final b = _folderName(pathB);
  if (a.isEmpty || b.isEmpty) return false;
  if (_letters(a) == _letters(b)) return false;
  final na = _numbers(a), nb = _numbers(b);
  if (na.isNotEmpty && nb.isNotEmpty && na.join(',') != nb.join(',')) return true;
  // Compare the words, ignoring numbers and "(Unabridged)": the whole names,
  // and each whole name against the other's parts (one may add a
  // subtitle). Parts aren't compared with each other: a shared "12 ABY -"
  // prefix doesn't make two books the same.
  String words(String x) => _letters(cleanTitle(x).replaceAll(RegExp(r'\d+'), ' '));
  List<String> partsOf(String x) =>
      cleanTitle(x).split(_segmentSplit).map(words).where((p) => p.isNotEmpty).toList();
  final wa = words(a), wb = words(b);
  var best = _wordOverlap(wa, wb);
  for (final p in partsOf(b)) {
    best = [best, _wordOverlap(wa, p)].reduce((x, y) => x > y ? x : y);
  }
  for (final p in partsOf(a)) {
    best = [best, _wordOverlap(wb, p)].reduce((x, y) => x > y ? x : y);
  }
  return best < 0.6;
}

/// Shared words / all words (0..1).
double _wordOverlap(String a, String b) {
  final x = a.split(' ').where((w) => w.isNotEmpty).toSet();
  final y = b.split(' ').where((w) => w.isNotEmpty).toSet();
  if (x.isEmpty || y.isEmpty) return 0;
  return x.intersection(y).length / x.union(y).length;
}

final _partMarker = RegExp(
  r'\b(?:part|pt|book|bk|volume|vol|disc|disk|cd|episode|ep)\.?\s*#?\s*(\d+)\b|\b(\d+)\s+of\s+\d+\b',
  caseSensitive: false,
);

/// The part or book number in a title: "Callista Trilogy - Book 2" -> 2,
/// "Elantris (1 of 3)" -> 1. Null if there isn't one.
int? partNumber(String title) {
  final m = _partMarker.firstMatch(title);
  if (m == null) return null;
  return int.tryParse(m.group(1) ?? m.group(2) ?? '');
}

/// Why two books look like the same book, and how sure, or null if they
/// don't.
({String confidence, String reason})? comparePair(DupBook a, DupBook b) {
  // Folders naming different books outweigh matching details.
  if (differentFolders(a.path, b.path)) return null;
  // Different parts or books: "Book 1" / "Book 2", "(1 of 3)" / "(3 of 3)".
  // A number on only one of them is fine if the lengths match (a series
  // label like "Book 3"), but not if they don't (one part of a split book).
  final na = partNumber(a.title), nb = partNumber(b.title);
  if (na != null && nb != null && na != nb) return null;
  if ((na == null) != (nb == null) && !_similarLength(a.duration, b.duration)) return null;

  final sameAuthor = authorSimilarity(a.author, b.author) >= 0.85;
  final ta = coreTitle(a.title, a.author);
  final tb = coreTitle(b.title, b.author);
  if (ta.isEmpty || tb.isEmpty) return null;

  // 1. The same title.
  if (ta == tb) {
    if (sameAuthor) {
      // Very different lengths: often an abridged and an unabridged edition.
      return _similarLength(a.duration, b.duration, tolerance: 0.25)
          ? (confidence: 'High', reason: 'Same title and author')
          : (confidence: 'Medium', reason: 'Same title and author, different lengths (two editions?)');
    }
    // Often one copy has a folder name as its author ("Star Wars"); only
    // when the lengths agree closely.
    if (a.duration > 0 && b.duration > 0 && _similarLength(a.duration, b.duration, tolerance: 0.03)) {
      return (confidence: 'Medium', reason: 'Same title and length, different author');
    }
    return null;
  }

  // 2. Same series and the same number in it.
  if (sameAuthor) {
    final pa = parseSeries(a.series).where((p) => p.sequence.isNotEmpty);
    final pb = parseSeries(b.series).where((p) => p.sequence.isNotEmpty);
    for (final x in pa) {
      for (final y in pb) {
        if (_letters(x.name) == _letters(y.name) && sameSequence(x.sequence, y.sequence)) {
          final close = _similarLength(a.duration, b.duration);
          return (
            confidence: close ? 'High' : 'Medium',
            reason: 'Both ${x.name} #${x.sequence}${close ? '' : ' (different lengths)'}',
          );
        }
      }
    }
  }

  // 3. One title is part of the other: "The Two Week Curse" and
  //    "The Two Week Curse: A LitRPG Adventure", or a folder-style title
  //    ending in the other's title. Only with the same author and similar
  //    lengths ("Dune" and "Dune Messiah" never match: no colon or dash).
  if (sameAuthor && _similarLength(a.duration, b.duration)) {
    final sa = _segments(a.title);
    final sb = _segments(b.title);
    final aInB = sb.isNotEmpty && (sb.first == ta || sb.last == ta);
    final bInA = sa.isNotEmpty && (sa.first == tb || sa.last == tb);
    if (aInB || bInA) return (confidence: 'Medium', reason: 'One title includes the other');
  }
  return null;
}

/// Groups of books that look like the same book. [ignored] holds pairs you
/// said aren't duplicates, as [pairKey].
List<DuplicateGroup> findDuplicates(List<DupBook> books, {Set<String> ignored = const {}}) {
  // Only compare books that could match: sharing a first title word (of the
  // whole title or one of its parts) or a series number.
  final buckets = <String, List<int>>{};
  for (var i = 0; i < books.length; i++) {
    final b = books[i];
    final keys = <String>{};
    final core = coreTitle(b.title, b.author);
    if (core.isNotEmpty) keys.add('t:${_firstWord(core)}');
    for (final s in _segments(b.title)) {
      keys.add('t:${_firstWord(s)}');
    }
    for (final p in parseSeries(b.series)) {
      if (p.sequence.isNotEmpty) keys.add('s:${_letters(p.name)}#${double.tryParse(p.sequence) ?? p.sequence}');
    }
    for (final k in keys) {
      buckets.putIfAbsent(k, () => []).add(i);
    }
  }

  // Every matching pair, then join pairs that share a book into groups.
  final pairs = <(int, int, ({String confidence, String reason}))>[];
  final checked = <int>{};
  for (final list in buckets.values) {
    for (var x = 0; x < list.length; x++) {
      for (var y = x + 1; y < list.length; y++) {
        final i = list[x] < list[y] ? list[x] : list[y];
        final j = list[x] < list[y] ? list[y] : list[x];
        if (!checked.add(i * books.length + j)) continue;
        if (ignored.contains(pairKey(books[i].id, books[j].id))) continue;
        final r = comparePair(books[i], books[j]);
        if (r != null) pairs.add((i, j, r));
      }
    }
  }

  final parent = List<int>.generate(books.length, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  for (final (i, j, _) in pairs) {
    parent[find(j)] = find(i);
  }

  final members = <int, List<int>>{};
  for (final (i, _, _) in pairs) {
    members.putIfAbsent(find(i), () => []);
  }
  for (var i = 0; i < books.length; i++) {
    members[find(i)]?.add(i);
  }

  final out = <DuplicateGroup>[];
  for (final e in members.entries) {
    final verdicts = [for (final (i, _, r) in pairs) if (find(i) == e.key) r];
    final v = verdicts.firstWhere((r) => r.confidence == 'High', orElse: () => verdicts.first);
    out.add(DuplicateGroup(ids: [for (final i in e.value) books[i].id], confidence: v.confidence, reason: v.reason));
  }
  out.sort((a, b) => a.confidence == b.confidence ? 0 : (a.confidence == 'High' ? -1 : 1));
  return out;
}

/// A remembered "these aren't duplicates", the same whichever order.
String pairKey(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
