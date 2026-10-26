import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/abs_api.dart';
import '../models.dart';
import '../sync/abs_progress.dart';
import '../sync/progress_keeper.dart';
import 'downloads.dart';
import 'windows_player.dart';

enum SleepMode { off, timer, endOfChapter }

/// Owns the audio player and keeps the server in sync.
///
/// A book can be split across many audio files; everything public here works
/// in *book time* (seconds from the start of the book) and this class maps
/// that onto (file index, position within file).
class PlayerController extends ChangeNotifier {
  PlayerController(this.downloads) {
    _logEngineVersion();
    _loadWindowsBooks();
    // Main player (media_kit). Its events are ignored while a book is on the
    // Windows player.
    _subs.add(_player.stream.playing.listen((p) {
      if (!_onWindows) _onPlaying(p);
    }));
    _subs.add(_player.stream.playlist.listen((pl) {
      // Ignore entries the player adds itself (it can split a stream it
      // failed to open into pieces); only our own files count.
      if (!_onWindows && pl.index < (session?.tracks.length ?? 0)) _trackIndex = pl.index;
    }));
    _subs.add(_player.stream.position.listen((p) {
      if (!_onWindows) _onPosition(p);
    }));
    _subs.add(_player.stream.completed.listen((d) {
      if (!_onWindows) _onCompleted(d);
    }));
    _subs.add(_player.stream.error.listen((e) {
      if (_onWindows) return;
      debugPrint('Player error: $e (book: ${session?.title}, file ${_trackIndex + 1})');
      _distrust('player error');
      if (_isDecoderError(e)) {
        _handleUndecodable();
        return;
      }
      lastError = _friendly(e);
      if (lastError != e) _ePause(); // no audio output: stop "playing" silently
      notifyListeners();
    }));

    // Windows' own player, for formats the main player can't decode.
    _subs.add(_win.playing.listen((p) {
      if (_onWindows) _onPlaying(p);
    }));
    _subs.add(_win.index.listen((i) {
      if (_onWindows) _trackIndex = i;
    }));
    _subs.add(_win.position.listen((p) {
      if (_onWindows) _onPosition(p);
    }));
    _subs.add(_win.completed.listen((d) {
      if (_onWindows) _onCompleted(d);
    }));
    _subs.add(_win.error.listen((e) {
      if (!_onWindows || session == null) return;
      _distrust('Windows player error');
      lastError = 'Windows could not play this book: $e';
      notifyListeners();
    }));
  }

  final DownloadManager downloads;
  final Player _player = Player();
  final WindowsPlayer _win = WindowsPlayer();

  bool _onWindows = false;

  /// Books known to need the Windows player, so they start there directly
  /// next time instead of failing first. Remembered between launches.
  final Set<String> _windowsBooks = {};

  /// True while the current book plays through Windows' own media engine.
  bool get usingWindowsPlayer => _onWindows;
  final List<StreamSubscription> _subs = [];

  /// Current position in book time. Updates many times a second, so it is a
  /// separate notifier: only the seek bar rebuilds, not the whole screen.
  final ValueNotifier<double> position = ValueNotifier(0);

  AbsApi? _api;
  String _deviceId = '';
  PlaybackSession? session;

  /// True when playing a downloaded book without a server connection.
  bool offline = false;
  bool playing = false;
  bool loading = false;
  double speed = 1.0;
  String? lastError;

  SleepMode sleepMode = SleepMode.off;
  DateTime? sleepAt;

  int _trackIndex = 0;
  bool _seeking = false;
  bool _stopping = false;
  Timer? _tick;
  double _offlineListened = 0;
  int _secondsSinceSync = 0;

  // ---- saving progress
  /// Every save to the server goes through the keeper. It decides when it's
  /// safe to send a position (see lib/sync/progress_keeper.dart).
  late final ProgressKeeper keeper = ProgressKeeper(store: PrefsUnsentStore(), log: debugPrint)
    ..onChange = _onKeeperChange;

  /// When the server last confirmed our position.
  DateTime? get lastSavedAt => keeper.lastSavedAt;

  /// A problem from the player itself (not sure where it is in the book).
  String? _playerProblem;

  /// For the warning banner. Null when fine.
  String? get syncProblem => _playerProblem ?? keeper.problem;

  /// The server has a different position for this book from another
  /// device. The banner asks whether to jump there or stay, and nothing
  /// overwrites it until then.
  ({double currentTime, int lastUpdate})? get remoteNewer {
    final c = keeper.conflict;
    return c == null ? null : (currentTime: c.currentTime, lastUpdate: c.lastUpdate);
  }

  bool _hadConflict = false;

  void _onKeeperChange() {
    // Another device turned out to be elsewhere while this one was playing:
    // stop and ask, rather than play on from the wrong place.
    final conflict = keeper.conflict != null;
    if (conflict && !_hadConflict && playing && !_waking) _ePause();
    _hadConflict = conflict;
    notifyListeners();
  }

  /// When playback was last paused (or the PC went to sleep while playing).
  DateTime? _pausedAt;
  DateTime? _lastTick;
  bool _waking = false;

  /// Positions from the player are only believed once playback is really
  /// working near where we asked it to be. Until then (or after an error,
  /// a missing audio device, a file that didn't load...) nothing is saved,
  /// so a bogus 0:00 can never replace your real position on the server.
  bool _positionTrusted = false;
  int _untrustedSeconds = 0;
  double _expected = 0; // where playback should be while not trusted

  /// The last place you asked to go (a seek, chapter, Jump, or the start).
  /// Arriving there is never treated as an unexpected jump, however long
  /// the player takes to get there.
  double _target = 0;
  DateTime _lastAccepted = DateTime.now();

  /// After this long paused (or asleep), check the server before carrying on.
  /// Any real pause counts: a phone can move on in seconds.
  static const _checkAfter = Duration(seconds: 3);

  static const speeds = [0.75, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

  double get duration => session?.duration ?? 0;

  /// The server connection of the current playback (used for cover art).
  AbsApi? get api => _api;

  Chapter? chapterAt(double t) {
    final s = session;
    if (s == null) return null;
    for (final c in s.chapters) {
      if (t >= c.start && t < c.end) return c;
    }
    return null;
  }

  Chapter? get currentChapter => chapterAt(position.value);

  // ------------------------------------------------------------ playback

  Future<void> play(AbsApi api, String deviceId, String itemId, {double? startAt}) async {
    if (session?.libraryItemId == itemId) {
      if (startAt != null) {
        await seekTo(startAt);
        await _ePlay();
      } else {
        await _resume();
      }
      return;
    }
    await _start(api, deviceId, itemId,
        startAt: startAt, windows: _windowsBooks.contains(itemId) && await WindowsPlayer.available());
  }

  /// True while playing a stream the server converts for us (see
  /// [_playConverted]).
  bool converted = false;
  bool _converting = false;
  int _generation = 0;

  /// Errors from the audio decoder, e.g. "Failed to initialize a decoder for
  /// codec 'aac'" or "Could not open codec". Some books use audio variants
  /// (newer AAC types, Dolby) that the bundled player can't decode.
  ///
  /// "Error decoding audio." on its own can be a single damaged frame, so
  /// that only counts once it keeps happening (the decoder opens but can't
  /// actually decode this format).
  bool _isDecoderError(String e) {
    final s = e.toLowerCase();
    if (s.contains('codec') || s.contains('decoder')) return true;
    if (s.contains('error decoding')) return ++_decodeErrors >= 5;
    return false;
  }

  int _decodeErrors = 0;

  bool get _canConvert =>
      session != null && _api != null && !offline && !converted && !_converting;

  /// The main player can't decode this book. Prefer Windows' own player
  /// (works offline too); fall back to asking the server to convert it.
  Future<void> _handleUndecodable() async {
    final s = session;
    final api = _api;
    if (s == null || api == null || _converting) return;
    if (await WindowsPlayer.available()) {
      _converting = true;
      final at = position.value;
      debugPrint('Main player cannot decode ${s.title}; switching to the Windows player.');
      _rememberWindowsBook(s.libraryItemId);
      try {
        await stop();
        await _start(api, _deviceId, s.libraryItemId, startAt: at, windows: true);
      } finally {
        _converting = false;
      }
    } else if (_canConvert) {
      if (Platform.isWindows) {
        debugPrint('The Windows player is not set up in this build '
            '(run installer\\patch-windows-runner.ps1); trying server conversion.');
      }
      await _playConverted();
    }
  }

  Future<void> _loadWindowsBooks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _windowsBooks.addAll(prefs.getStringList('windowsPlayerBooks') ?? const []);
    } catch (_) {}
  }

  Future<void> _rememberWindowsBook(String itemId) async {
    if (!_windowsBooks.add(itemId)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('windowsPlayerBooks', _windowsBooks.toList());
    } catch (_) {}
  }

  /// Restarts the current book at the same spot, but asks the server to
  /// convert the audio into a standard stream the player can always decode.
  Future<void> _playConverted() async {
    final s = session;
    final api = _api;
    if (s == null || api == null) return;
    _converting = true;
    final at = position.value;
    debugPrint('Audio format not supported here; asking the server to convert ${s.title}.');
    try {
      await stop();
      await _start(api, _deviceId, s.libraryItemId, startAt: at, transcode: true);
    } finally {
      _converting = false;
    }
  }

  Future<void> _start(AbsApi api, String deviceId, String itemId,
      {double? startAt, bool transcode = false, bool windows = false}) async {
    final gen = ++_generation;
    await stop();
    _onWindows = windows;
    loading = true;
    lastError = null;
    converted = transcode;
    _decodeErrors = 0;
    notifyListeners();

    try {
      // A converted stream always comes from the server, never from disk.
      var local = transcode ? null : downloads.book(itemId);
      PlaybackSession s;
      try {
        s = await api.startPlayback(itemId, deviceId, transcode: transcode);
        offline = false;
      } catch (e) {
        // No server: fall back to the downloaded copy if there is one.
        local = downloads.book(itemId);
        if (local == null) rethrow;
        s = local.toSession();
        offline = true;
        converted = false;
      }
      if (s.tracks.isEmpty) throw StateError('This item has no playable audio.');
      _api = api;
      _deviceId = deviceId;
      session = s;
      _playerProblem = null;
      _offlineListened = 0;

      // Where the server says you are, or further on if this PC played
      // further last time and couldn't save it (and no other device has
      // saved since).
      var resumeAt = s.currentTime;
      if (offline) {
        keeper.end();
      } else {
        resumeAt = await keeper.begin(
          server: AbsProgressServer(api, deviceId: deviceId, transcode: transcode),
          itemId: itemId,
          sessionId: s.id,
          duration: s.duration,
          serverPosition: s.currentTime,
        );
        if (gen != _generation) return;
      }

      final start = (startAt ?? resumeAt).clamp(0.0, math.max(s.duration, 0.0)).toDouble();
      if (startAt != null) keeper.userSeeked(start);
      final idx = s.trackIndexFor(start);
      _trackIndex = idx;
      position.value = start;
      _positionTrusted = false;
      _expected = start;
      _target = start;

      final ready = _waitForDuration();
      if (windows) {
        // Prefer files on disk; stream anything that isn't downloaded. Windows
        // can't send our login header, so the token goes in the address.
        await _win.open([
          for (final t in s.tracks)
            if (local?.pathForIndex(t.index) case final path?)
              WindowsSource(source: path, isFile: true, mime: _mimeFor(path))
            else
              WindowsSource(source: _withToken(api, t.contentUrl), isFile: false),
        ], index: idx);
      } else {
        await _tuneForStream(converted: transcode && !offline);
        if (transcode && !offline) {
          await _waitForConvertedAudio(api, s, start);
          if (gen != _generation) return;
        }
        // Prefer files on disk; stream anything that isn't downloaded.
        final medias = [
          for (final t in s.tracks)
            if (local?.pathForIndex(t.index) case final path?)
              Media(path)
            else
              Media(api.trackUri(t.contentUrl).toString(), httpHeaders: api.authHeaders),
        ];
        await _player.open(Playlist(medias, index: idx), play: false);
      }
      await ready;
      // A newer start (e.g. the converted stream) took over while loading.
      if (gen != _generation) return;
      await _eSeek(_within(idx, start));
      await _eRate(speed);
      await _ePlay();
      _startTick();
    } catch (e) {
      if (gen != _generation) return;
      debugPrint('Could not start playback of $itemId: $e');
      lastError = e.toString();
      session = null;
    } finally {
      if (gen == _generation) loading = false;
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    if (session == null) return;
    if (playing) {
      await _ePause();
    } else {
      await _resume();
    }
  }

  /// Carry on playing. After a long pause (or sleep), first check whether
  /// another device has listened further; if so, ask instead of playing.
  Future<void> _resume() async {
    final paused = _pausedAt;
    final pausedFor = paused == null ? Duration.zero : DateTime.now().difference(paused);
    if (!offline && keeper.active) {
      if (keeper.conflict != null) return; // the banner is asking
      if (_waking || pausedFor > _checkAfter) {
        keeper.hold(_waking ? 'woke from sleep' : 'paused');
        // After sleep the network can take a few seconds to come back.
        final r = await keeper.check(localPosition: position.value, patient: _waking);
        if (r == CheckResult.otherDeviceAhead) return;
        // Unreachable: play anyway. Your place is kept on this PC and only
        // sent once the server has been checked.
      } else {
        keeper.releasePause();
      }
    }
    // After a long pause or sleep the stream may have been dropped; seeking
    // first makes the player reopen it at our place, not at 0:00.
    if (pausedFor > const Duration(minutes: 1) && session != null) {
      await seekTo(position.value);
    }
    await _ePlay();
  }

  void dismissSyncProblem() {
    _playerProblem = null;
    keeper.problem = null;
    notifyListeners();
  }

  void dismissError() {
    lastError = null;
    notifyListeners();
  }

  /// A later spot this PC played while offline, when another device has
  /// saved an earlier one since. The banner offers it.
  double? get offlineSpot => keeper.offlineSpot;

  /// The answer to the "you got further on this PC while offline" banner.
  Future<void> resolveOfflineSpot({required bool go}) async {
    final spot = keeper.offlineSpot;
    keeper.offlineSpot = null;
    notifyListeners();
    if (spot == null || session == null) return;
    if (go) await seekTo(spot); // the next save sends it
  }

  /// The answer to the "further along on another device" banner.
  Future<void> resolveRemoteNewer({required bool jump}) async {
    final r = keeper.conflict;
    if (r == null || session == null) return;
    await keeper.resolve(jump: jump, localPosition: position.value);
    if (jump) await seekTo(r.currentTime);
    await _ePlay();
  }

  Future<void> skip(double seconds) => seekTo(position.value + seconds);

  Future<void> seekTo(double seconds) async {
    final s = session;
    if (s == null) return;
    final t = seconds.clamp(0.0, math.max(s.duration - 1, 0.0)).toDouble();
    final idx = s.trackIndexFor(t);
    _seeking = true;
    position.value = t;
    keeper.userSeeked(t);
    _expected = t;
    _target = t;
    _untrustedSeconds = 0;
    try {
      if (idx != _trackIndex) {
        final ready = _waitForDuration();
        _trackIndex = idx;
        await _eJump(idx);
        await ready;
      }
      await _eSeek(_within(idx, t));
    } finally {
      _seeking = false;
    }
  }

  Future<void> nextChapter() async {
    final s = session;
    if (s == null) return;
    for (final c in s.chapters) {
      if (c.start > position.value + 0.5) return seekTo(c.start);
    }
  }

  Future<void> previousChapter() async {
    final s = session;
    final c = currentChapter;
    if (s == null || c == null) return seekTo(0);
    // Like a music player: first press restarts the chapter.
    if (position.value - c.start > 3) return seekTo(c.start);
    final i = s.chapters.indexOf(c);
    return seekTo(i > 0 ? s.chapters[i - 1].start : 0);
  }

  Future<void> setSpeed(double v) async {
    speed = v;
    notifyListeners();
    await _eRate(v);
  }

  void setSleepTimer(Duration? d) {
    if (d == null) {
      sleepMode = SleepMode.off;
      sleepAt = null;
    } else {
      sleepMode = SleepMode.timer;
      sleepAt = DateTime.now().add(d);
    }
    notifyListeners();
  }

  void sleepAtEndOfChapter() {
    sleepMode = SleepMode.endOfChapter;
    sleepAt = null;
    notifyListeners();
  }

  Duration? get sleepRemaining {
    final at = sleepAt;
    if (sleepMode != SleepMode.timer || at == null) return null;
    final r = at.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  Future<void> stop() async {
    if (session == null) return;
    _stopping = true;
    _tick?.cancel();
    _tick = null;
    try {
      await _ePause();
      // The keeper checks the server first if needed, so closing never
      // overwrites a newer position from another device.
      await _sync(close: true);
      await _eStop();
    } finally {
      keeper.end();
      session = null;
      sleepMode = SleepMode.off;
      sleepAt = null;
      position.value = 0;
      _stopping = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ internals

  // The active engine: Windows' player or the main one.
  Future<void> _ePlay() => _onWindows ? _win.play() : _player.play();
  Future<void> _ePause() => _onWindows ? _win.pause() : _player.pause();
  Future<void> _eSeek(Duration d) => _onWindows ? _win.seek(d) : _player.seek(d);
  Future<void> _eJump(int i) => _onWindows ? _win.jump(i) : _player.jump(i);
  Future<void> _eRate(double r) => _onWindows ? _win.setRate(r) : _player.setRate(r);
  Future<void> _eStop() => _onWindows ? _win.stop() : _player.stop();

  static String _withToken(AbsApi api, String contentUrl) {
    final uri = api.trackUri(contentUrl);
    return uri.replace(queryParameters: {...uri.queryParameters, 'token': api.token}).toString();
  }

  static String _mimeFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.mp3')) return 'audio/mpeg';
    if (p.endsWith('.flac')) return 'audio/flac';
    if (p.endsWith('.ogg') || p.endsWith('.opus')) return 'audio/ogg';
    if (p.endsWith('.wav')) return 'audio/wav';
    return 'audio/mp4'; // m4b, m4a, mp4, aac
  }

  /// Prints which audio engine is in use, e.g. "Audio engine: mpv
  /// v0.40.0-..., FFmpeg N-12345-...". Handy for checking the newer one loaded.
  Future<void> _logEngineVersion() async {
    final native = _player.platform;
    if (native is! NativePlayer) return;
    try {
      final mpv = await native.getProperty('mpv-version');
      final ffmpeg = await native.getProperty('ffmpeg-version');
      debugPrint('Audio engine: $mpv, FFmpeg $ffmpeg');
    } catch (_) {}
  }

  /// A converted stream is made by the server in 6-second pieces as we
  /// listen. Read only a little ahead so we never ask for pieces it hasn't
  /// made yet, and retry a piece that isn't ready instead of skipping it.
  Future<void> _tuneForStream({required bool converted}) async {
    final native = _player.platform;
    if (native is! NativePlayer) return;
    try {
      await native.setProperty('cache-secs', converted ? '20' : '3600000');
      await native.setProperty('demuxer-lavf-o', converted ? 'seg_max_retry=30' : '');
    } catch (e) {
      debugPrint('Could not tune the player: $e');
    }
  }

  /// The server starts converting at the listening position; wait until the
  /// piece for that spot exists before the player asks for it (up to ~45 s).
  Future<void> _waitForConvertedAudio(AbsApi api, PlaybackSession s, double start) async {
    final url = s.tracks.first.contentUrl;
    final slash = url.lastIndexOf('/');
    if (!url.startsWith('/hls/') || slash < 0) return;
    final piece = '${url.substring(0, slash)}/output-${(start / 6).floor()}.ts';
    for (var i = 0; i < 90; i++) {
      try {
        final res = await api.client
            .get(api.trackUri(piece), headers: api.authHeaders)
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) return;
        if (res.statusCode == 401 || res.statusCode == 403) {
          throw StateError('The server refused the converted audio (${res.statusCode}).');
        }
      } on TimeoutException {
        // keep waiting
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    debugPrint('Converted audio still not ready; trying anyway.');
  }

  Duration _within(int idx, double bookTime) {
    final offset = bookTime - session!.tracks[idx].startOffset;
    return Duration(milliseconds: math.max(0, (offset * 1000).round()));
  }

  /// media_kit ignores seeks issued before a file has loaded, so we wait for
  /// it to report a duration first.
  Future<Duration> _waitForDuration() => (_onWindows ? _win.duration : _player.stream.duration)
      .firstWhere((d) => d > Duration.zero)
      .timeout(const Duration(seconds: 8), onTimeout: () => Duration.zero)
      .catchError((_) => Duration.zero);

  void _onPlaying(bool p) {
    playing = p;
    if (p) {
      _pausedAt = null;
    } else if (!_waking) {
      _pausedAt = DateTime.now();
    }
    notifyListeners();
    // Save the position whenever we pause, except when pausing because the
    // PC just woke up: then the server is checked first (see _startTick).
    // After that save, hold further saves: if the pause turns out long, the
    // server is checked before carrying on (see [_resume]).
    if (!p && !_stopping && !_waking) {
      _sync().whenComplete(() {
        // (Not while the book is still loading: nothing has played yet.)
        if (!playing && session != null && _positionTrusted) keeper.hold('paused');
      });
    }
  }

  void _onPosition(Duration p) {
    final s = session;
    if (s == null || _seeking || s.tracks.isEmpty) return;
    final idx = _trackIndex.clamp(0, s.tracks.length - 1);
    final t = s.tracks[idx].startOffset + p.inMilliseconds / 1000.0;

    final now = DateTime.now();
    final nearTarget = (t - _target).abs() < 60;
    if (!_positionTrusted) {
      // Believe the player only once it's playing close to where it should
      // be: the last good position or the last place you asked to go. A
      // failed load often reports 0:00 or jumps to the end.
      if (playing && ((t - _expected).abs() < 60 || nearTarget)) {
        _positionTrusted = true;
        _untrustedSeconds = 0;
        debugPrint('Playback confirmed at ${t.toStringAsFixed(0)} s; saving progress is on.');
      } else {
        return;
      }
    } else {
      // Normal playback moves at about playback speed. A big move nobody
      // asked for means the player lost its place: ignore it, don't save it.
      final elapsed = now.difference(_lastAccepted).inMilliseconds / 1000.0;
      final allowed = elapsed * speed + 30;
      if ((t - position.value).abs() > allowed && !nearTarget) {
        debugPrint('Ignoring unexpected jump from ${position.value.toStringAsFixed(0)} s to ${t.toStringAsFixed(0)} s.');
        final goodPosition = position.value;
        _distrust('unexpected jump');
        _recoverTo(goodPosition);
        return;
      }
    }
    _lastAccepted = now;
    position.value = t;

    if (sleepMode == SleepMode.endOfChapter && playing) {
      final c = currentChapter;
      if (c != null && position.value >= c.end - 0.6) {
        _ePause();
        sleepMode = SleepMode.off;
        notifyListeners();
      }
    }
  }

  /// The player lost its place (often after the PC slept and the stream was
  /// dropped): send it back to the last good position. Limited to a few
  /// tries a minute so a broken file can't loop.
  final List<DateTime> _recoveries = [];

  Future<void> _recoverTo(double good) async {
    final now = DateTime.now();
    _recoveries.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (_recoveries.length >= 3) {
      debugPrint('Not trying to recover again yet (3 tries in the last minute).');
      return;
    }
    _recoveries.add(now);
    debugPrint('Putting the player back at ${good.toStringAsFixed(0)} s.');
    try {
      await seekTo(good);
    } catch (e) {
      debugPrint('Could not put the player back: $e');
    }
  }

  /// Stop believing (and saving) positions until playback is confirmed
  /// again near the last good one.
  void _distrust(String why) {
    if (!_positionTrusted) return;
    _positionTrusted = false;
    _expected = position.value;
    debugPrint('Not saving progress until playback works again ($why).');
  }

  static String _friendly(String e) {
    final s = e.toLowerCase();
    if (s.contains('audio device') || s.contains('audio output') || s.contains('ao:') || s.contains('no audio')) {
      return 'No audio output found. Plug in headphones or speakers, then press play. Your place in the book is safe.';
    }
    return e;
  }

  void _onCompleted(bool done) {
    final s = session;
    // Only a real finish counts: playback was working and reached the end.
    // (A file that fails to play can also report "completed".)
    if (done && s != null && _positionTrusted && _trackIndex >= s.tracks.length - 1 && position.value >= s.duration - 30) {
      _sync();
    }
  }

  void _startTick() {
    _tick?.cancel();
    _lastTick = DateTime.now();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final gap = now.difference(_lastTick ?? now);
      _lastTick = now;
      if (playing && gap > const Duration(seconds: 30)) {
        // The PC slept while playing. Pause and check the server before
        // carrying on, in case another device was used meanwhile.
        debugPrint('Woke up after ${gap.inMinutes} min; checking the server before continuing.');
        _waking = true;
        keeper.hold('woke from sleep');
        _pausedAt = now.subtract(gap);
        _ePause().then((_) => _resume()).whenComplete(() => _waking = false);
        return;
      }
      if (playing) {
        if (offline) {
          _offlineListened += 1;
        } else {
          keeper.addListened(1);
        }
        _secondsSinceSync++;
        // Playing for a minute without a believable position: say so, rather
        // than silently not saving.
        _untrustedSeconds = _positionTrusted ? 0 : _untrustedSeconds + 1;
        if (_untrustedSeconds == 60 && syncProblem == null) {
          _playerProblem = 'Lectern isn\'t sure where you are in this book, so it has stopped saving your place. '
              'Pick your chapter from the chapter list to carry on saving.';
          notifyListeners();
        }
      }
      if (sleepMode == SleepMode.timer) {
        final at = sleepAt;
        if (at != null && DateTime.now().isAfter(at)) {
          _ePause();
          sleepMode = SleepMode.off;
          sleepAt = null;
        }
        notifyListeners(); // refresh the countdown label
      }
      if (_secondsSinceSync >= 15) {
        _secondsSinceSync = 0;
        _sync();
      }
    });
  }

  /// Saves the position: every 15 s while playing, on pause, and when the
  /// book is closed. Online, the keeper decides whether it's safe to send.
  Future<void> _sync({bool close = false}) async {
    final s = session;
    if (s == null) return;
    if (_positionTrusted && downloads.isDownloaded(s.libraryItemId)) {
      downloads.savePosition(s.libraryItemId, position.value);
    }
    if (offline) {
      if (!_positionTrusted) return;
      final listened = _offlineListened;
      _offlineListened = 0;
      await downloads.recordOffline(
          session: s, currentTime: position.value, listened: listened, deviceId: _deviceId);
      return;
    }
    if (close) {
      await keeper.close(position.value, trusted: _positionTrusted);
      return;
    }
    final r = await keeper.save(position.value, trusted: _positionTrusted);
    if (r == SaveResult.blockedBackwards && session?.id == s.id) {
      // The player went backwards by itself: put it back.
      final good = keeper.base;
      _distrust('position went backwards');
      _recoverTo(good);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _tick?.cancel();
    keeper.onChange = null; // nothing to notify once disposed
    _sync(close: true);
    _player.dispose();
    _win.dispose();
    position.dispose();
    super.dispose();
  }
}

