import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// Holds the chosen color theme and remembers it between launches.
///
/// These aren't secrets, so they live in ordinary settings rather than the
/// encrypted store that holds the login (sharing that file caused clashes).
class ThemeController extends ChangeNotifier {

  LecternPalette palette = LecternPalettes.amber;

  /// Bigger buttons, always-visible controls and long-press menus, for
  /// touchscreens. Remembered per computer.
  bool touchMode = false;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      palette = LecternPalettes.byId(prefs.getString('palette'));
      touchMode = prefs.getBool('touchMode') ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setTouchMode(bool on) async {
    if (touchMode == on) return;
    touchMode = on;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool('touchMode', on);
    } catch (_) {}
  }

  Future<void> select(LecternPalette p) async {
    if (p.id == palette.id) return;
    palette = p;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setString('palette', p.id);
    } catch (_) {}
  }
}

extension TouchContext on BuildContext {
  /// True when Touch mode is on. Rebuilds the widget when it changes.
  bool get isTouch => select<ThemeController, bool>((t) => t.touchMode);
}
