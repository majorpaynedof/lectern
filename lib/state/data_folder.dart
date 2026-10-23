import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Early builds kept their data (login, settings, downloads) in
/// %APPDATA%\com.example\lectern, Flutter's placeholder company name. Builds
/// now say "Lectern" instead, so the folder is %APPDATA%\Lectern\Lectern.
/// This moves the old folder across once, before anything reads it.
Future<void> moveOldDataFolder() async {
  if (!Platform.isWindows) return;
  try {
    final appData = Platform.environment['APPDATA'];
    if (appData == null) return;
    final old = Directory('$appData\\com.example\\lectern');
    if (!await old.exists()) return;

    final current = await getApplicationSupportDirectory();
    if (_same(current.path, old.path)) return; // runner not renamed yet
    if (await current.exists()) {
      // path_provider creates it; only replace it while it's still empty.
      if (await current.list().isEmpty) {
        await current.delete();
      } else {
        return;
      }
    }
    await current.parent.create(recursive: true);
    await old.rename(current.path);
    debugPrint('Moved Lectern data from ${old.path} to ${current.path}');
    // Tidy up the empty com.example folder.
    final company = old.parent;
    if (await company.list().isEmpty) await company.delete();
  } catch (e) {
    debugPrint('Could not move the old data folder: $e');
  }
}

bool _same(String a, String b) =>
    a.toLowerCase().replaceAll('/', '\\') == b.toLowerCase().replaceAll('/', '\\');
