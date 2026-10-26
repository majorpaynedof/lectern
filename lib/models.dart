// Plain data classes for the parts of the Audiobookshelf API we use.

double _d(dynamic v) => v is num ? v.toDouble() : 0.0;

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

List<dynamic> _list(dynamic v) => v is List ? v : const [];

String _authorOf(Map<String, dynamic> md) {
  final name = md['authorName'];
  if (name is String && name.isNotEmpty) return name;
  final names = _list(md['authors'])
      .map((a) => _map(a)['name']?.toString() ?? '')
      .where((n) => n.isNotEmpty);
  return names.isEmpty ? 'Unknown author' : names.join(', ');
}

class Library {
  final String id;
  final String name;
  final String mediaType;

  const Library({required this.id, required this.name, required this.mediaType});

  factory Library.fromJson(Map<String, dynamic> j) => Library(
        id: j['id'].toString(),
        name: (j['name'] ?? 'Library').toString(),
        mediaType: (j['mediaType'] ?? 'book').toString(),
      );
}

class BookSummary {
  final String id;
  final String title;
  final String author;
  final double duration;

  /// E-book-only items have no audio, so their duration is 0.
  bool get hasAudio => duration > 0;

  final bool hasCover;

  /// Series name(s) as the server shows them, e.g. "Bobiverse #3"; empty
  /// when the book isn't in a series.
  final String series;

  const BookSummary({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    this.hasCover = true,
    this.series = '',
  });

  factory BookSummary.fromJson(Map<String, dynamic> j) {
    final media = _map(j['media']);
    final md = _map(media['metadata']);
    return BookSummary(
      id: j['id'].toString(),
      title: (md['title'] ?? 'Untitled').toString(),
      author: _authorOf(md),
      duration: _d(media['duration']),
      hasCover: (media['coverPath'] ?? '').toString().isNotEmpty,
      series: _seriesNameOf(md),
    );
  }
}

String _seriesNameOf(Map<String, dynamic> md) {
  final name = (md['seriesName'] ?? '').toString().trim();
  if (name.isNotEmpty) return name;
  return seriesRefsOf(md).map((r) => r.name).where((n) => n.isNotEmpty).join(', ');
}

/// A row on the home screen ("Continue Listening", "Recently Added", ...).
class Shelf {
  final String id;
  final String label;
  final String type;
  final List<BookSummary> items;

  const Shelf({required this.id, required this.label, required this.type, required this.items});

  factory Shelf.fromJson(Map<String, dynamic> j) {
    final type = (j['type'] ?? '').toString();
    return Shelf(
      id: (j['id'] ?? '').toString(),
      label: (j['label'] ?? '').toString(),
      type: type,
      items: type == 'book'
          ? _list(j['entities']).map((e) => BookSummary.fromJson(_map(e))).toList()
          : const [],
    );
  }
}

class Chapter {
  final int id;
  final double start;
  final double end;
  final String title;

  const Chapter({required this.id, required this.start, required this.end, required this.title});

  factory Chapter.fromJson(Map<String, dynamic> j) => Chapter(
        id: (j['id'] as num?)?.toInt() ?? 0,
        start: _d(j['start']),
        end: _d(j['end']),
        title: (j['title'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'start': start, 'end': end, 'title': title};
}

class BookDetail {
  final String id;
  final String title;
  final String author;
  final String? narrator;
  final String? series;
  final String? year;
  final String subtitle;
  final List<String> narrators;
  final String publisher;
  final List<String> genres;
  final String description;
  final double duration;
  final List<Chapter> chapters;
  final double currentTime;
  final double progress; // 0..1
  final bool isFinished;
  final List<NamedRef> authorRefs; // for links to author pages
  final List<SeriesRef> seriesRefs; // for links to series pages

  const BookDetail({
    required this.id,
    required this.title,
    required this.author,
    required this.narrator,
    required this.series,
    required this.year,
    required this.description,
    required this.duration,
    required this.chapters,
    required this.currentTime,
    required this.progress,
    required this.isFinished,
    this.authorRefs = const [],
    this.seriesRefs = const [],
    this.subtitle = '',
    this.narrators = const [],
    this.publisher = '',
    this.genres = const [],
  });

  factory BookDetail.fromJson(Map<String, dynamic> j) {
    final media = _map(j['media']);
    final md = _map(media['metadata']);

    String? narrator = md['narratorName']?.toString();
    if (narrator == null || narrator.isEmpty) {
      final n = _list(md['narrators']).map((e) => e.toString()).where((e) => e.isNotEmpty);
      narrator = n.isEmpty ? null : n.join(', ');
    }

    String? series = md['seriesName']?.toString();
    if (series == null || series.isEmpty) {
      final s = _list(md['series']).map((e) {
        final m = _map(e);
        final seq = m['sequence']?.toString();
        return seq == null || seq.isEmpty ? '${m['name']}' : '${m['name']} #$seq';
      });
      series = s.isEmpty ? null : s.join(', ');
    }

    final prog = _map(j['userMediaProgress']);
    return BookDetail(
      id: j['id'].toString(),
      title: (md['title'] ?? 'Untitled').toString(),
      author: _authorOf(md),
      narrator: narrator,
      series: series,
      year: md['publishedYear']?.toString(),
      description: (md['description'] ?? '').toString(),
      duration: _d(media['duration']),
      chapters: _list(media['chapters']).map((c) => Chapter.fromJson(_map(c))).toList(),
      currentTime: _d(prog['currentTime']),
      progress: _d(prog['progress']),
      isFinished: prog['isFinished'] == true,
      authorRefs: _list(md['authors'])
          .map((a) => NamedRef.fromJson(_map(a)))
          .where((a) => a.id.isNotEmpty)
          .toList(),
      seriesRefs: seriesRefsOf(md),
      subtitle: (md['subtitle'] ?? '').toString(),
      narrators: _list(md['narrators']).map((e) => e.toString()).where((e) => e.isNotEmpty).toList(),
      publisher: (md['publisher'] ?? '').toString(),
      genres: _list(md['genres']).map((e) => e.toString()).where((e) => e.isNotEmpty).toList(),
    );
  }
}

class AudioTrack {
  final int index;
  final double startOffset;
  final double duration;
  final String contentUrl;

  const AudioTrack({
    required this.index,
    required this.startOffset,
    required this.duration,
    required this.contentUrl,
  });

  factory AudioTrack.fromJson(Map<String, dynamic> j) => AudioTrack(
        index: (j['index'] as num?)?.toInt() ?? 0,
        startOffset: _d(j['startOffset']),
        duration: _d(j['duration']),
        contentUrl: (j['contentUrl'] ?? '').toString(),
      );
}

/// What the server returns when you start playing an item.
class PlaybackSession {
  final String id;
  final String libraryItemId;
  final String title;
  final String author;
  final double duration;
  final double currentTime;
  final List<AudioTrack> tracks;
  final List<Chapter> chapters;

  const PlaybackSession({
    required this.id,
    required this.libraryItemId,
    required this.title,
    required this.author,
    required this.duration,
    required this.currentTime,
    required this.tracks,
    required this.chapters,
  });

  /// The same book and position under a new server session id (used when
  /// the server has forgotten the old session).
  PlaybackSession withId(String newId) => PlaybackSession(
        id: newId,
        libraryItemId: libraryItemId,
        title: title,
        author: author,
        duration: duration,
        currentTime: currentTime,
        tracks: tracks,
        chapters: chapters,
      );

  factory PlaybackSession.fromJson(Map<String, dynamic> j) {
    final tracks = _list(j['audioTracks']).map((t) => AudioTrack.fromJson(_map(t))).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return PlaybackSession(
      id: j['id'].toString(),
      libraryItemId: j['libraryItemId'].toString(),
      title: (j['displayTitle'] ?? 'Untitled').toString(),
      author: (j['displayAuthor'] ?? '').toString(),
      duration: _d(j['duration']),
      currentTime: _d(j['currentTime']),
      tracks: tracks,
      chapters: _list(j['chapters']).map((c) => Chapter.fromJson(_map(c))).toList(),
    );
  }

  /// Which audio file contains the given book-level timestamp.
  int trackIndexFor(double seconds) {
    var idx = 0;
    for (var i = 0; i < tracks.length; i++) {
      if (tracks[i].startOffset <= seconds) idx = i;
    }
    return idx;
  }
}


// ---------------------------------------------------------------- series

class NamedRef {
  final String id;
  final String name;
  const NamedRef(this.id, this.name);

  factory NamedRef.fromJson(Map<String, dynamic> j) =>
      NamedRef((j['id'] ?? '').toString(), (j['name'] ?? '').toString());
}

class SeriesRef {
  final String id;
  final String name;
  final String? sequence;
  const SeriesRef(this.id, this.name, this.sequence);
}

/// The series a book belongs to. Audiobookshelf sends either a list or a
/// single object depending on the endpoint.
List<SeriesRef> seriesRefsOf(Map<String, dynamic> metadata) {
  final raw = metadata['series'];
  final list = raw is List ? raw : (raw is Map ? [raw] : const []);
  return [
    for (final e in list)
      if (_map(e)['id'] != null)
        SeriesRef(
          _map(e)['id'].toString(),
          (_map(e)['name'] ?? '').toString(),
          _map(e)['sequence']?.toString(),
        ),
  ];
}

/// One book in a series, with its number in the series ("1", "2.5", ...).
class SeriesEntry {
  final BookSummary book;
  final String? sequence;
  const SeriesEntry(this.book, this.sequence);
}

class SeriesSummary {
  final String id;
  final String name;
  final List<SeriesEntry> entries; // in reading order, audio books only

  const SeriesSummary({required this.id, required this.name, required this.entries});

  List<BookSummary> get books => [for (final e in entries) e.book];
  double get totalDuration => entries.fold(0.0, (sum, e) => sum + e.book.duration);

  factory SeriesSummary.fromJson(Map<String, dynamic> j, {String? itemsKey}) {
    final id = (j['id'] ?? '').toString();
    final items = _list(j[itemsKey ?? 'books']).isNotEmpty ? _list(j[itemsKey ?? 'books']) : _list(j['items']);
    return SeriesSummary(
      id: id,
      name: (j['name'] ?? 'Series').toString(),
      entries: entriesFromItems(id, items),
    );
  }

  /// Turns raw library items into ordered series entries.
  static List<SeriesEntry> entriesFromItems(String seriesId, List<dynamic> items) {
    final out = <SeriesEntry>[];
    for (final raw in items) {
      final item = _map(raw);
      final book = BookSummary.fromJson(item);
      if (!book.hasAudio) continue;
      String? seq = item['seriesSequence']?.toString();
      if (seq == null) {
        final md = _map(_map(item['media'])['metadata']);
        for (final r in seriesRefsOf(md)) {
          if (r.id == seriesId) seq = r.sequence;
        }
      }
      out.add(SeriesEntry(book, (seq == null || seq.isEmpty) ? null : seq));
    }
    double order(SeriesEntry e) => double.tryParse(e.sequence ?? '') ?? double.infinity;
    out.sort((a, b) {
      final c = order(a).compareTo(order(b));
      return c != 0 ? c : a.book.title.compareTo(b.book.title);
    });
    return out;
  }
}

// --------------------------------------------------------------- authors

class AuthorSummary {
  final String id;
  final String name;
  final int numBooks;
  final bool hasImage;

  const AuthorSummary({required this.id, required this.name, required this.numBooks, required this.hasImage});

  factory AuthorSummary.fromJson(Map<String, dynamic> j) => AuthorSummary(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? 'Unknown').toString(),
        numBooks: (j['numBooks'] as num?)?.toInt() ?? _list(j['libraryItems']).length,
        hasImage: (j['imagePath'] ?? '').toString().isNotEmpty,
      );
}

class AuthorDetail {
  final AuthorSummary summary;
  final String description;
  final List<BookSummary> books;
  final List<SeriesSummary> series;

  const AuthorDetail({required this.summary, required this.description, required this.books, required this.series});

  factory AuthorDetail.fromJson(Map<String, dynamic> j) => AuthorDetail(
        summary: AuthorSummary.fromJson(j),
        description: (j['description'] ?? '').toString(),
        books: _list(j['libraryItems']).map((e) => BookSummary.fromJson(_map(e))).where((b) => b.hasAudio).toList()
          ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())),
        series: _list(j['series'])
            .map((e) => SeriesSummary.fromJson(_map(e), itemsKey: 'items'))
            .where((s) => s.entries.isNotEmpty)
            .toList(),
      );
}


// --------------------------------------------------------------- editing

/// A metadata source the server can search (Audible, Google Books, ...).
class MetadataProvider {
  final String value;
  final String label;
  const MetadataProvider(this.value, this.label);

  static const defaults = [
    MetadataProvider('audible', 'Audible (US)'),
    MetadataProvider('audible.uk', 'Audible (UK)'),
    MetadataProvider('google', 'Google Books'),
    MetadataProvider('openlibrary', 'Open Library'),
    MetadataProvider('itunes', 'iTunes'),
  ];
}

/// One search result when matching a book.
class MatchResult {
  final String title;
  final String subtitle;
  final String author;
  final String narrator;
  final String publisher;
  final String year;
  final String description;
  final String? coverUrl;
  final List<String> genres;
  final List<SeriesRef> series; // id is empty: only name + sequence
  final String asin;
  final String isbn;
  final double durationMinutes;

  const MatchResult({
    required this.title,
    required this.subtitle,
    required this.author,
    required this.narrator,
    required this.publisher,
    required this.year,
    required this.description,
    required this.coverUrl,
    required this.genres,
    required this.series,
    required this.asin,
    required this.isbn,
    required this.durationMinutes,
  });

  factory MatchResult.fromJson(Map<String, dynamic> j) {
    String str(String k) => (j[k] ?? '').toString().trim();
    final seriesRaw = j['series'];
    final series = <SeriesRef>[];
    if (seriesRaw is List) {
      for (final e in seriesRaw) {
        final m = _map(e);
        final name = (m['series'] ?? m['name'] ?? '').toString().trim();
        if (name.isNotEmpty) series.add(SeriesRef('', name, m['sequence']?.toString()));
      }
    } else if (seriesRaw is String && seriesRaw.trim().isNotEmpty) {
      series.add(SeriesRef('', seriesRaw.trim(), j['sequence']?.toString()));
    }
    final genres = j['genres'];
    final cover = str('cover');
    return MatchResult(
      title: str('title'),
      subtitle: str('subtitle'),
      author: str('author'),
      narrator: str('narrator'),
      publisher: str('publisher'),
      year: str('publishedYear'),
      description: str('description'),
      coverUrl: cover.isEmpty ? null : cover,
      genres: genres is List ? genres.map((e) => e.toString()).toList() : const [],
      series: series,
      asin: str('asin'),
      isbn: str('isbn'),
      durationMinutes: j['duration'] is num ? (j['duration'] as num).toDouble() : 0,
    );
  }
}
