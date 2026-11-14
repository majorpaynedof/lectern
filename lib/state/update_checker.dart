import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import '../update_check.dart';

/// Checks GitHub for a newer Lectern at start-up and at most once a day, and
/// tells the banner. It never downloads or installs anything: Download just
/// opens the release page. Can be turned off under Appearance → About.
class UpdateChecker extends ChangeNotifier {
  UpdateChecker({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _kEnabled = 'updateCheckEnabled';
  static const _kLastCheck = 'updateLastCheck';
  static const _kLatest = 'updateLatestVersion';
  static const _kLatestUrl = 'updateLatestUrl';
  static const _kSkipped = 'updateSkippedVersion';
  static const _every = Duration(hours: 24);

  String _current = '';
  bool enabled = true;
  bool checking = false;

  /// A newer release to tell you about, or null.
  ReleaseInfo? available;

  /// "Later" hides the banner until Lectern is next started.
  bool _later = false;

  /// What the last "Check now" found, for the About section.
  String? lastResult;

  Timer? _timer;

  String get currentVersion => _current;
  bool get showBanner => enabled && available != null && !_later;

  /// Called once at start-up with this copy's version.
  Future<void> start(String currentVersion) async {
    _current = currentVersion;
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_kEnabled) ?? true;

    // Show what the last check found straight away (no waiting for GitHub).
    final known = prefs.getString(_kLatest);
    final knownUrl = prefs.getString(_kLatestUrl) ?? AppInfo.repoUrl;
    if (known != null && _worthShowing(known, prefs)) {
      available = ReleaseInfo(version: known, url: knownUrl);
    }
    notifyListeners();

    if (enabled) unawaited(_checkIfDue());
    _timer = Timer.periodic(const Duration(hours: 6), (_) {
      if (enabled) _checkIfDue();
    });
  }

  bool _worthShowing(String version, SharedPreferences prefs) =>
      _current.isNotEmpty && isNewer(version, _current) && prefs.getString(_kSkipped) != version;

  Future<void> _checkIfDue() async {
    final prefs = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(prefs.getString(_kLastCheck) ?? '');
    if (last != null && DateTime.now().difference(last) < _every) return;
    await check();
  }

  /// Asks GitHub now. Returns a short message for "Check now".
  Future<String> check({bool manual = false}) async {
    final api = latestReleaseApi(AppInfo.repoUrl);
    if (api == null || _current.isEmpty || checking) return lastResult ?? '';
    checking = true;
    notifyListeners();
    try {
      final res = await _client.get(Uri.parse(api), headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Lectern/$_current',
      }).timeout(const Duration(seconds: 15));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastCheck, DateTime.now().toIso8601String());
      if (res.statusCode == 404) {
        lastResult = 'No releases found.';
        return lastResult!;
      }
      if (res.statusCode != 200) {
        lastResult = "Couldn't check for updates (GitHub answered ${res.statusCode}).";
        return lastResult!;
      }
      final release = parseLatestRelease(jsonDecode(res.body));
      if (release == null) {
        lastResult = "Couldn't read GitHub's answer.";
        return lastResult!;
      }
      await prefs.setString(_kLatest, release.version);
      await prefs.setString(_kLatestUrl, release.url);
      if (isNewer(release.version, _current)) {
        // "Check now" shows it even if you skipped it before.
        if (manual || prefs.getString(_kSkipped) != release.version) {
          available = release;
          _later = false;
        }
        lastResult = 'Lectern ${release.version} is available.';
      } else {
        available = null;
        lastResult = "You're up to date (${release.version}).";
      }
      return lastResult!;
    } catch (e) {
      // Offline or GitHub didn't answer: stay quiet, try again later.
      debugPrint('Update check failed: $e');
      lastResult = "Couldn't reach GitHub to check for updates.";
      return lastResult!;
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  void later() {
    _later = true;
    notifyListeners();
  }

  Future<void> skip() async {
    final v = available?.version;
    if (v == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSkipped, v);
    available = null;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
    notifyListeners();
    if (value) unawaited(_checkIfDue());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _client.close();
    super.dispose();
  }
}
