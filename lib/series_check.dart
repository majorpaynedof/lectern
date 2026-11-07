/// Rules for "Check series": compares the series a book is in with what was
/// found online, and spots two books with the same number in one series.
/// Nothing here changes anything; the screen asks first.
library;

import 'title_tools.dart';

/// A book's place in one series, e.g. ("Bobiverse", "3").
typedef SeriesPlace = ({String name, String sequence});

/// Reads the server's series text, "Bobiverse #3, Other Series #1".
List<SeriesPlace> parseSeries(String text) {
  final out = <SeriesPlace>[];
  for (final part in text.split(',')) {
    final t = part.trim();
    if (t.isEmpty) continue;
    final m = RegExp(r'^(.*?)\s+#\s*([^\s#]+)$').firstMatch(t);
    out.add(m == null ? (name: t, sequence: '') : (name: m.group(1)!.trim(), sequence: m.group(2)!.trim()));
  }
  return out;
}

/// "1", "01" and "1.0" are the same number; "1.5" isn't.
bool sameSequence(String a, String b) {
  final x = double.tryParse(a.trim());
  final y = double.tryParse(b.trim());
  if (x != null && y != null) return x == y;
  return a.trim().toLowerCase() == b.trim().toLowerCase();
}

bool _sameSeries(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase() || titleSimilarity(a, b) >= 0.92;

enum SeriesIssue { numberMissing, numberDifferent }

class SeriesFix {
  const SeriesFix({required this.issue, required this.series, required this.from, required this.to});
  final SeriesIssue issue;
  final String series; // your library's name for the series
  final String from; // current number ('' if none)
  final String to; // number found online

  String get describe => switch (issue) {
        SeriesIssue.numberMissing => '$series: add number #$to',
        SeriesIssue.numberDifferent => '$series: #$from → #$to',
      };
}

/// What to change for one book, comparing [current] (from your library) with
/// [found] (online). Only series you already have the book in are checked.
List<SeriesFix> checkBookSeries(List<SeriesPlace> current, List<SeriesPlace> found) {
  final fixes = <SeriesFix>[];
  for (final c in current) {
    for (final f in found) {
      if (!_sameSeries(c.name, f.name) || f.sequence.trim().isEmpty) continue;
      if (c.sequence.trim().isEmpty) {
        fixes.add(SeriesFix(issue: SeriesIssue.numberMissing, series: c.name, from: '', to: f.sequence.trim()));
      } else if (!sameSequence(c.sequence, f.sequence)) {
        fixes.add(SeriesFix(issue: SeriesIssue.numberDifferent, series: c.name, from: c.sequence, to: f.sequence.trim()));
      }
      break;
    }
  }
  return fixes;
}

/// Books sharing a number in the same series: series name -> number -> ids.
/// Only groups with two or more books are returned.
Map<String, Map<String, List<String>>> findDuplicateNumbers(Map<String, List<SeriesPlace>> books) {
  final bySeries = <String, Map<String, List<String>>>{};
  final names = <String, String>{}; // lower-case -> display name
  books.forEach((id, places) {
    for (final p in places) {
      if (p.sequence.trim().isEmpty) continue;
      final display = names.putIfAbsent(p.name.trim().toLowerCase(), () => p.name.trim());
      final seqKey = double.tryParse(p.sequence.trim())?.toString() ?? p.sequence.trim().toLowerCase();
      bySeries.putIfAbsent(display, () => {}).putIfAbsent(seqKey, () => []).add(id);
    }
  });
  return {
    for (final e in bySeries.entries)
      if (e.value.values.any((ids) => ids.length > 1))
        e.key: {for (final s in e.value.entries) if (s.value.length > 1) s.key: s.value},
  };
}
