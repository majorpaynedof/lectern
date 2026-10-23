import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Sets the window title and minimum size, and remembers the window's size,
/// position and maximized state between launches.
class WindowState with WindowListener {
  WindowState._(this._prefs);

  static const _key = 'window';
  static const _minSize = Size(900, 600);

  final SharedPreferences _prefs;
  Timer? _saveTimer;

  static Future<void> setUp() async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    await windowManager.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final state = WindowState._(prefs);

    Rect? bounds;
    var maximized = false;
    final saved = prefs.getString(_key);
    if (saved != null) {
      try {
        final m = jsonDecode(saved) as Map<String, dynamic>;
        final r = Rect.fromLTWH(
          (m['x'] as num).toDouble(),
          (m['y'] as num).toDouble(),
          (m['w'] as num).toDouble(),
          (m['h'] as num).toDouble(),
        );
        // Ignore obviously broken values (e.g. a monitor that was unplugged).
        if (r.width >= _minSize.width && r.height >= _minSize.height && r.left > -4000 && r.top > -4000) {
          bounds = r;
        }
        maximized = m['max'] == true;
      } catch (_) {}
    }

    const options = WindowOptions(
      title: 'Lectern',
      size: Size(1280, 800),
      minimumSize: _minSize,
      center: true,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (bounds != null) await windowManager.setBounds(bounds);
      if (maximized) await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });
    windowManager.addListener(state);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    try {
      if (await windowManager.isMinimized()) return;
      final maximized = await windowManager.isMaximized();
      Map<String, dynamic> data;
      if (maximized) {
        // Keep the last normal size so un-maximizing next time looks right.
        final previous = _prefs.getString(_key);
        data = previous == null ? <String, dynamic>{} : (jsonDecode(previous) as Map<String, dynamic>);
        if (data.isEmpty) return;
        data['max'] = true;
      } else {
        final b = await windowManager.getBounds();
        data = {'x': b.left, 'y': b.top, 'w': b.width, 'h': b.height, 'max': false};
      }
      await _prefs.setString(_key, jsonEncode(data));
    } catch (_) {}
  }

  @override
  void onWindowResize() => _scheduleSave();

  @override
  void onWindowMove() => _scheduleSave();

  @override
  void onWindowMaximize() => _scheduleSave();

  @override
  void onWindowUnmaximize() => _scheduleSave();
}
