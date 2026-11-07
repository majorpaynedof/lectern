import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/abs_api.dart';
import '../models.dart';
import '../sync/abs_progress.dart';
import '../sync/progress_keeper.dart';

/// A book saved on this computer for offline listening.
class DownloadedBook {
  DownloadedBook({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    required this.chapters,
    required this.tracks,
    required this.folder,
    required this.sizeBytes,
    required this.downloadedAt,
    this.coverFile,
    this.position = 0,
    this.serverPosition,
  });

  final String id;
  final String title;
  final String author;
  final double duration;
  final List<Chapter> chapters;
  final List<AudioTrack> tracks; // contentUrl = local file name
  final String folder;
  final String? coverFile;
  final int sizeBytes;
  final DateTime downloadedAt;
  double position; // last known position, for resuming offline

  /// The position the server last had for this book, as far as this PC
  /// knows. Offline listening is only sent if the server still has it
  /// (otherwise another device has listened since). Null if unknown.
  double? serverPosition;

  String pathOf(AudioTrack t) => '$folder${Platform.pathSeparator}${t.contentUrl}';
  String? get coverPath => coverFile == null ? null : '$folder${Platform.pathSeparator}$coverFile';

  String? pathForIndex(int index) {
    for (final t in tracks) {
      if (t.index == index) return pathOf(t);
    }
    return null;
  }

  /// A playback session built entirely from local files (used offline).
  PlaybackSession toSession() => PlaybackSession(
        id: 'play_local_${_randomId()}',
        libraryItemId: id,
        title: title,
        author: author,
        duration: duration,
        currentTime: position,
        tracks: tracks,
        chapters: chapters,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'duration': duration,
        'chapters': [for (final c in chapters) c.toJson()],
        'tracks': [
          for (final t in tracks)
            {'index': t.index, 'startOffset': t.startOffset, 'duration': t.duration, 'file': t.contentUrl},
        ],
        'cover': coverFile,
        'size': sizeBytes,
        'downloadedAt': downloadedAt.toIso8601String(),
        'position': position,
        if (serverPosition != null) 'serverPosition': serverPosition,
      };

  static DownloadedBook fromJson(Map<String, dynamic> j, String folder) => DownloadedBook(
        id: j['id'].toString(),
        title: (j['title'] ?? '').toString(),
        author: (j['author'] ?? '').toString(),
        duration: (j['duration'] as num?)?.toDouble() ?? 0,
        chapters: [
          for (final c in (j['chapters'] as List? ?? const []))
            Chapter.fromJson((c as Map).cast<String, dynamic>()),
        ],
        tracks: [
          for (final t in (j['tracks'] as List? ?? const []))
            AudioTrack(
              index: ((t as Map)['index'] as num).toInt(),
              startOffset: (t['startOffset'] as num?)?.toDouble() ?? 0,
              duration: (t['duration'] as num?)?.toDouble() ?? 0,
              contentUrl: t['file'].toString(),
            ),
        ]..sort((a, b) => a.index.compareTo(b.index)),
        folder: folder,
        coverFile: j['cover']?.toString(),
        sizeBytes: (j['size'] as num?)?.toInt() ?? 0,
        downloadedAt: DateTime.tryParse((j['downloadedAt'] ?? '').toString()) ?? DateTime.now(),
        position: (j['position'] as num?)?.toDouble() ?? 0,
        serverPosition: (j['serverPosition'] as num?)?.toDouble(),
      );
}

/// A download that is still in progress.
class DownloadTask {
  DownloadTask(this.id, this.title);
  final String id;
  final String title;
  double progress = 0; // 0..1
  bool cancelled = false;
  String? error;
}

String _randomId() {
  final r = Random.secure();
  return List.generate(12, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Downloads books, keeps track of what's on disk, and queues listening
/// done offline so it can be sent to the server later.
class DownloadManager extends ChangeNotifier {
  late Directory _root;
  bool ready = false;

  final Map<String, DownloadedBook> _books = {};
  final Map<String, DownloadTask> tasks = {};

  /// Offline listening sessions waiting to be uploaded, keyed by session id.
  final Map<String, Map<String, dynamic>> _pending = {};

  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  List<DownloadedBook> get books =>
      _books.values.toList()..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));

  DownloadedBook? book(String id) => _books[id];
  bool isDownloaded(String id) => _books.containsKey(id);
  int get totalBytes => _books.values.fold(0, (sum, b) => sum + b.sizeBytes);
  bool get hasPending => _pending.isNotEmpty;

  String? coverPath(String id) => _books[id]?.coverPath;

  String get folderPath => _root.path;

  Future<void> load() async {
    try {
      final support = await getApplicationSupportDirectory();
      _root = Directory('${support.path}${Platform.pathSeparator}downloads');
      await _root.create(recursive: true);

      await for (final entry in _root.list()) {
        if (entry is! Directory) continue;
        if (entry.path.endsWith('.part')) {
          // Left over from a download that was interrupted.
          try {
            await entry.delete(recursive: true);
          } catch (_) {}
          continue;
        }
        final manifest = File('${entry.path}${Platform.pathSeparator}manifest.json');
        if (!await manifest.exists()) continue;
        try {
          final j = jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
          final b = DownloadedBook.fromJson(j, entry.path);
          _books[b.id] = b;
        } catch (e) {
          debugPrint('Skipping broken download ${entry.path}: $e');
        }
      }

      final pending = File('${_root.path}${Platform.pathSeparator}pending.json');
      if (await pending.exists()) {
        final j = jsonDecode(await pending.readAsString());
        if (j is Map) {
          j.forEach((k, v) => _pending[k.toString()] = (v as Map).cast<String, dynamic>());
        }
      }
    } catch (e) {
      debugPrint('Could not load downloads: $e');
    }
    ready = true;
    notifyListeners();
  }

  // ------------------------------------------------------------ downloading

  Future<void> download(AbsApi api, String itemId) async {
    if (tasks.containsKey(itemId) || _books.containsKey(itemId)) return;
    final task = DownloadTask(itemId, '');
    tasks[itemId] = task;
    notifyListeners();

    final part = Directory('${_root.path}${Platform.pathSeparator}$itemId.part');
    try {
      final raw = await api.itemRaw(itemId);
      final media = (raw['media'] as Map?)?.cast<String, dynamic>() ?? const {};
      final summary = BookSummary.fromJson(raw);
      final rawTracks = (media['tracks'] as List?) ?? const [];
      if (rawTracks.isEmpty) throw StateError('This book has no audio files on the server.');

      if (await part.exists()) await part.delete(recursive: true);
      await part.create(recursive: true);

      // Total size, for the progress bar.
      var total = 0;
      for (final t in rawTracks) {
        final size = ((t as Map)['metadata'] as Map?)?['size'];
        if (size is num) total += size.toInt();
      }

      var received = 0;
      final tracks = <AudioTrack>[];
      for (final t in rawTracks) {
        if (task.cancelled) throw _Cancelled();
        final m = (t as Map).cast<String, dynamic>();
        final index = (m['index'] as num?)?.toInt() ?? tracks.length + 1;
        final meta = (m['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};
        var ext = (meta['ext'] ?? '').toString();
        if (ext.isEmpty) {
          final name = (meta['filename'] ?? '').toString();
          final dot = name.lastIndexOf('.');
          ext = dot >= 0 ? name.substring(dot) : '.mp3';
        }
        final fileName = 'track_${index.toString().padLeft(3, '0')}$ext';
        final file = File('${part.path}${Platform.pathSeparator}$fileName');

        final req = http.Request('GET', api.trackUri(m['contentUrl'].toString()))..headers.addAll(api.authHeaders);
        final res = await api.client.send(req);
        if (res.statusCode != 200) throw StateError('Server returned ${res.statusCode} for an audio file.');
        if (total == 0 && res.contentLength != null) total = res.contentLength! * rawTracks.length;

        final sink = file.openWrite();
        try {
          await for (final chunk in res.stream) {
            if (task.cancelled) throw _Cancelled();
            sink.add(chunk);
            received += chunk.length;
            task.progress = total > 0 ? (received / total).clamp(0.0, 0.99) : 0;
            _notifyThrottled();
          }
        } finally {
          await sink.close();
        }

        tracks.add(AudioTrack(
          index: index,
          startOffset: (m['startOffset'] as num?)?.toDouble() ?? 0,
          duration: (m['duration'] as num?)?.toDouble() ?? 0,
          contentUrl: fileName,
        ));
      }

      // Cover (optional).
      String? coverFile;
      try {
        final res = await api.client.get(api.coverUri(itemId, width: 800), headers: api.authHeaders);
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          coverFile = 'cover.img';
          await File('${part.path}${Platform.pathSeparator}$coverFile').writeAsBytes(res.bodyBytes);
          received += res.bodyBytes.length;
        }
      } catch (_) {}

      final book = DownloadedBook(
        id: itemId,
        title: summary.title,
        author: summary.author,
        duration: summary.duration,
        chapters: [
          for (final c in (media['chapters'] as List? ?? const []))
            Chapter.fromJson((c as Map).cast<String, dynamic>()),
        ],
        tracks: tracks,
        folder: '', // set below
        coverFile: coverFile,
        sizeBytes: received,
        downloadedAt: DateTime.now(),
      );

      // Move the finished folder into place, then write the manifest that
      // marks it as complete.
      final finalDir = Directory('${_root.path}${Platform.pathSeparator}$itemId');
      if (await finalDir.exists()) await finalDir.delete(recursive: true);
      await part.rename(finalDir.path);
      final saved = DownloadedBook.fromJson(book.toJson(), finalDir.path);
      await _writeManifest(saved);
      _books[itemId] = saved;
    } on _Cancelled {
      // Nothing to report.
    } catch (e) {
      task.error = e.toString();
      debugPrint('Download of $itemId failed: $e');
    } finally {
      tasks.remove(itemId);
      if (await part.exists()) {
        try {
          await part.delete(recursive: true);
        } catch (_) {}
      }
      notifyListeners();
    }
    if (task.error != null) throw StateError(task.error!);
  }

  void cancel(String itemId) {
    tasks[itemId]?.cancelled = true;
  }

  Future<void> remove(String itemId) async {
    final b = _books.remove(itemId);
    notifyListeners();
    if (b == null) return;
    try {
      await Directory(b.folder).delete(recursive: true);
    } catch (e) {
      debugPrint('Could not delete ${b.folder}: $e');
    }
  }

  // ---------------------------------------------------- position & offline

  /// Remembers where you are in a downloaded book, for resuming offline.
  Future<void> savePosition(String itemId, double seconds) async {
    final b = _books[itemId];
    if (b == null || (b.position - seconds).abs() < 1) return;
    b.position = seconds;
    await _writeManifest(b);
  }

  /// Remembers the position the server has for a downloaded book (called
  /// after each successful save online).
  Future<void> noteServerPosition(String itemId, double seconds) async {
    final b = _books[itemId];
    if (b == null) return;
    final known = b.serverPosition;
    if (known != null && (known - seconds).abs() < 1) return;
    b.serverPosition = seconds;
    await _writeManifest(b);
  }

  /// Records listening done without a server connection.
  Future<void> recordOffline({
    required PlaybackSession session,
    required double currentTime,
    required double listened,
    required String deviceId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = _pending[session.id] ??
        {
          'id': session.id,
          'libraryItemId': session.libraryItemId,
          'mediaType': 'book',
          'displayTitle': session.title,
          'displayAuthor': session.author,
          'duration': session.duration,
          'timeListening': 0.0,
          'startTime': currentTime,
          'startedAt': now,
          'mediaPlayer': 'media_kit',
          'deviceInfo': AbsApi.deviceInfo(deviceId),
          // What the server had when this listening started (see flushPending).
          'basePosition': _books[session.libraryItemId]?.serverPosition,
        };
    entry['currentTime'] = currentTime;
    entry['timeListening'] = ((entry['timeListening'] as num?)?.toDouble() ?? 0) + listened;
    entry['updatedAt'] = now;
    _pending[session.id] = entry;
    await savePosition(session.libraryItemId, currentTime);
    await _writePending();
  }

  /// Sends queued offline listening to the server. Safe to call often.
  ///
  /// Listening time is always sent (for stats). The position follows the
  /// keeper's rule ([decideOffline]): it's only sent if no other device has
  /// saved since the offline listening started. If another device saved an
  /// *earlier* spot, the offline one is offered next time the book is
  /// opened; if it saved a later one, that one stays.
  Future<void> flushPending(AbsApi api) async {
    if (_pending.isEmpty) return;
    final byBook = <String, List<String>>{};
    for (final e in _pending.entries) {
      byBook.putIfAbsent(e.value['libraryItemId'].toString(), () => []).add(e.key);
    }
    for (final itemId in byBook.keys) {
      final ids = byBook[itemId]!
        ..sort((a, b) => _num(_pending[a]!['startedAt']).compareTo(_num(_pending[b]!['startedAt'])));
      final latest = _pending[ids.last]!;
      final ours = _num(latest['currentTime']);
      final base = (_pending[ids.first]!['basePosition'] as num?)?.toDouble();
      final duration = _num(latest['duration']);
      try {
        final remote = await api.progressOf(itemId);
        final choice = decideOffline(server: remote?.currentTime, base: base, ours: ours);
        final keep = choice == OfflineChoice.sendOurs ? ours : remote!.currentTime;

        // Listening time for stats. Each session carries the winning
        // position, so the upload itself can never move you to the wrong one.
        for (final id in ids) {
          await api.syncLocalSession({..._pending[id]!, 'currentTime': keep}..remove('basePosition'));
        }
        if (choice == OfflineChoice.sendOurs) {
          await api.updateProgress(itemId, currentTime: ours, duration: duration);
          debugPrint('Uploaded offline listening for $itemId: ${ours.toStringAsFixed(0)} s.');
        } else if (choice == OfflineChoice.offerOurs) {
          // Another device saved an earlier spot since. Keep it for now and
          // let the book offer the offline spot when it's next opened.
          await PrefsUnsentStore().write(UnsentSave(
            itemId: itemId,
            sessionId: '',
            position: ours,
            // The server has already moved on from the base, so the book
            // offers this spot instead of sending it. (-1 if unknown; JSON
            // can't store NaN.)
            basePosition: base ?? -1,
            duration: duration,
            listened: 0,
          ));
          debugPrint('Another device saved ${keep.toStringAsFixed(0)} s for $itemId since; '
              'the offline spot ${ours.toStringAsFixed(0)} s will be offered next time.');
        } else {
          debugPrint('Kept the server position ${keep.toStringAsFixed(0)} s for $itemId: '
              'another device listened further than the offline ${ours.toStringAsFixed(0)} s.');
        }
        await noteServerPosition(itemId, keep);
        for (final id in ids) {
          _pending.remove(id);
        }
      } catch (e) {
        debugPrint('Could not upload offline listening for $itemId yet: $e');
        break; // still offline; try again later
      }
    }
    await _writePending();
  }

  static double _num(Object? v) => (v as num?)?.toDouble() ?? 0;

  // ------------------------------------------------------------ internals

  void _notifyThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastNotify) > const Duration(milliseconds: 250)) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  Future<void> _writeManifest(DownloadedBook b) async {
    final f = File('${b.folder}${Platform.pathSeparator}manifest.json');
    await f.writeAsString(jsonEncode(b.toJson()));
  }

  Future<void> _writePending() async {
    try {
      await File('${_root.path}${Platform.pathSeparator}pending.json').writeAsString(jsonEncode(_pending));
    } catch (_) {}
  }
}

class _Cancelled implements Exception {}

String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
