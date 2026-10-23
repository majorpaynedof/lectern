import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'player_controller.dart';

/// Connects Lectern to Windows' media controls: keyboard media keys, the
/// media tile in Quick Settings, and the lock screen. It mirrors what the
/// [PlayerController] is doing and forwards button presses back to it.
///
/// The Windows side lives in windows/runner/media_controls.cpp and talks to
/// this class over a method channel. Does nothing on other platforms.
class MediaControls {
  MediaControls(this.player);

  final PlayerController player;

  static const _channel = MethodChannel('lectern/media_controls');

  bool _available = false;
  String? _itemId;
  bool? _playing;
  int _lastPositionSecond = -1;

  void start() {
    if (!Platform.isWindows) return;
    _available = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'button') _onButton(call.arguments as String? ?? '');
      return null;
    });
    player.addListener(_sync);
    player.position.addListener(_onPosition);
  }

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    if (!_available) return;
    try {
      await _channel.invokeMethod(method, args);
    } on MissingPluginException {
      // The Windows code isn't hooked in (see installer/patch-windows-runner.ps1).
      _available = false;
      debugPrint('Windows media controls are not set up in windows\\runner.');
    } catch (e) {
      debugPrint('Media controls update failed: $e');
    }
  }

  void _onButton(String button) {
    switch (button) {
      case 'play':
      case 'pause':
        player.togglePlay();
      case 'next':
        player.nextChapter();
      case 'previous':
        player.previousChapter();
      case 'fastForward':
        player.skip(30);
      case 'rewind':
        player.skip(-10);
      case 'stop':
        player.stop();
    }
  }

  /// Runs whenever the player's state changes (book, play/pause, ...).
  Future<void> _sync() async {
    if (!_available) return;
    final s = player.session;
    if (s == null) {
      if (_itemId != null) {
        _itemId = null;
        _playing = null;
        await _call('disable');
      }
      return;
    }

    if (_itemId != s.libraryItemId) {
      _itemId = s.libraryItemId;
      _lastPositionSecond = -1;
      await _call('metadata', {
        'title': s.title,
        'artist': s.author,
        'thumbnail': _coverUrl(s.libraryItemId),
      });
      await _call('timeline', {'position': player.position.value, 'duration': s.duration});
    }

    if (_playing != player.playing) {
      _playing = player.playing;
      await _call('status', {'playing': player.playing});
    }
  }

  /// Position updates arrive many times a second; Windows only needs them
  /// about once every few seconds.
  void _onPosition() {
    final s = player.session;
    if (!_available || s == null || _itemId == null) return;
    final second = player.position.value.floor();
    if ((second - _lastPositionSecond).abs() < 5) return;
    _lastPositionSecond = second;
    _call('timeline', {'position': player.position.value, 'duration': s.duration});
  }

  /// Windows fetches the cover itself and can't send our login header, so
  /// the token goes in the address instead (Audiobookshelf accepts both).
  /// Downloaded books use their local copy.
  String? _coverUrl(String itemId) {
    final local = player.downloads.coverPath(itemId);
    if (player.offline && local != null) return Uri.file(local).toString();
    final api = player.api;
    if (api == null) return local == null ? null : Uri.file(local).toString();
    return '${api.coverUri(itemId, width: 400)}&token=${Uri.encodeQueryComponent(api.token)}';
  }

  void dispose() {
    player.removeListener(_sync);
    player.position.removeListener(_onPosition);
    if (_available) _channel.setMethodCallHandler(null);
  }
}
