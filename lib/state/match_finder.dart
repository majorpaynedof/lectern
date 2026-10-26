import '../api/abs_api.dart';
import '../models.dart';
import '../title_tools.dart';

/// A search result that might be the right book, with why it was found and
/// how close it looks (0..1).
class PossibleMatch {
  const PossibleMatch(this.result, this.reason, this.score);
  final MatchResult result;
  final String reason;
  final double score;

  /// "Close match" / "Possible match", for the label on each result.
  String get closeness => score >= 0.8 ? 'Close match' : (score >= 0.55 ? 'Possible match' : 'Loose match');
}

/// Searches again with a cleaned-up title and author when the exact title
/// finds nothing. Nothing is changed: this only suggests books.
///
/// Tries, in this order:
///  1. cleaned-up versions of the title (codes, brackets, "Book 3" removed,
///     the part before or after a colon) with the main author only;
///  2. the original title with the author cleaned up, if that's different;
///  3. the author with just the first words of the title, for books whose
///     title is very different online.
Future<List<PossibleMatch>> findPossibleMatches(
  AbsApi api, {
  required String provider,
  required String title,
  required String author,
  String? itemId,
}) async {
  final mainAuthor = cleanAuthor(author);
  final searches = <(String, String, String)>[
    for (final v in titleVariants(title).take(3)) (v, mainAuthor, 'Title cleaned up: "$v"'),
    if (mainAuthor.isNotEmpty && mainAuthor.toLowerCase() != author.trim().toLowerCase())
      (title.trim(), mainAuthor, 'Author cleaned up: "$mainAuthor"'),
    if (mainAuthor.isNotEmpty && shortTitle(title).isNotEmpty)
      (shortTitle(title), mainAuthor, 'Same author, similar title'),
  ];

  final batches = await Future.wait([
    for (final (t, a, _) in searches)
      api
          .searchBooks(provider: provider, title: t, author: a, itemId: itemId)
          .catchError((Object _) => <MatchResult>[]),
  ]);

  final seen = <String>{};
  final found = <PossibleMatch>[];
  for (var i = 0; i < searches.length; i++) {
    for (final r in batches[i]) {
      final key = r.asin.isNotEmpty ? r.asin : '${r.title.toLowerCase()}|${r.author.toLowerCase()}';
      if (!seen.add(key)) continue;
      final t = titleSimilarity(title, r.title);
      final score = author.trim().isEmpty ? t : 0.7 * t + 0.3 * authorSimilarity(author, r.author);
      if (score < 0.35) continue;
      found.add(PossibleMatch(r, searches[i].$3, score));
    }
  }
  found.sort((a, b) => b.score.compareTo(a.score));
  return found.take(15).toList();
}

/// The best online match for a book that has a series, for the Series
/// Finder. Returns null when nothing close enough has a series.
Future<PossibleMatch?> findSeriesMatch(
  AbsApi api, {
  required String provider,
  required String title,
  required String author,
  String? itemId,
}) async {
  final mainAuthor = cleanAuthor(author);
  final tries = <String>[cleanTitle(title), ...titleVariants(title).take(2)];
  final seen = <String>{};
  PossibleMatch? best;
  for (final t in tries) {
    if (!seen.add(t.toLowerCase())) continue;
    List<MatchResult> results;
    try {
      results = await api.searchBooks(provider: provider, title: t, author: mainAuthor, itemId: itemId);
    } catch (_) {
      continue;
    }
    for (final r in results) {
      if (r.series.isEmpty) continue;
      final ts = titleSimilarity(title, r.title);
      final au = mainAuthor.isEmpty ? 1.0 : authorSimilarity(author, r.author);
      if (ts < 0.6 || au < 0.5) continue; // not the same book
      final score = 0.75 * ts + 0.25 * au;
      if (best == null || score > best.score) best = PossibleMatch(r, 'Online match', score);
    }
    if (best != null && best.score >= 0.9) break; // good enough, no more searches
  }
  return best;
}
