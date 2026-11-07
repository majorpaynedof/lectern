/// Spots author names that are really folder names or "Last, First" and
/// suggests the plain name, e.g. "Clancy, Tom - Op Center 01" -> "Tom Clancy".
/// Used by Tidy author names (review first); nothing here changes anything.
library;

class AuthorTidy {
  const AuthorTidy({required this.name, required this.reason, this.mergeInto, this.possibleDuplicate = false});

  /// Same name apart from a middle initial: probably, not certainly, the
  /// same person, so it isn't pre-ticked.
  final bool possibleDuplicate;

  /// The suggested name.
  final String name;

  /// Why, in plain words, for the review card.
  final String reason;

  /// The exact name of an author that already exists with this name. Renaming
  /// to it merges the two (their books move to that author).
  final String? mergeInto;

  /// High when it would merge into an author you already have: the name is
  /// confirmed by your own library. Otherwise Medium.
  String get confidence => (mergeInto != null && !possibleDuplicate) ? 'High' : 'Medium';
}

final _dash = RegExp(r'\s+[-–—]\s+');

/// Company words, "The ..." and name suffixes: never a first or last name.
final _companyOrSuffix = RegExp(
  r'^(the|inc\.?|llc|ltd\.?|limited|co\.?|corp\.?|corporation|company|gmbh|press|publishing|'
  r'publishers|books|media|studios?|productions?|group|collective|jr\.?|sr\.?|ii|iii|iv|phd|md)\b|'
  r'\b(inc\.?|llc|ltd\.?|press|publishing|publishers|books|media|studios?|productions?|group|collective)$',
  caseSensitive: false,
);
final _spaces = RegExp(r'\s+');

/// Letters (any language), initials, apostrophes and hyphens; 1 to 4 words.
/// No digits, no "&", no brackets.
bool _nameLike(String s, {int maxWords = 4}) {
  final t = s.trim();
  if (t.isEmpty || RegExp(r'[0-9&()\[\]/\\+]').hasMatch(t)) return false;
  if (RegExp(r'\band\b', caseSensitive: false).hasMatch(t)) return false;
  final words = t.split(_spaces);
  return words.length <= maxWords && words.every((w) => RegExp(r"^[\p{L}.'’\-]+$", unicode: true).hasMatch(w));
}

String _key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}]+', unicode: true), '');

/// A tidier name for [name], or null if it looks fine (or isn't safe to
/// guess, such as two people in one entry). [others] are the other author
/// names in the library, used to spot an existing author to merge into.
AuthorTidy? suggestAuthorName(String name, Iterable<String> others) {
  final original = name.trim().replaceAll(_spaces, ' ');
  final parts = original.split(_dash);
  final base = parts.first.trim();
  final extra = parts.length > 1;

  String? candidate;
  String reason;
  final commas = ','.allMatches(base).length;
  if (commas == 1) {
    final last = base.split(',')[0].trim();
    final first = base.split(',')[1].trim();
    if (!_nameLike(last, maxWords: 3) || !_nameLike(first, maxWords: 3)) return null;
    // "The DevOps Collective, Inc." and "Smith, Jr." aren't "Last, First".
    if (_companyOrSuffix.hasMatch(first) || _companyOrSuffix.hasMatch(last)) return null;
    candidate = '$first $last';
    reason = extra ? 'Last name first, with extra text after it' : 'Last name first';
  } else if (commas == 0 && extra && _nameLike(base)) {
    candidate = base;
    reason = 'Extra text after the name';
  } else {
    return null;
  }

  if (candidate == original) return null;

  // An author you already have with this name (ignoring case, dots and
  // spaces, so "J.R.R. Tolkien" finds "J. R. R. Tolkien").
  final want = _key(candidate);
  String? existing;
  for (final o in others) {
    if (o.trim() != original && _key(o) == want) {
      existing = o.trim();
      break;
    }
  }
  return AuthorTidy(name: existing ?? candidate, reason: reason, mergeInto: existing);
}

/// The name without punctuation and single-letter initials:
/// "Steve R. Pieczenik" -> "steve pieczenik". Null if fewer than two words
/// would be left ("J. Smith"), since a surname alone isn't enough to say two
/// authors are the same person.
String? _withoutInitials(String name) {
  final words = name
      .toLowerCase()
      .replaceAll(RegExp(r"[^\p{L}\s'’-]+", unicode: true), ' ')
      .split(_spaces)
      .where((w) => w.length > 1)
      .toList();
  return words.length < 2 ? null : words.join(' ');
}

/// Another author who is probably the same person, differing only by a
/// middle initial ("Steve R. Pieczenik" and "Steve Pieczenik"). Suggested
/// only on the entry with fewer books, to merge into the one with more (on a
/// tie, into the one with the initial). [library] maps every author name to
/// its number of books.
AuthorTidy? suggestDuplicate(String name, Map<String, int> library) {
  final me = name.trim();
  final key = _withoutInitials(me);
  if (key == null) return null;
  final mine = library[me] ?? 0;
  for (final e in library.entries) {
    final other = e.key.trim();
    if (other == me || _withoutInitials(other) != key) continue;
    if (other.toLowerCase().replaceAll(' ', '') == me.toLowerCase().replaceAll(' ', '')) continue; // spacing only
    final theirs = e.value;
    final keepOther = theirs > mine || (theirs == mine && other.length > me.length);
    if (!keepOther) continue;
    return AuthorTidy(
      name: other,
      reason: 'Same name apart from a middle initial',
      mergeInto: other,
      possibleDuplicate: true,
    );
  }
  return null;
}
