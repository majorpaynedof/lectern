import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One file for [WindowsPlayer]: a downloaded file on disk, or a web address
/// (with the login token in it, since Windows can't send our login header).
class WindowsSource {
  const WindowsSource({required this.source, required this.isFile, this.mime = 'audio/mp4'});
  final String source;
  final bool isFile;
  final String mime;
}

/// Plays audio through Windows' own media engine. Windows 11 can decode
/// formats the main player can't (notably Audible's xHE-AAC), so a book is
/// moved over here when the main player fails to decode it.
///
/// It mirrors the small part of media_kit's player that [PlayerController]
/// uses: a list of files, play/pause/seek/rate, and position updates. The
/// Windows side is windows/runner/windows_player.cpp.
class WindowsPlayer {
  WindowsPlayer() {
    if (Platform.isWindows) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'event') _onEvent((call.arguments as Map).cast<String, Object?>());
        return null;
      });
    }
  }

  static const _channel = MethodChannel('lectern/windows_player');

  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _index = StreamController<int>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _error = StreamController<String>.broadcast();

  Stream<bool> get playing => _playing.stream;
  Stream<Duration> get position => _position.stream;
  Stream<Duration> get duration => _duration.stream;
  Stream<int> get index => _index.stream;
  Stream<bool> get completed => _completed.stream;
  Stream<String> get error => _error.stream;

  List<WindowsSource> _sources = const [];
  int _current = 0;
  bool _wantPlay = false;
  Timer? _poll;

  /// Whether this PC has the Windows player hooked in (see
  /// installer/patch-windows-runner.ps1).
  static Future<bool> available() async {
    if (!Platform.isWindows) return false;
    try {
      await _channel.invokeMethod('state');
      return true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return true;
    }
  }

  Future<void> open(List<WindowsSource> sources, {int index = 0}) async {
    _sources = sources;
    _wantPlay = false;
    await _load(index);
  }

  Future<void> _load(int index) async {
    _current = index.clamp(0, _sources.length - 1);
    _index.add(_current);
    final s = _sources[_current];
    await _channel.invokeMethod('open', {'source': s.source, 'isFile': s.isFile, 'mime': s.mime});
    _startPolling();
  }

  Future<void> jump(int index) async {
    await _load(index);
    if (_wantPlay) await play();
  }

  Future<void> play() async {
    _wantPlay = true;
    await _channel.invokeMethod('play');
  }

  Future<void> pause() async {
    _wantPlay = false;
    await _channel.invokeMethod('pause');
  }

  Future<void> seek(Duration d) =>
      _channel.invokeMethod('seek', {'position': d.inMilliseconds / 1000.0});

  Future<void> setRate(double rate) => _channel.invokeMethod('rate', {'rate': rate});

  Future<void> stop() async {
    _wantPlay = false;
    _poll?.cancel();
    _poll = null;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    _playing.add(false);
  }

  void _startPolling() {
    _poll ??= Timer.periodic(const Duration(milliseconds: 250), (_) async {
      try {
        final m = (await _channel.invokeMethod('state') as Map).cast<String, Object?>();
        final pos = (m['position'] as num?)?.toDouble() ?? 0;
        _position.add(Duration(milliseconds: (pos * 1000).round()));
      } catch (_) {}
    });
  }

  void _onEvent(Map<String, Object?> e) {
    switch (e['type']) {
      case 'opened':
        final secs = (e['duration'] as num?)?.toDouble() ?? 0;
        _duration.add(Duration(milliseconds: (secs * 1000).round()));
      case 'state':
        _playing.add(e['playing'] == true);
      case 'ended':
        if (_current + 1 < _sources.length) {
          // Next file of a multi-file book.
          _load(_current + 1).then((_) => play());
        } else {
          _wantPlay = false;
          _playing.add(false);
          _completed.add(true);
        }
      case 'failed':
        final msg = e['message']?.toString() ?? 'Windows could not play this audio.';
        debugPrint('Windows player error: $msg');
        _error.add(msg);
    }
  }

  void dispose() {
    _poll?.cancel();
    if (Platform.isWindows) _channel.setMethodCallHandler(null);
    for (final c in [_playing, _position, _duration, _index, _completed, _error]) {
      c.close();
    }
  }
}
