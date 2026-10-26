import 'package:shared_preferences/shared_preferences.dart';

import '../api/abs_api.dart';
import 'progress_keeper.dart';

/// [ProgressServer] on top of the Audiobookshelf API.
class AbsProgressServer implements ProgressServer {
  AbsProgressServer(this.api, {required this.deviceId, this.transcode = false});

  final AbsApi api;
  final String deviceId;
  final bool transcode;

  /// The server answered with an error: it's reachable. Anything else
  /// (no connection, timeout) passes through as "couldn't reach".
  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on AbsApiException catch (e) {
      throw ServerRejected(e.toString());
    }
  }

  @override
  Future<ServerProgress?> fetch(String itemId) => _call(() async {
        final p = await api.progressOf(itemId);
        return p == null ? null : ServerProgress(p.currentTime, p.lastUpdate);
      });

  @override
  Future<void> sync(String sessionId,
          {required double currentTime, required double listened, required double duration}) =>
      _call(() => api.syncSession(sessionId, currentTime: currentTime, timeListened: listened, duration: duration));

  @override
  Future<void> close(String sessionId,
          {required double currentTime, required double listened, required double duration}) =>
      _call(() => api.closeSession(sessionId, currentTime: currentTime, timeListened: listened, duration: duration));

  @override
  Future<void> put(String itemId, {required double currentTime, required double duration}) =>
      _call(() => api.updateProgress(itemId, currentTime: currentTime, duration: duration));

  @override
  Future<String?> renewSession(String itemId) async {
    try {
      return (await api.startPlayback(itemId, deviceId, transcode: transcode)).id;
    } catch (_) {
      return null;
    }
  }
}

/// Keeps unsent positions in the app's settings, so they survive closing
/// Lectern or a crash.
class PrefsUnsentStore implements UnsentStore {
  static String _key(String itemId) => 'unsentProgress.$itemId';

  @override
  Future<UnsentSave?> load(String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key(itemId));
    return s == null ? null : UnsentSave.decode(s);
  }

  @override
  Future<void> write(UnsentSave save) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(save.itemId), save.encode());
  }

  @override
  Future<void> clear(String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(itemId));
  }
}
