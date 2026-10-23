import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

class AbsApiException implements Exception {
  final int? status;
  final String message;
  AbsApiException(this.status, this.message);

  @override
  String toString() => status == null ? message : '$message (HTTP $status)';
}

typedef TokensChanged = void Function(String accessToken, String? refreshToken);

/// Thin wrapper around the Audiobookshelf REST API.
class AbsApi {
  AbsApi({
    required String baseUrl,
    required this.token,
    this.refreshToken,
    this.onTokensChanged,
    http.Client? client,
  })  : baseUrl = normalizeBase(baseUrl),
        _client = client ?? http.Client();

  final String baseUrl;
  String token;
  String? refreshToken;
  TokensChanged? onTokensChanged;
  final http.Client _client;

  static const clientName = 'Lectern';
  static const clientVersion = '0.1.0';

  static String normalizeBase(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Map<String, String> get authHeaders => {'Authorization': 'Bearer $token'};

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  // ---------------------------------------------------------------- auth

  /// Logs in with a username and password.
  /// Returns (accessToken, refreshToken). Newer servers (2.26+) return
  /// short-lived access tokens plus a refresh token; older ones return a
  /// single long-lived `token`.
  static Future<(String, String?)> login(String baseUrl, String username, String password) async {
    final base = normalizeBase(baseUrl);
    final http.Response res;
    try {
      res = await http.post(
        Uri.parse('$base/login'),
        headers: {'Content-Type': 'application/json', 'x-return-tokens': 'true'},
        body: jsonEncode({'username': username, 'password': password}),
      );
    } catch (e) {
      throw AbsApiException(null, 'Could not reach the server. Check the address.');
    }
    if (res.statusCode == 401) throw AbsApiException(401, 'Wrong username or password');
    final data = _decode(res);
    final user = (data is Map ? data['user'] : null);
    if (user is! Map) throw AbsApiException(null, 'Unexpected response from server');
    final access = (user['accessToken'] ?? user['token'])?.toString();
    if (access == null || access.isEmpty) {
      throw AbsApiException(null, 'Server did not return a token');
    }
    return (access, user['refreshToken']?.toString());
  }

  /// The refresh in progress, shared by every request that hit a 401 at the
  /// same time. The server replaces the refresh token each time it's used,
  /// so two refreshes racing with the same token would leave one of them
  /// (and possibly the saved sign-in) holding a token that's no longer valid.
  Future<bool>? _refreshing;

  Future<bool> _refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final rt = refreshToken;
    if (rt == null) return false;
    try {
      final res = await _client.post(
        _uri('/auth/refresh'),
        headers: {'x-refresh-token': rt, 'x-return-tokens': 'true'},
      );
      if (res.statusCode != 200) return false;
      final user = (jsonDecode(res.body) as Map)['user'] as Map;
      token = user['accessToken'].toString();
      refreshToken = user['refreshToken']?.toString() ?? rt;
      onTokensChanged?.call(token, refreshToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------ plumbing

  Future<dynamic> _send(
    Future<http.Response> Function() request, {
    bool retried = false,
    bool safeToRepeat = false,
  }) async {
    http.Response res;
    final sentWith = token;
    try {
      // Fail fast when the server can't be reached, so offline mode kicks in.
      res = await request().timeout(const Duration(seconds: 12));
    } on http.ClientException {
      // Usually a reused connection the server had already closed. A fresh
      // attempt almost always works; only repeat requests that are safe to.
      if (!safeToRepeat) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      res = await request().timeout(const Duration(seconds: 12));
    }
    if (res.statusCode == 401 && !retried) {
      // Another request may already have refreshed the token while this one
      // was in flight: then just try again with the new one.
      if (token != sentWith || await _refresh()) {
        return _send(request, retried: true, safeToRepeat: safeToRepeat);
      }
    }
    return _decode(res);
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) =>
      _send(() => _client.get(_uri(path, query), headers: authHeaders), safeToRepeat: true);

  Future<dynamic> _post(String path, [Object? body]) => _send(() => _client.post(
        _uri(path),
        headers: {...authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode(body ?? {}),
      ));

  Future<dynamic> _patch(String path, [Object? body]) => _send(() => _client.patch(
        _uri(path),
        headers: {...authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode(body ?? {}),
      ));

  static dynamic _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AbsApiException(res.statusCode, res.body.isEmpty ? 'Request failed' : res.body);
    }
    if (res.body.isEmpty) return null;
    try {
      return jsonDecode(res.body);
    } catch (_) {
      return res.body;
    }
  }

  // ------------------------------------------------------------- library

  Future<Map<String, dynamic>> me() async =>
      ((await _get('/api/me')) as Map).cast<String, dynamic>();

  Future<List<Library>> libraries() async {
    final d = await _get('/api/libraries') as Map;
    return (d['libraries'] as List)
        .map((e) => Library.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Home-page shelves that are only about e-books; Lectern only plays audio.
  static const _ebookShelves = {'continue-reading', 'read-again'};

  Future<List<Shelf>> personalized(String libraryId) async {
    final d = await _get('/api/libraries/$libraryId/personalized', {'limit': '14'});
    return (d as List)
        .map((e) => Shelf.fromJson((e as Map).cast<String, dynamic>()))
        .where((s) => s.type == 'book' && !_ebookShelves.contains(s.id))
        .map((s) => Shelf(
              id: s.id,
              label: s.label,
              type: s.type,
              items: s.items.where((b) => b.hasAudio).toList(),
            ))
        .where((s) => s.items.isNotEmpty)
        .toList();
  }

  Future<List<BookSummary>> items(
    String libraryId, {
    int page = 0,
    int limit = 60,
    String sort = 'media.metadata.title',
    bool desc = false,
  }) async {
    final d = await _get('/api/libraries/$libraryId/items', {
      'limit': '$limit',
      'page': '$page',
      'sort': sort,
      'desc': desc ? '1' : '0',
      'minified': '1',
    }) as Map;
    return (d['results'] as List)
        .map((e) => BookSummary.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<BookSummary>> search(String libraryId, String query) async {
    final d = await _get('/api/libraries/$libraryId/search', {'q': query, 'limit': '40'}) as Map;
    final books = (d['book'] as List?) ?? const [];
    return [
      for (final b in books)
        if (b is Map && b['libraryItem'] is Map)
          BookSummary.fromJson((b['libraryItem'] as Map).cast<String, dynamic>()),
    ].where((b) => b.hasAudio).toList();
  }

  Future<BookDetail> item(String id) async {
    final d = await _get('/api/items/$id', {'expanded': '1', 'include': 'progress'}) as Map;
    return BookDetail.fromJson(d.cast<String, dynamic>());
  }

  // --------------------------------------------------- series & authors

  /// One page of series. `raw` is how many the server sent before e-book-only
  /// series were dropped, for knowing whether more pages exist.
  Future<({List<SeriesSummary> items, int raw})> series(
    String libraryId, {
    int page = 0,
    int limit = 40,
    String sort = 'name',
    bool desc = false,
  }) async {
    final d = await _get('/api/libraries/$libraryId/series', {
      'limit': '$limit',
      'page': '$page',
      'sort': sort,
      'desc': desc ? '1' : '0',
    }) as Map;
    final results = (d['results'] as List?) ?? const [];
    return (
      items: results
          .map((e) => SeriesSummary.fromJson((e as Map).cast<String, dynamic>()))
          .where((s) => s.entries.isNotEmpty)
          .toList(),
      raw: results.length,
    );
  }

  /// Every book in one series, in reading order.
  Future<List<SeriesEntry>> seriesBooks(String libraryId, String seriesId) async {
    final filter = 'series.${base64Encode(utf8.encode(seriesId))}';
    final d = await _get('/api/libraries/$libraryId/items', {
      'filter': filter,
      'limit': '500',
      'page': '0',
    }) as Map;
    return SeriesSummary.entriesFromItems(seriesId, (d['results'] as List?) ?? const []);
  }

  Future<List<AuthorSummary>> authors(String libraryId) async {
    final d = await _get('/api/libraries/$libraryId/authors') as Map;
    final list = ((d['authors'] as List?) ?? const [])
        .map((e) => AuthorSummary.fromJson((e as Map).cast<String, dynamic>()))
        .where((a) => a.numBooks > 0)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<AuthorDetail> author(String authorId) async {
    final d = await _get('/api/authors/$authorId', {'include': 'items,series'}) as Map;
    return AuthorDetail.fromJson(d.cast<String, dynamic>());
  }

  /// The full item as the server sends it (used for downloads).
  Future<Map<String, dynamic>> itemRaw(String id) async =>
      ((await _get('/api/items/$id', {'expanded': '1'})) as Map).cast<String, dynamic>();

  /// The server-side download client, shared so downloads reuse connections.
  http.Client get client => _client;

  Future<Map<String, dynamic>> listeningStats() async =>
      ((await _get('/api/me/listening-stats')) as Map).cast<String, dynamic>();

  /// Uploads listening done while offline (counts towards stats).
  Future<void> syncLocalSession(Map<String, dynamic> session) async {
    await _post('/api/session/local', session);
  }

  Future<void> updateProgress(String itemId, {required double currentTime, required double duration}) async {
    await _patch('/api/me/progress/$itemId', {
      'currentTime': currentTime,
      'duration': duration,
      'progress': duration > 0 ? (currentTime / duration).clamp(0.0, 1.0) : 0,
    });
  }

  Uri authorImageUri(String authorId, {int width = 300}) =>
      _uri('/api/authors/$authorId/image', {'width': '$width'});

  // ------------------------------------------------------------ editing

  /// Saves book details to the server. [metadata] uses Audiobookshelf's
  /// field names (title, authors: [{name}], series: [{name, sequence}], ...).
  /// If [coverUrl] is given the server downloads it as the new cover.
  Future<void> updateBook(String itemId, Map<String, dynamic> metadata, {String? coverUrl}) async {
    await _patch('/api/items/$itemId/media', {
      'metadata': metadata,
      if (coverUrl != null && coverUrl.isNotEmpty) 'url': coverUrl,
    });
  }

  Future<List<MetadataProvider>> bookProviders() async {
    try {
      final d = await _get('/api/search/providers') as Map;
      final books = (d['providers'] as Map?)?['books'];
      if (books is List && books.isNotEmpty) {
        return [
          for (final b in books)
            if (b is Map) MetadataProvider(b['value'].toString(), (b['text'] ?? b['value']).toString()),
        ];
      }
    } catch (_) {}
    return MetadataProvider.defaults;
  }

  Future<List<MatchResult>> searchBooks({
    required String provider,
    required String title,
    String author = '',
    String? itemId,
  }) async {
    final d = await _get('/api/search/books', {
      'provider': provider,
      'title': title,
      'author': author,
      if (itemId != null) 'id': itemId,
    });
    final list = d is List ? d : (d is Map && d['results'] is List ? d['results'] as List : const []);
    return [for (final r in list) if (r is Map) MatchResult.fromJson(r.cast<String, dynamic>())];
  }

  /// Quick-match one book. Returns 'updated', 'unchanged' or 'notfound'.
  Future<String> matchBook(
    String itemId, {
    required String provider,
    bool overrideCover = false,
    bool overrideDetails = false,
  }) async {
    final d = await _post('/api/items/$itemId/match', {
      'provider': provider,
      'overrideCover': overrideCover,
      'overrideDetails': overrideDetails,
    });
    if (d is Map && d['warning'] != null) return 'notfound';
    if (d is Map && d['updated'] == true) return 'updated';
    return 'unchanged';
  }

  /// Every audiobook in the library (pages through the whole list).
  Future<List<BookSummary>> allBooks(String libraryId) async {
    final all = <BookSummary>[];
    for (var page = 0;; page++) {
      final batch = await items(libraryId, page: page, limit: 200);
      all.addAll(batch.where((b) => b.hasAudio));
      if (batch.length < 200) break;
    }
    return all;
  }

  Future<void> updateAuthor(String authorId, {String? name, String? description}) async {
    await _patch('/api/authors/$authorId', {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
    });
  }

  /// Looks the author up online and fills in photo and bio. Returns false
  /// if no match was found.
  Future<bool> matchAuthor(String authorId, String query) async {
    try {
      await _post('/api/authors/$authorId/match', {'q': query});
      return true;
    } on AbsApiException catch (e) {
      if (e.status == 404) return false;
      rethrow;
    }
  }

  Uri coverUri(String itemId, {int width = 400}) =>
      _uri('/api/items/$itemId/cover', {'width': '$width'});

  // ------------------------------------------------------------ playback

  /// Starts a listening session. Normally the original files are streamed
  /// as-is; with [transcode] the server converts the book to a standard
  /// stream instead (for audio our player can't decode).
  Future<PlaybackSession> startPlayback(String itemId, String deviceId,
      {bool transcode = false}) async {
    final d = await _post('/api/items/$itemId/play', {
      'deviceInfo': {
        'clientName': clientName,
        'clientVersion': clientVersion,
        'deviceId': deviceId,
      },
      'forceDirectPlay': !transcode,
      'forceTranscode': transcode,
      'supportedMimeTypes': transcode ? <String>[] : [
        'audio/flac',
        'audio/mpeg',
        'audio/mp4',
        'audio/ogg',
        'audio/aac',
        'audio/webm',
        'audio/x-m4b',
      ],
      'mediaPlayer': 'media_kit',
    }) as Map;
    return PlaybackSession.fromJson(d.cast<String, dynamic>());
  }

  Uri trackUri(String contentUrl) {
    final uri = Uri.parse('$baseUrl$contentUrl');
    // Converted streams (/hls/...) also get the token in the address, in case
    // the player doesn't send our login header with every piece it fetches.
    if (!contentUrl.startsWith('/hls/')) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, 'token': token});
  }

  Future<void> syncSession(
    String sessionId, {
    required double currentTime,
    required double timeListened,
    required double duration,
  }) async {
    await _post('/api/session/$sessionId/sync', {
      'currentTime': currentTime,
      'timeListened': timeListened,
      'duration': duration,
    });
  }

  Future<void> closeSession(
    String sessionId, {
    required double currentTime,
    required double timeListened,
    required double duration,
  }) async {
    await _post('/api/session/$sessionId/close', {
      'currentTime': currentTime,
      'timeListened': timeListened,
      'duration': duration,
    });
  }
}
