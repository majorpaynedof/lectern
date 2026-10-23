import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/abs_api.dart';
import '../models.dart';

/// Who is logged in, to which server, and which library is selected.
class AppSession extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();

  // The secure store rewrites one shared file on every change, so changes
  // made at the same moment can overwrite each other (that's how a freshly
  // refreshed sign-in could be lost). Every read and write goes through this
  // queue, one at a time.
  Future<void> _queue = Future.value();

  Future<T> _locked<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<String?> _read(String key) => _locked(() => _storage.read(key: key));

  Future<void> _write(String key, String? value) =>
      _locked(() => value == null ? _storage.delete(key: key) : _storage.write(key: key, value: value));

  AbsApi? api;
  String deviceId = '';
  String? username;
  bool canEdit = false; // user may change book and author details
  List<Library> libraries = [];
  Library? currentLibrary;
  bool restoring = true;

  /// Signed in, but the server can't be reached: only downloads work.
  bool offline = false;

  /// Called whenever the server becomes reachable (used to upload offline
  /// listening).
  void Function(AbsApi api)? onOnline;

  /// libraryItemId -> progress (0..1), for progress bars on covers.
  Map<String, double> progress = {};
  Set<String> finished = {};

  Future<void> restore() async {
    try {
      deviceId = await _read('deviceId') ?? '';
      if (deviceId.isEmpty) {
        deviceId = _randomId();
        await _write('deviceId', deviceId);
      }
      final server = await _read('server');
      final token = await _read('token');
      if (server != null && token != null) {
        final refresh = await _read('refreshToken');
        final candidate = AbsApi(baseUrl: server, token: token, refreshToken: refresh);
        try {
          await _activate(candidate);
        } on AbsApiException catch (e) {
          if (e.status == 401 || e.status == 403) rethrow; // signed out on the server
          await _goOffline(candidate, e);
        } catch (e) {
          // One more try before giving up: a single dropped connection
          // shouldn't send the whole app offline.
          try {
            await Future<void>.delayed(const Duration(seconds: 1));
            await _activate(candidate);
          } catch (e2) {
            await _goOffline(candidate, e2); // no network / server down
          }
        }
      }
    } catch (e) {
      debugPrint('Session restore failed: $e');
      api = null;
    }
    restoring = false;
    notifyListeners();
  }

  Future<void> _goOffline(AbsApi candidate, Object error) async {
    debugPrint('Server unreachable, starting offline: $error');
    candidate.onTokensChanged = _saveTokens;
    api = candidate;
    offline = true;
    libraries = [];
    currentLibrary = null;
    username = await _read('username');
  }

  /// Tries to reach the server again after starting offline.
  Future<bool> retryOnline() async {
    final a = api;
    if (a == null) return false;
    try {
      await _activate(a);
      offline = false;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> loginWithPassword(String server, String user, String password) async {
    final (access, refresh) = await AbsApi.login(server, user, password);
    await _finishLogin(AbsApi(baseUrl: server, token: access, refreshToken: refresh));
  }

  Future<void> loginWithApiKey(String server, String key) =>
      _finishLogin(AbsApi(baseUrl: server, token: key.trim()));

  Future<void> _finishLogin(AbsApi candidate) async {
    try {
      await _activate(candidate);
    } on AbsApiException catch (e) {
      if (e.status == 401) throw AbsApiException(401, 'That key or token was rejected');
      rethrow;
    }
    await _write('server', candidate.baseUrl);
    await _saveTokens(candidate.token, candidate.refreshToken);
    notifyListeners();
  }

  Future<void> _activate(AbsApi candidate) async {
    candidate.onTokensChanged = _saveTokens;
    final me = await candidate.me(); // validates the token
    api = candidate;
    username = me['username']?.toString();
    final type = me['type']?.toString();
    final perms = me['permissions'];
    canEdit = type == 'root' || type == 'admin' || (perms is Map && perms['update'] == true);
    _readProgress(me);
    if (username != null) await _write('username', username);

    final libs = await candidate.libraries();
    libraries = libs.where((l) => l.mediaType == 'book').toList();
    final saved = await _read('library');
    currentLibrary = null;
    for (final l in libraries) {
      if (l.id == saved) currentLibrary = l;
    }
    currentLibrary ??= libraries.isNotEmpty ? libraries.first : null;
    offline = false;
    onOnline?.call(candidate);
  }

  /// Saves both tokens as one step in the queue, so nothing can slip in
  /// between them.
  Future<void> _saveTokens(String access, String? refresh) => _locked(() async {
        await _storage.write(key: 'token', value: access);
        if (refresh != null) {
          await _storage.write(key: 'refreshToken', value: refresh);
        } else {
          await _storage.delete(key: 'refreshToken');
        }
      });

  void _readProgress(Map<String, dynamic> me) {
    final list = me['mediaProgress'];
    final p = <String, double>{};
    final f = <String>{};
    if (list is List) {
      for (final e in list) {
        if (e is! Map || e['episodeId'] != null) continue;
        final id = e['libraryItemId']?.toString();
        if (id == null) continue;
        p[id] = (e['progress'] as num?)?.toDouble() ?? 0;
        if (e['isFinished'] == true) f.add(id);
      }
    }
    progress = p;
    finished = f;
  }

  Future<void> refreshProgress() async {
    final a = api;
    if (a == null) return;
    try {
      _readProgress(await a.me());
      notifyListeners();
    } catch (_) {}
  }

  Future<void> selectLibrary(Library l) async {
    currentLibrary = l;
    notifyListeners();
    await _write('library', l.id);
  }

  Future<void> logout() async {
    api = null;
    offline = false;
    libraries = [];
    currentLibrary = null;
    progress = {};
    finished = {};
    await _write('token', null);
    await _write('refreshToken', null);
    notifyListeners();
  }

  Future<String?> lastServer() => _read('server');

  static String _randomId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
